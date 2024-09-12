require "random/secure"

require "crinja"

require "./util"
require "./util/shell"
require "./job"
require "./cleanup"

class AssetSniper::Execute
  include Util
  include Util::Shell

  getter input_file_path : String
  getter output_file_path : String
  getter command : String
  getter jobs : Int32
  getter jobs_count : Int32 = 0
  getter command : String
  getter task_name : String
  getter task_code : String
  getter start_time = Time.monotonic
  getter job_task_dir : String
  getter stream : Bool
  getter debug : Bool

  def initialize(input_file_path : String, output_file_path : String, command : String, jobs : Int32, task : String = "", stream : Bool = false, debug : Bool = false)
    @input_file_path = input_file_path
    @output_file_path = output_file_path
    @command = command
    @jobs = jobs
    @task_code = task.blank? ? Random::Secure.hex(4) : task
    @task_name = "asset-sniper-task-#{task_code}"
    @job_task_dir = "/tmp/#{task_name}"
    @stream = stream
    @debug = debug

    setup_signal_handler
  end

  def run
    begin
      create_input_artifacts

      puts "\nRunning Asset Sniper task #{task_code} with #{jobs_count} jobs..."

      print_elapsed_time unless stream || debug

      execute_jobs
      aggregate_output

      puts
      puts "\nTask #{task_code} completed."

    rescue e : Exception
      puts "\nTask #{task_code} failed: #{e.message}"
    ensure
      cleanup
    end

    print_elapsed_time
  end

  private def create_input_artifacts
    puts "\nPreparing input files for #{jobs} jobs..."

    input_file = File.read(input_file_path)
    lines = input_file.lines
    @jobs_count = [jobs, lines.size].min
    split_content = Array.new(jobs_count) { [] of String }

    lines.each_with_index do |line, index|
      split_content[index % jobs] << "#{line}\n"
    end

    FileUtils.rm_rf(job_task_dir)
    Dir.mkdir_p(job_task_dir)

    split_content.map_with_index do |content, index|
      input_file_path = File.join("/tmp/#{task_name}", "input-#{index}.yaml")
      File.write(input_file_path, content.join)
      input_file_path
    end
  end

  private def aggregate_output
    run_shell_command("cat /tmp/#{task_name}/output-* > #{output_file_path}", error_message: "Failed to aggregate output", print_output: debug)
  end

  private def execute_jobs
    jobs_channel = Channel(Job).new

    puts "\nWaiting for all pods to be ready..."

    jobs_template = jobs_count.times.map do |job_id|
      spawn do
        job = Job.new(task_name: task_name, job_id: job_id, command: command, start_time: start_time, stream: stream, debug: debug)
        job.create
        jobs_channel.send(job)
      end
    end.join("\n---\n")

    jobs = [] of Job

    jobs_count.times do
      jobs << jobs_channel.receive
    end

    update_proxy

    jobs.each do |job|
      spawn do
        job.run
        jobs_channel.send(job)
      end
    end

    jobs_count.times do
      jobs_channel.receive
    end
  end

  private def update_proxy
    puts "\nWaiting for proxy to be ready..."

    cmd = <<-CMD
      kubectl rollout status daemonset asset-sniper-proxy -n default

      for POD in $(kubectl get pods -n default -l app=asset-sniper-ip-rotator -o jsonpath='{.items[*].metadata.name}'); do
        kubectl exec -n default $POD -c config-updater -- /bin/sh /scripts/update_haproxy_cfg.sh
      done
    CMD

    run_shell_command(cmd, error_message: "Failed to aggregate output", print_output: debug)
  end

  private def cleanup
    FileUtils.rm_rf(job_task_dir)

    AssetSniper::Cleanup.new(task_name: task_name, debug: debug).run
  end

  private def setup_signal_handler
    Signal::INT.trap do
      puts "\nInterrupted! Either reconnect to the existing task #{task_code} with the `reconnect` command or run the `cleanup` command to clean up the task."
      exit
    end
  end

  private def print_elapsed_time
    spawn do
      loop do
        elapsed = Time.monotonic - start_time
        elapsed_str = format_elapsed_time(elapsed)

        print "\rElapsed time: #{elapsed_str} ".colorize.fore(:green)
        STDOUT.flush

        sleep 1
      end
    end
  end
end
