require "random/secure"

require "./shell/command_result"

module Util
  module Shell
    def run_shell_command(command : String, kubeconfig_path : String = "~/.kube/config", error_message : String = "", abort_on_error  = true, print_output : Bool = true) : CommandResult
      cmd_file_path = "/tmp/cli_#{Random::Secure.hex(8)}.cmd"

      File.write(cmd_file_path, <<-CONTENT
      set -euo pipefail
      #{command}
      CONTENT
      )

      File.chmod(cmd_file_path, 0o700)

      stdout = IO::Memory.new
      stderr = IO::Memory.new

      if print_output
        all_io_out = IO::MultiWriter.new(STDOUT, stdout)
        all_io_err = IO::MultiWriter.new(STDERR, stderr)
      else
        all_io_out = stdout
        all_io_err = stderr
      end

      env = {
        # "KUBECONFIG" => kubeconfig_path
        "LANG" => "en_US.UTF-8",
        "LC_ALL" => "en_US.UTF-8"
      }

      status = Process.run("bash",
        args: ["-c", cmd_file_path],
        env: env,
        output: all_io_out,
        error: all_io_err
      )

      FileUtils.rm_rf(cmd_file_path)

      output = status.success? ? stdout.to_s : stderr.to_s
      result = CommandResult.new(output, status.exit_code)

      unless result.success?
        puts "#{error_message}: #{result.output}"
        exit 1 if abort_on_error
      end

      result
    end
  end
end
