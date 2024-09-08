require "random/secure"

require "crinja"

require "./util"
require "./util/shell"
require "./job"
require "./cleanup"

class AssetSniper::Execute
  include Util
  include Util::Shell

  CONFIG_MAP_TEMPLATE = {{ read_file("#{__DIR__}/templates/configmap.yaml") }}

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

  def initialize(input_file_path : String, output_file_path : String, command : String, jobs : Int32, task : String = "")
    @input_file_path = input_file_path
    @output_file_path = output_file_path
    @command = command
    @jobs = jobs
    @task_code = task.blank? ? Random::Secure.hex(4) : task
    @task_name = "asset-sniper-task-#{task_code}"
    @job_task_dir = "/tmp/#{task_name}"

    setup_signal_handler
  end

  def run
    begin
      puts "Running Asset Sniper task #{task_code} with #{jobs_count} jobs..."

      create_input_artifacts
      print_elapsed_time

      create_dns_resolvers_configmap
      execute_jobs
      aggregate_output

      puts
      puts "Task #{task_code} completed."

    rescue e : Exception
      puts "Task #{task_code} failed: #{e.message}"
    ensure
      cleanup
    end
  end

  private def create_input_artifacts
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

  private def create_dns_resolvers_configmap
    yaml = Crinja.render(CONFIG_MAP_TEMPLATE, {
      task_name: task_name
    })

    cmd = <<-CMD
    kubectl apply -f - <<-YAML
    #{yaml}
    YAML
    CMD

    run_shell_command(cmd, print_output: false)
  end

  private def aggregate_output
    run_shell_command("cat /tmp/#{task_name}/output-* > #{output_file_path}", print_output: false)
  end

  private def execute_jobs
    jobs_channel = Channel(Nil).new

    jobs_template = jobs_count.times.map do |job_id|
      spawn do
        Job.new(task_name, job_id, command, start_time).run
        jobs_channel.send(nil)
      end
    end.join("\n---\n")

    jobs_count.times do
      jobs_channel.receive
    end
  end

  private def cleanup
    FileUtils.rm_rf(job_task_dir)

    AssetSniper::Cleanup.new(task_name).run
  end

  private def setup_signal_handler
    Signal::INT.trap do
      puts "Interrupted! Either reconnect to the existing task #{task_code} with the `reconnect` command or run the `cleanup` command to clean up the task."
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
