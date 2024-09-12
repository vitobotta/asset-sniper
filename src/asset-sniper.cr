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

      define_flag jobs : Int32,
                  description: "The number of jobs to run in parallel",
                  long: "jobs",
                  short: "j",
                  required: true,
                  default: 1

      define_flag stream : Bool,
                  description: "Stream the output of the jobs",
                  long: "stream",
                  short: "s",
                  required: false,
                  default: false

      define_flag debug : Bool,
                  description: "Enabled debug ouput",
                  long: "debug",
                  short: "d",
                  required: false

      def run
        AssetSniper::Execute.new(
          input_file_path: flags.input_file_path,
          output_file_path: flags.output_file_path,
          command: flags.command,
          jobs: flags.jobs,
          stream: flags.stream,
          debug: flags.debug
        ).run
      end
    end

    class Reconnect < Admiral::Command
      define_help description: "Reconnect - Reconnect to an existing task"

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

      define_flag task : String,
                  description: "The task to reconnect to",
                  long: "task",
                  short: "b",
                  required: true

      define_flag jobs : Int32,
                  description: "The number of jobs to run in parallel",
                  long: "jobs",
                  short: "j",
                  required: true

      define_flag stream : Bool,
                  description: "Stream the output of the jobs",
                  long: "stream",
                  short: "s",
                  required: false

      define_flag debug : Bool,
                  description: "Enabled debug ouput",
                  long: "debug",
                  short: "d",
                  required: false

      def run
        AssetSniper::Execute.new(
          input_file_path: flags.input_file_path,
          output_file_path: flags.output_file_path,
          command: flags.command,
          jobs: flags.jobs,
          stream: flags.stream,
          task: flags.task,
          debug: flags.debug
        ).run
      end
    end

    class Cleanup < Admiral::Command
      define_help description: "Cleanup - Remove an existing task"

      define_flag task : String,
                  description: "The task to reconnect to",
                  long: "task",
                  short: "b",
                  required: true

      define_flag debug : Bool,
                  description: "Enabled debug ouput",
                  long: "debug",
                  short: "d",
                  required: false

      def run
        AssetSniper::Cleanup.new(task_name: "asset-sniper-task-#{flags.task}", debug: flags.debug).run
      end
    end

    define_version VERSION

    define_help description: "asset-sniper - A tool to distribute recon work across multiple Kubernetes jobs"

    register_sub_command execute : Execute, description: "Run a recon tool in a distributed manner"
    register_sub_command reconnect : Reconnect, description: "Reconnect to an existing task"
    register_sub_command cleanup : Cleanup, description: "Remove an existing task"

    def run
      puts help
    end
  end
end

AssetSniper::CLI.run
