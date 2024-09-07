module Util
  def which(command)
    exts = ENV.fetch("PATHEXT", "").split(";")
    paths = ENV["PATH"]?.try(&.split(Process::PATH_DELIMITER)) || [] of String

    paths.each do |path|
      exts.each do |ext|
        exe = File.join(path, "#{command}#{ext}")
        return exe if File.executable?(exe) && !File.directory?(exe)
      end
    end

    nil
  end
end
