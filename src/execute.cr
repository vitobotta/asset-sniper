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
  private property done_cleanup : Bool = false

  def initialize(input_file_path : String, output_file_path : String, command : String, jobs : Int32, task : String = "")
    @input_file_path = input_file_path
    @output_file_path = output_file_path
    @command = command
    @jobs = jobs
    @task_code = task.blank? ? Random::Secure.hex(4) : task
    @task_name = "asset-sniper-task-#{task_code}"
  end

  def run
    puts "Running Asset Sniper task #{task_code}..."

    Signal::INT.trap do
      cleanup
      exit
    end

    at_exit do
      cleanup
    end

    begin
      create_input_artifacts
      create_dns_resolvers_configmap_template
      execute_jobs
      aggregate_output
    rescue ex
      puts "An error occurred: #{ex.message}"
      cleanup
    end

    puts
    puts "Task #{task_code} completed."
  end

  private def create_input_artifacts
    input_file = File.read(input_file_path)
    lines = input_file.lines
    @jobs_count = [jobs, lines.size].min
    split_content = Array.new(jobs_count) { [] of String }

    lines.each_with_index do |line, index|
      split_content[index % jobs] << "#{line}\n"
    end

    job_task_dir = "/tmp/#{task_name}"

    FileUtils.rm_rf(job_task_dir)
    Dir.mkdir_p(job_task_dir)

    split_content.map_with_index do |content, index|
      input_file_path = File.join("/tmp/#{task_name}", "input-#{index}.yaml")
      File.write(input_file_path, content.join)
      input_file_path
    end
  end

  private def create_dns_resolvers_configmap_template
    yaml = Crinja.render(CONFIG_MAP_TEMPLATE, {
      task_name: task_name
    })

    cmd = <<-CMD
    kubectl apply -f - <<-YAML
    #{yaml}
    YAML
    CMD

    run_shell_command(cmd, error_message: "Failed creating ConfigMap with DNS resolvers")
  end

  private def aggregate_output
    run_shell_command("cat /tmp/#{task_name}/output-* > #{output_file_path}", error_message: "Failed aggregating results")
  end

  private def execute_jobs
    jobs_channel = Channel(Nil).new

    jobs_template = jobs_count.times.map do |job_id|
      spawn do
        Job.new(task_name, job_id, command).run

        jobs_channel.send(nil)
      end
    end.join("\n---\n")

    jobs_count.times do
      jobs_channel.receive
    end
  end

  private def cleanup
    return if done_cleanup

    AssetSniper::Cleanup.new(task_name).run

    @done_cleanup = true
  end
end
