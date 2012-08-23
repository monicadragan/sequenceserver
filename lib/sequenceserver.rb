# sequenceserver.rb

require 'sinatra/base'
require 'logger'
require 'sequenceserver/env'
require 'sequenceserver/settings'
require 'sequenceserver/blast'
require 'sequenceserver/sequencehelpers'
require 'sequenceserver/sinatralikeloggerformatter'
require 'sequenceserver/customisation'
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
    include SequenceServer::Customisation

    # Basic configuration settings for app.
    configure do
      # enable some builtin goodies
      enable :session, :logging

      # enable trapping internal server error in controller
      disable :show_exceptions

      # main application file
      set :app_file,   File.expand_path(__FILE__)

      # app root is SequenceServer's installation directory
      #
      # SequenceServer figures out different settings, location of static
      # assets or templates for example, based on app root.
      set :root,       File.dirname(File.dirname(app_file))

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

    def initialize
      super

      settings = SequenceServer.settings
      @blast = Blast.new(settings.binaries, settings.databases, 'num_threads' => settings.num_threads)
    end

    attr_reader :blast

    get '/' do
      erb :search
    end

    post '/' do
      method    = params[:method]
      sequences = params[:sequences]
      databases = params[:databases]
      options   = params[:options]

      # log params
      settings.log.debug('method    : ' + method.to_s)
      settings.log.debug('sequences : ' + sequences.to_s)
      settings.log.debug('databases : ' + databases.inspect)
      settings.log.debug('options   : ' + options.to_s)

      query = blast.run(method, sequences, databases, options)
      format_blast_results(query.result, databases)
    end

    # get '/get_sequence/?id=sequence_ids&db=retreival_databases'
    #
    # Use whitespace to separate entries in sequence_ids (all other chars exist
    # in identifiers) and retreival_databases (we don't allow whitespace in a
    # database's name, so it's safe).
    get '/get_sequence/' do
      sequence_ids = params[:id].split(/\s/).uniq  # in a multi-blast
      database_ids = params[:db].split(/\s/)

      # BLAST+ does not indicate which database a hit is from.  Thus if several
      # databases were used for blasting, we must check them all.
      settings.log.info("Searching for: '#{sequence_ids.join(', ')}' in '#{database_ids.join(', ')}'")

      sequences  = blast.get(sequence_ids, *database_ids)
      nsequences = sequences.count('>')

      out = ''
      # just in case, checking we found right number of sequences
      if nsequences != sequence_ids.length
        out <<<<HEADER
<h1>ERROR: incorrect number of sequences found.</h1>
<p>Dear user,</p>

<p><strong>We have found
<em>#{nsequences > sequence_ids.length ? 'more' : 'less'}</em>
sequence than expected.</strong></p>

<p>This is likely due to a problem with how databases are formatted. 
<strong>Please share this text with the person managing this website so 
they can resolve the issue.</strong></p>

<p> You requested #{sequence_ids.length} sequence#{sequence_ids.length > 1 ? 's' : ''}
with the following identifiers: <code>#{sequence_ids.join(', ')}</code>,
from the following databases: <code>#{retrieval_databases.join(', ')}</code>.
But we found #{nsequences} sequence#{nsequences > 1 ? 's' : ''}.
</p>

<p>If sequences were retrieved, you can find them below (but some may be incorrect, so be careful!).</p>
<hr/>
HEADER
      end

      out << "<pre><code>#{sequences}</pre></code>"
      out
    end

    error 400 do
      error = env['sinatra.error']
      Log.error(error) # TODO: figure out how to make Sinatra log this automatically with backtrace, like InternalServerError (500).
      erb :'errors/400', :locals => {:error => error}
    end

    error 500 do
      erb :'errors/500', :locals => {:error => env['sinatra.error']}
    end

    def format_blast_results(result, databases)
      formatted_result = ''
      @all_retrievable_ids = []
      string_of_used_databases = databases.join(' ')
      blast_database_number = 0
      line_number = 0
      started_query = false
      finished_database_summary = false
      finished_alignments = false
      reference_string = ''
      database_summary_string = ''
      result.each do |line|
        line_number += 1
        next if line_number <= 5 #skip the first 5 lines

        # Add the reference to the end, not the start, of the blast result
        if line_number >= 7 and line_number <= 15
          reference_string += line
          next
        end

        if !finished_database_summary and line_number > 15
          database_summary_string += line
          finished_database_summary = true if line.match(/total letters/)
          next
        end

        # Remove certain lines from the output
        skipped_lines = [/^<\/BODY>/,/^<\/HTML>/,/^<\/PRE>/]
        skip = false
        skipped_lines.each do |skippy|
        #  $stderr.puts "`#{line}' matches #{skippy}?"
          if skippy.match(line)
            skip = true
         #   $stderr.puts 'yes'
          else
          #  $stderr.puts 'no'
          end
        end
        next if skip

        # Remove the javascript inclusion
        line.gsub!(/^<script src=\"blastResult.js\"><\/script>/, '')

        if line.match(/^>/) # If line to possibly replace
          # Reposition the anchor to the end of the line, so that it both still works and
          # doesn't interfere with the diagnostic space at the beginning of the line.
          #
          # There are two cases:
          #
          # database formatted _with_ -parse_seqids
          line.gsub!(/^>(.+)(<a.*><\/a>)(.*)/, '>\1\3\2')
          #
          # database formatted _without_ -parse_seqids
          line.gsub!(/^>(<a.*><\/a>)(.*)/, '>\2\1')

          # get hit coordinates -- useful for linking to genome browsers
          hit_length      = result[line_number..-1].index{|l| l =~ />lcl|Lambda/}
          hit_coordinates = result[line_number, hit_length].grep(/Sbjct/).
            map(&:split).map{|l| [l[1], l[-1]]}.flatten.map(&:to_i).minmax

          # Create the hyperlink (if required)
          formatted_result += construct_sequence_hyperlink_line(line, databases, hit_coordinates)
        else
          # Surround each query's result in <div> tags so they can be coloured by CSS
          if matches = line.match(/^<b>Query=<\/b> (.*)/) # If starting a new query, then surround in new <div> tag, and finish the last one off
            line = "<div class=\"resultn\" id=\"#{matches[1]}\">\n<h3>Query= #{matches[1]}</h3><pre>"
            unless blast_database_number == 0
              line = "</pre></div>\n#{line}"
            end
            blast_database_number += 1
          elsif line.match(/^  Database: /) and !finished_alignments
            formatted_result += "</div>\n<pre>#{database_summary_string}\n\n"
            finished_alignments = true
          end
          formatted_result += line
        end
      end
      formatted_result << "</pre>"

      link_to_fasta_of_all = "/get_sequence/?id=#{@all_retrievable_ids.join(' ')}&db=#{string_of_used_databases}"
      # #dbs must be sep by ' '
      retrieval_text       = @all_retrievable_ids.empty? ? '' : "<a href='#{url(link_to_fasta_of_all)}'>FASTA of #{@all_retrievable_ids.length} retrievable hit(s)</a>"

      "<h2>Results</h2>"+
      retrieval_text +
      "<br/><br/>" +
      formatted_result +
      "<br/>" +
      "<pre>#{reference_string.strip}</pre>"
    end

    def construct_sequence_hyperlink_line(line, databases, hit_coordinates)
      matches = line.match(/^>(.+)/)
      sequence_id = matches[1]

      link = nil

      # If a custom sequence hyperlink method has been defined,
      # use that.
      options = {
        :sequence_id => sequence_id,
        :databases => databases,
        :hit_coordinates => hit_coordinates
      }

      # First precedence: construct the whole line to be customised
      if self.respond_to?(:construct_custom_sequence_hyperlinking_line)
        settings.log.debug("Using custom hyperlinking line creator with sequence #{options.inspect}")
        link_line = construct_custom_sequence_hyperlinking_line(options)
        unless link_line.nil?
          return link_line
        end
      end

      # If we have reached here, custom construction of the
      # whole line either wasn't defined, or returned nil
      # (indicating failure)
      if self.respond_to?(:construct_custom_sequence_hyperlink)
        settings.log.debug("Using custom hyperlink creator with sequence #{options.inspect}")
        link = construct_custom_sequence_hyperlink(options)
      else
        settings.log.debug("Using standard hyperlink creator with sequence `#{options.inspect}'")
        link = construct_standard_sequence_hyperlink(options)
      end

      # Return the BLAST output line with the link in it
      if link.nil?
        settings.log.debug('No link added link for: `'+ sequence_id +'\'')
        return line
      else
        settings.log.debug('Added link for: `'+ sequence_id +'\''+ link)
        return "><a href='#{url(link)}'>#{sequence_id}</a> \n"
      end

    end
  end
end
