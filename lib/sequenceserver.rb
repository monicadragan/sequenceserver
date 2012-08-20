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

    configure do
      set :log, Log
    end

    # Settings for the self hosted server.
    configure do
      # The port number to run SequenceServer standalone.
      set :port, 4567
    end

    class << self
      # Run SequenceServer as a self-hosted server.
      #
      # By default SequenceServer uses Thin, Mongrel or WEBrick (in that
      # order). This can be configured by setting the 'server' option.
      def run!(options={})
        set options

        # perform SequenceServer initializations
        puts "\n== Initializing SequenceServer..."

        # find out the what server to host SequenceServer with
        handler      = detect_rack_handler
        handler_name = handler.name.gsub(/.*::/, '')

        puts
        log.info("Using #{handler_name} web server.")

        if handler_name == 'WEBrick'
          puts "\n== We recommend using Thin web server for better performance."
          puts "== To install Thin: [sudo] gem install thin"
        end

        url = "http://#{bind}:#{port}"
        puts "\n== Launched SequenceServer at: #{url}"
        puts "== Press CTRL + C to quit."
        handler.run(new, :Host => bind, :Port => port, :Logger => Logger.new('/dev/null')) do |server|
          [:INT, :TERM].each { |sig| trap(sig) { quit!(server, handler) } }
          set :running, true

          # for Thin
          server.silent = true if handler_name == 'Thin'
        end
      rescue Errno::EADDRINUSE, RuntimeError => e
        puts "\n== Failed to start SequenceServer."
        puts "== Is SequenceServer already running at: #{url}"
      end

      # Stop SequenceServer.
      def quit!(server, handler_name)
        # Use Thin's hard #stop! if available, otherwise just #stop.
        server.respond_to?(:stop!) ? server.stop! : server.stop
        puts "\n== Thank you for using SequenceServer :)." +
             "\n== Please cite: " +
             "\n==             Priyam A., Woodcroft B.J., Wurm Y (in prep)." +
             "\n==             Sequenceserver: BLAST searching made easy." unless handler_name =~/cgi/i
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
