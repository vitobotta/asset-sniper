require "crinja"

require "./util"
require "./util/shell"

class Job
  include Util
  include Util::Shell

  POD_TEMPLATE = {{ read_file("#{__DIR__}/templates/pod.yaml") }}

  getter job_batch_name : String
  getter job_name : String
  getter job_id : Int32
  getter command : String

  def initialize(job_batch_name : String, job_id : Int32, command : String)
    @job_batch_name = job_batch_name
    @job_id = job_id
    @job_name = "#{job_batch_name}-job-#{job_id}"
    @command = command
  end

  def run
    create_job
    wait_for_pod
    upload_artifact
    run_command
    extract_output
  end

  private def create_job
    yaml = Crinja.render(POD_TEMPLATE, {
      job_batch_name: job_batch_name,
      job_name: job_name
    })

    temp_file_path = "/tmp/#{job_batch_name}/job-#{job_id}.yaml"
    File.write(temp_file_path, yaml)

    puts "Configuring job ##{job_id}..."

    run_shell_command("kubectl apply -f #{temp_file_path}", error_message: "Failed creating job ##{job_id}", print_output: false)
  end

  private def wait_for_pod
    run_shell_command("kubectl wait --for=condition=Ready pod -l job-name=#{job_name} --timeout=10m", error_message: "Failed waiting for pod ##{job_id}", print_output: false)
    puts "Pod ##{job_id} is ready"
  end

  private def upload_artifact
    input_file_path = File.join("/tmp/#{job_batch_name}", "input-#{job_id}.yaml")

    run_shell_command("kubectl cp -c asset-sniper #{input_file_path} #{pod_name}:/input", error_message: "Failed uploading artifact for job ##{job_id}")
  end

  private def already_running
    tool = command.split(" ").first
    output = run_shell_command("kubectl exec #{pod_name} -c asset-sniper -- /bin/sh -c \"if test -f /output; then echo 1; else echo 0; fi\"", error_message: "Failed to check if tool is already running for job ##{job_id}", print_output: false).output.chomp
    output == "1"
  end

  private def run_command
    if already_running
      run_shell_command("kubectl exec #{pod_name} -c asset-sniper -- /bin/sh -c \"tail -f /output\"", error_message: "Failed to stream output for job ##{job_id}")
    else
      run_shell_command("kubectl exec #{pod_name} -c asset-sniper -- /bin/sh -c \"cat /input | #{command} | tee /output\"", error_message: "Failed uploading artifact for job ##{job_id}")
    end
  end

  private def extract_output
    run_shell_command("kubectl cp -c asset-sniper #{pod_name}:/output /tmp/#{job_batch_name}/output-#{job_id} > /dev/null 2>&1", error_message: "Failed extracting output for job ##{job_id}")
  end

  private def pod_name
    run_shell_command(command: "kubectl get pods --selector=job-name=#{job_name} -o jsonpath='{.items[*].metadata.name}'", print_output: false).output
  end
end
