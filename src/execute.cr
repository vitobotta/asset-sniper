require "random/secure"

require "./util"
require "./util/shell"

class AssetSniper::Execute
  include Util
  include Util::Shell

  getter input_file_path : String
  getter output_file_path : String
  getter command : String
  getter jobs : Int32
  getter jobs_count : Int32 = 0
  getter command : String
  getter args : Array(String)

  def initialize(input_file_path : String, output_file_path : String, command : String, jobs : Int32)
    @input_file_path = input_file_path
    @output_file_path = output_file_path
    command_parts = command.split(" ")
    @command = command_parts[0]
    @args = command_parts.size > 1 ? command_parts[1..].map { |arg| "\"#{arg}\"" } : [] of String
    @jobs = jobs
  end

  def run
    create_input_artifacts
    create_jobs
    wait_for_pods
    upload_artifacts
  end

  private def job_batch_name
    @job_batch_name ||= "asset-sniper-job-batch-#{Random::Secure.hex(4)}"
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

    Dir.delete(job_batch_dir) if Dir.exists?(job_batch_dir)
    Dir.mkdir_p(job_batch_dir)

    split_content.map_with_index do |content, index|
      input_file_path = File.join("/tmp/#{job_batch_name}", "input-#{index}.yaml")
      File.write(input_file_path, content.join)
      input_file_path
    end
  end

  private def job_template(job_id : Int32) : String
    <<-YAML
    apiVersion: v1
    kind: Pod
    metadata:
      name: #{job_name(job_id)}
      labels:
        job_batch: #{job_batch_name}
        job-name: #{job_name(job_id)}
    spec:
      containers:
        - name: asset-sniper
          image: vitobotta/assetsniper:vbefb074
          imagePullPolicy: IfNotPresent
          command: ["/bin/sh", "-c"]
          args: ["tail -f /dev/null"]
          resources:
            requests:
              cpu: 0.5
              memory: 25Mi
      restartPolicy: Never
    YAML
  end

  private def job_name(index)
    "#{job_batch_name}-job-#{index}"
  end

  private def create_jobs
    jobs_template = jobs_count.times.map do |job_id|
      job_template(job_id)
    end.join("\n---\n")

    jobs_template_temp_file = File.join("/tmp/#{job_batch_name}", "#{job_batch_name}-jobs.yaml")
    File.write(jobs_template_temp_file, jobs_template)

    puts "Creating jobs..."

    run_shell_command("kubectl apply -f #{jobs_template_temp_file}", error_message = "Failed creating jobs")
  end

  private def wait_for_pods
    cmd = "kubectl wait --for=condition=Ready pod -l job_batch=#{job_batch_name}"

    run_shell_command(cmd, error_message = "Failed waiting for pods")
  end

  private def upload_artifacts
    jobs_count.times do |job_id|
      input_file_path = File.join("/tmp/#{job_batch_name}", "input-#{job_id}.yaml")

      cmd = <<-CMD
      pod_name=$(kubectl get pods --selector=job-name=#{job_name(job_id)} -o jsonpath='{.items[*].metadata.name}')
      kubectl cp #{input_file_path} $pod_name:/input
      CMD

      run_shell_command(cmd, error_message = "Failed uploading artifacts")
    end
  end
end
