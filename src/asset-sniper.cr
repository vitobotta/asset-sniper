require "admiral"

require "./execute"

module AssetSniper
  class CLI < Admiral::Command
    VERSION = "0.1.0"

    class Execute < Admiral::Command
      define_help description: "execute - Run a command"

      define_flag input_file_path : String,
                  description: "The path of the input text file",
                  long: "input",
                  short: "i",
                  required: true

      define_flag output_file_path : String,
                  description: "The path of the output text file",
                  long: "output",
                  short: "o",
                  required: true

      define_flag command : String,
                  description: "The command to run",
                  long: "command",
                  short: "c",
                  required: true

      define_flag jobs : Int16,
                  description: "The number of jobs to run in parallel",
                  long: "jobs",
                  short: "j",
                  required: true

      def run
        AssetSniper::Execute.new(flags.input_file_path, flags.output_file_path, flags.command, flags.jobs).run
      end
    end

    define_version VERSION

    define_help description: "asset-sniper - A tool to distribute recon work across multiple Kubernetes jobs"

    register_sub_command execute : Execute, description: "Run a recon tool in a distributed manner"

    def run
      puts help
    end
  end
end

AssetSniper::CLI.run
