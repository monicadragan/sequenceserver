require 'rack/handler'

class SequenceServer

  class Server

    attr_reader :app, :port

    def initialize(app)
      @server = Rack::Handler.default
      @app    = app
      optspec.order!
    rescue OptionParser::InvalidOption => e
      puts e
      puts "Run '#{$0} server -h' for help with command line options."
      exit
    end

    def run
      url = "http://localshost:#{options['port']}"
      puts "\n== Launched SequenceServer at: #{url}"
      puts "== Press CTRL + C to quit."

      server.run(app,
                  :Port   => port,
                  :Logger => Logger.new('/dev/null')) do |server|
        # for Thin
        server.silent = true if server.respond_to? :silent

        [:INT, :TERM].each do |sig|
          trap(sig) do
            server.respond_to?(:stop!) ? server.stop! : server.stop
            puts "\n== Thank you for using SequenceServer :)." +
                "\n== Please cite: " +
                "\n==             Priyam A., Woodcroft B.J., Wurm Y (in prep)." +
                "\n==             Sequenceserver: BLAST searching made easy."
          end
        end
      end
    rescue Errno::EADDRINUSE, RuntimeError
      puts "\n== Failed to start SequenceServer."
      puts "== Is SequenceServer already running at: #{url}?"
    end

    def port
      options['port']
    end

    def options
      @options ||= {
        'port' => 4567
      }
    end

    def optspec
      @optspec ||= OptionParser.new do |opts|
        opts.banner =<<BANNER

SUMMARY

  launch the builtin server

USAGE

  sequenceserver [options] server [server options]

  Example:

    # launch server with the default config file
    $ sequenceserver server

    # launch server with a different configuration file
    $ sequenceserver --config ~/.sequenceserver.ants.conf server

DESCRIPTION

  Launch the builtin server.  This is the default command, i.e. simply running
  `sequenceserver` from the command line is equivalent to `sequenceserver
  server`.

OPTIONS

BANNER
        opts.on('-p', '--port PORT', 'Port to run SequenceServer on') do |port|
          begin
            options['port'] = Integer(port)
          rescue ArgumentError
            puts "Port should be a number. Typo?"
            exit
          end
        end
      end
    end

    private

    attr_reader :server
  end
end
