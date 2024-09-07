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
    run_shell_command("kubectl delete pods -l job_batch=#{task_name} --force --grace-period=0 2>/dev/null", error_message: "Failed removing pods")
    run_shell_command("kubectl delete configmap #{task_name}-dns-resolvers", error_message: "Failed removing configmap")
  end
end
