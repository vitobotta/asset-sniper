require "./util"
require "./util/shell"

class AssetSniper::Cleanup
  include Util
  include Util::Shell

  getter task_name : String

  def initialize(task_name : String)
    @task_name = task_name
  end

  def run
    puts "Cleaning up task #{task_name.split("-").last}..."

    delete_pods
    delete_configmap
  end

  private def pods_exist
    output = run_shell_command("kubectl get pods -l job_batch=#{task_name} --no-headers 2>/dev/null", print_output: false).output
    !output.empty?
  end

  private def delete_pods
    retry_three_times do
      while pods_exist
        run_shell_command("kubectl delete pods -l job_batch=#{task_name} --force --grace-period=0 2>/dev/null", print_output: false)
        sleep 1
      end
    end
  end

  private def configmap_exists
    output = run_shell_command("kubectl get configmap #{task_name}-dns-resolvers --no-headers 2>/dev/null", print_output: false).output
    !output.empty?
  end

  private def delete_configmap
    retry_three_times do
      while configmap_exists
        run_shell_command("kubectl delete configmap #{task_name}-dns-resolvers --force --grace-period=0 2>/dev/null", print_output: false)
        sleep 1
      end
    end
  end

  private def retry_three_times
    attempts = 0
    success = false
    while attempts < 3 && !success
      begin
        yield
        success = true
      rescue
        attempts += 1
        sleep 1 if attempts < 3
      end
    end
  end
end
