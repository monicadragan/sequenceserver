module SequenceServer

  class Logger < ::Logger
    # We change Logging format so that it is consistent with Sinatra's.
    class Formatter < ::Logger::Formatter
      Format = "[%s] %s  %s\n"
      def initialize
        self.datetime_format = "%Y-%m-%d %H:%M:%S"
      end
      def call(severity, time, progname, msg)
        Format % [format_datetime(time), severity, msg2str(msg)]
      end
    end

    def initialize(*args)
      super(*args)
      self.formatter = Formatter.new
    end
  end
end
