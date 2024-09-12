require "crinja"
require "colorize"

require "./util"
require "./util/shell"

class Job
  include Util
  include Util::Shell

  POD_TEMPLATE = {{ read_file("#{__DIR__}/templates/pod.yaml") }}

  getter task_name : String
  getter name : String
  getter job_id : Int32
  getter command : String
  getter start_time : Time::Span
  getter stream : Bool
  getter debug : Bool

  def initialize(task_name : String, job_id : Int32, command : String, start_time : Time::Span, stream : Bool = false, debug : Bool = false)
    @task_name = task_name
    @job_id = job_id
    @name = "#{task_name}-job-#{job_id}"
    @command = command
    @start_time = start_time
    @stream = stream
    @debug = debug
  end

  def create
    create_pod
    wait_for_pod
    upload_artifact
  end

  def run
    run_command
    extract_output
  end

  private def wait_for_pod
    run_shell_command("kubectl wait --for=condition=Ready pod -l job-name=#{name} --timeout=10m 2>/dev/null", error_message: "Job #{name} failed to start", print_output: debug)
  end

  private def upload_artifact
    input_file_path = File.join("/tmp/#{task_name}", "input-#{job_id}.yaml")

    run_shell_command("kubectl cp -c asset-sniper #{input_file_path} #{pod_name}:input", error_message: "Failed to upload input file for job #{name}", print_output: debug)
  end

  private def tool
    command.split(" ").first
  end

  private def running
    output = run_shell_command("kubectl exec #{pod_name} -c asset-sniper 2>/dev/null -- /bin/sh -c \"if ps waux | grep #{tool} | grep -v grep | grep -v '\[' > /dev/null; then echo #{pod_name}; else echo 0; fi\"", error_message: "Failed to check status of job #{name}", print_output: false).output.chomp
    output == "1"
  end

  private def run_command
    unless running
      puts "\nStarting job #{name}..."
      run_shell_command("kubectl exec #{pod_name} -c asset-sniper -- /bin/sh -c \"touch output && nohup sh -c '. /env-vars/proxy.env && cat input | #{command} 2>&1 | tee asset-sniper.log &'\"", error_message: "Failed to start job #{name}", print_output: stream)
    end

    job_wait_channel = Channel(Nil).new

    spawn do
      loop do
        break unless running
        sleep Random.rand(3..8)
      end

      puts "\nJob #{name} finished"

      job_wait_channel.send(nil)
    end

    job_wait_channel.receive
  end

  private def extract_output
    run_shell_command("kubectl cp -c asset-sniper #{pod_name}:output /tmp/#{task_name}/output-#{job_id} > /dev/null 2>&1", error_message: "Failed to extract output for job #{name}", print_output: debug)
  end

  private def pod_name
    run_shell_command(command: "kubectl get pods --selector=job-name=#{name} -o jsonpath='{.items[*].metadata.name}' 2>/dev/null", error_message: "Failed to determine pod name for job #{name}", print_output: false).output
  end

  private def create_pod
    yaml = Crinja.render(POD_TEMPLATE, {
      task_name: task_name,
      job_name: name
    })

    temp_file_path = "/tmp/#{task_name}/job-#{job_id}.yaml"
    File.write(temp_file_path, yaml)

    run_shell_command("kubectl apply -f #{temp_file_path}", error_message: "Failed to create pod for job #{name}", print_output: debug)
  end
end
