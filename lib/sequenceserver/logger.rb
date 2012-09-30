require 'logger'

module SequenceServer

  Log = Logger.new(STDERR)

  # We change Logging format so that it is consistent with Sinatra's
  Log.formatter = Class.new Logger::Formatter do

    def initialize
      self.datetime_format = "%Y-%m-%d %H:%M:%S"
    end

    def format
      "[%s] %s  %s\n"
    end

    def call(severity, time, progname, msg)
      format % [format_datetime(time), severity, msg2str(msg)]
    end
  end.new
end
