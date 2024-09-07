require "crinja"

require "./util"
require "./util/shell"

class Job
  include Util
  include Util::Shell

  POD_TEMPLATE = {{ read_file("#{__DIR__}/templates/pod.yaml") }}

  getter task_name : String
  getter job_name : String
  getter job_id : Int32
  getter command : String

  def initialize(task_name : String, job_id : Int32, command : String)
    @task_name = task_name
    @job_id = job_id
    @job_name = "#{task_name}-job-#{job_id}"
    @command = command
  end

  def run
    create_pod
    wait_for_pod
    upload_artifact
    run_command
    extract_output
  end

  private def wait_for_pod
    run_shell_command("kubectl wait --for=condition=Ready pod -l job-name=#{job_name} --timeout=10m", print_output: false)
  end

  private def upload_artifact
    input_file_path = File.join("/tmp/#{task_name}", "input-#{job_id}.yaml")

    run_shell_command("kubectl cp -c asset-sniper #{input_file_path} #{pod_name}:/input")
  end

  private def tool
    command.split(" ").first
  end

  private def running
    output = run_shell_command("kubectl exec #{pod_name} -c asset-sniper -- /bin/sh -c \"if pgrep #{tool} > /dev/null; then echo 1; else echo 0; fi\"", print_output: false).output.chomp
    output == "1"
  end

  private def run_command
    unless running
      run_shell_command("kubectl exec #{pod_name} -c asset-sniper -- /bin/sh -c \"nohup sh -c 'cat /input | #{command} > /output 2>&1 &'\"")
    end

    loop do
      break unless running
      print "."
      sleep 10
    end
  end

  private def extract_output
    run_shell_command("kubectl cp -c asset-sniper #{pod_name}:/output /tmp/#{task_name}/output-#{job_id} > /dev/null 2>&1")
  end

  private def pod_name
    run_shell_command(command: "kubectl get pods --selector=job-name=#{job_name} -o jsonpath='{.items[*].metadata.name}'", print_output: false).output
  end

  private def create_pod
    yaml = Crinja.render(POD_TEMPLATE, {
      task_name: task_name,
      job_name: job_name
    })

    temp_file_path = "/tmp/#{task_name}/job-#{job_id}.yaml"
    File.write(temp_file_path, yaml)

    run_shell_command("kubectl apply -f #{temp_file_path}", print_output: false)
  end
end
