require "random/secure"
require "crinja"

require "./util"
require "./util/shell"
require "./job"

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
  getter job_batch_name : String
  private property done_cleanup : Bool = false

  def initialize(input_file_path : String, output_file_path : String, command : String, jobs : Int32, batch : String = "")
    @input_file_path = input_file_path
    @output_file_path = output_file_path
    @command = command
    @jobs = jobs

    @job_batch_name = if batch.blank?
      "asset-sniper-batch-#{Random::Secure.hex(4)}"
    else
      "asset-sniper-batch-#{batch}"
    end
  end

  def run
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
  end

  private def create_input_artifacts
    puts "Creating input artifacts..."

    input_file = File.read(input_file_path)
    lines = input_file.lines
    @jobs_count = [jobs, lines.size].min
    split_content = Array.new(jobs_count) { [] of String }

    lines.each_with_index do |line, index|
      split_content[index % jobs] << "#{line}\n"
    end

    job_batch_dir = "/tmp/#{job_batch_name}"

    FileUtils.rm_rf(job_batch_dir)
    Dir.mkdir_p(job_batch_dir)

    split_content.map_with_index do |content, index|
      input_file_path = File.join("/tmp/#{job_batch_name}", "input-#{index}.yaml")
      File.write(input_file_path, content.join)
      input_file_path
    end
  end

  private def create_dns_resolvers_configmap_template
    yaml = Crinja.render(CONFIG_MAP_TEMPLATE, {
      job_batch_name: job_batch_name
    })

    cmd = <<-CMD
    kubectl apply -f - <<-YAML
    #{yaml}
    YAML
    CMD

    puts "Creating configmap with DNS resolvers..."

    run_shell_command(cmd, error_message: "Failed creating ConfigMap with DNS resolvers")
  end

  private def aggregate_output
    run_shell_command("cat /tmp/#{job_batch_name}/output-* > #{output_file_path}", error_message: "Failed aggregating results")
  end

  private def execute_jobs
    jobs_channel = Channel(Nil).new

    jobs_template = jobs_count.times.map do |job_id|
      spawn do
        Job.new(job_batch_name, job_id, command).run

        jobs_channel.send(nil)
      end
    end.join("\n---\n")

    jobs_count.times do
      jobs_channel.receive
    end
  end

  private def cleanup
    return
    return if done_cleanup

    puts "Cleaning up..."

    run_shell_command("kubectl delete pods -l job_batch=#{job_batch_name} --force --grace-period=0 2>/dev/null", error_message: "Failed uploading artifacts")
    run_shell_command("kubectl delete configmap #{job_batch_name}-dns-resolvers", error_message: "Failed uploading artifacts")

    @done_cleanup = true
  end
end
