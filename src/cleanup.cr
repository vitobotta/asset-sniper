require "./util"
require "./util/shell"

class AssetSniper::Cleanup
  include Util
  include Util::Shell

  getter job_batch_name : String

  def initialize(job_batch_name : String)
    @job_batch_name = job_batch_name
  end

  def run
    puts "Cleaning up ..."

    run_shell_command("kubectl delete pods -l job_batch=#{job_batch_name} --force --grace-period=0 2>/dev/null", error_message: "Failed removing pods")
    run_shell_command("kubectl delete configmap #{job_batch_name}-dns-resolvers", error_message: "Failed removing configmap")
  end
end
