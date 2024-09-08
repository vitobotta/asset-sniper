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
end
