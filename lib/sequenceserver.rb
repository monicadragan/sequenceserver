# sequenceserver.rb

require 'sinatra/base'
require 'logger'
require 'sequenceserver/env'
require 'sequenceserver/settings'
require 'sequenceserver/web_blast'
require 'sequenceserver/sinatralikeloggerformatter'
require 'sequenceserver/version'

# Helper module - initialize the blast server.
module SequenceServer

  # App-global logger.
  Log = Logger.new(STDERR)
  Log.formatter = SinatraLikeLogFormatter.new()

  env :development do
    Log.level = Logger::DEBUG
  end

  env :production do
    Log.level = Logger::INFO
  end

  class << self

    def settings
      @settings ||= Settings.new
    end
  end

  # Load user specific customization, if any.
  config_rb = settings.config_rb
  require "#{config_rb}" if config_rb

  class App < Sinatra::Base

    # Settings for the self hosted server.
    configure do
      # The port number to run SequenceServer standalone.
      set :port, 4567
    end

    class << self

      def run!(options={})
        url = "http://#{bind}:#{port}"
        puts "== Launching SequenceServer on \"#{url}\"... Done!"
        puts "== Press CTRL + C to quit."
        puts

        # Sinatra initializes the app the first time `call` is called.  But we
        # want the app to be initialized as soon as it starts.
        prototype

        mute_stderr do
          super
        end
      rescue Errno::EADDRINUSE, RuntimeError => e
        puts "== Failed to start SequenceServer."
        puts "== Is SequenceServer already running at: \"#{url}\"?"
      end

      def quit!(server, handler_name)
        puts
        puts "== Thank you for using SequenceServer :)."
        puts "== Please cite: "
        puts "==             Priyam A., Woodcroft B.J., Wurm Y (in prep),"
        puts "==             Sequenceserver: BLAST searching made easy."

        super
      end

      private

      def mute_stderr
        stderr  = $stderr
        $stderr = File.open('/dev/null', 'w')
        yield
        $stderr.close
        $stderr = stderr
      end
    end

    # App settings.
    configure do
      # Log HTTP requests in the common log format.
      enable :logging
    end

    def initialize
      super WebBlast
    end
  end
end
