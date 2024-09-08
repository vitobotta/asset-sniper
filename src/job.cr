require "crinja"
require "colorize"

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
  getter start_time : Time::Span

  def initialize(task_name : String, job_id : Int32, command : String, start_time : Time::Span)
    @task_name = task_name
    @job_id = job_id
    @job_name = "#{task_name}-job-#{job_id}"
    @command = command
    @start_time = start_time
  end

  def run
    create_pod
    wait_for_pod
    upload_artifact
    run_command
    extract_output
    delete_pod
  end

  private def wait_for_pod
    run_shell_command("kubectl wait --for=condition=Ready pod -l job-name=#{job_name} --timeout=10m 2>/dev/null", print_output: false)
  end

  private def upload_artifact
    input_file_path = File.join("/tmp/#{task_name}", "input-#{job_id}.yaml")

    run_shell_command("kubectl cp -c asset-sniper #{input_file_path} #{pod_name}:input")
  end

  private def tool
    command.split(" ").first
  end

  private def running
    output = run_shell_command("kubectl exec #{pod_name} -c asset-sniper 2>/dev/null -- /bin/sh -c \"if pgrep #{tool} > /dev/null; then echo 1; else echo 0; fi\"", print_output: false).output.chomp
    output == "1"
  end

  private def run_command
    unless running
      run_shell_command("kubectl exec #{pod_name} -c asset-sniper -- /bin/sh -c \"nohup sh -c 'cat input | #{command} | tee /log 2>&1 &'\"", print_output: false)
    end

    job_wait_channel = Channel(Nil).new

    spawn do
      loop do
        break unless running
        sleep 10
      end

      job_wait_channel.send(nil)
    end

    spawn do
      loop do
        elapsed = Time.monotonic - start_time
        elapsed_str = format_elapsed_time(elapsed)

        print "\rElapsed time: #{elapsed_str} ".colorize.fore(:green)
        STDOUT.flush

        sleep 1
      end
    end

    job_wait_channel.receive
  end

  private def extract_output
    run_shell_command("kubectl cp -c asset-sniper #{pod_name}:output /tmp/#{task_name}/output-#{job_id} > /dev/null 2>&1")
  end

  private def pod_name
    run_shell_command(command: "kubectl get pods --selector=job-name=#{job_name} -o jsonpath='{.items[*].metadata.name}' 2>/dev/null", print_output: false).output
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

  private def format_elapsed_time(span : Time::Span) : String
    hours = span.total_hours.to_i
    minutes = span.minutes
    seconds = span.seconds
    milliseconds = span.milliseconds

    if hours > 0
      sprintf("%02d:%02d", hours, minutes, seconds)
    else
      sprintf("%02d:%02d", minutes, seconds)
    end
  end

  private def delete_pod
    run_shell_command("kubectl delete pods -l job-name=#{job_name} --force --grace-period=0 2>/dev/null", print_output: false)
  end
end
