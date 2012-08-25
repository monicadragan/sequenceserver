require 'sinatra/base'
require 'sequenceserver/blast'
require 'sequenceserver/sequencehelpers'

module SequenceServer
  class WebBlast < Sinatra::Base

    # Basic configuration settings for app.
    configure do
      # Log HTTP requests in the common log format.
      enable :logging

      # Enable trapping internal server error in controller.
      disable :show_exceptions

      # Location of client code (erb, js, etc).
      set :root, File.expand_path('web_blast', File.dirname(__FILE__))
    end

    def initialize
      super

      settings = Settings.new
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
      Log.debug('method    : ' + method.to_s)
      Log.debug('sequences : ' + sequences.to_s)
      Log.debug('databases : ' + databases.inspect)
      Log.debug('options   : ' + options.to_s)

      query = blast.run(method, sequences, databases, options)
      format_blast_results(query.result, databases)
    end

    # get '/get_sequence/?id=sequence_ids&db=retreival_databases&download=true'
    #
    # Use whitespace to separate entries in sequence_ids (all other chars exist
    # in identifiers) and retreival_databases (we don't allow whitespace in a
    # database's name, so it's safe).
    get '/get_sequence/' do
      sequence_ids = params[:id].split(/\s/).uniq  # in a multi-blast
      database_ids = params[:db].split(/\s/)

      # BLAST+ does not indicate which database a hit is from.  Thus if several
      # databases were used for blasting, we must check them all.
      Log.info("Searching for: '#{sequence_ids.join(', ')}' in '#{database_ids.join(', ')}'")

      sequences  = blast.get(sequence_ids, *database_ids)

      if params[:download]
        download_name = "sequenceserver_#{sequence_ids.first}.txt"
        file = Tempfile.open(download_name) do |file|
          file.puts sequences
          file
        end

        send_file file.path, :filename => download_name
      end
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
          # Create the hyperlink (if required)
          formatted_result += format_hit_line!(line, line_number, result, databases)
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
      download_all_fasta   = "#{link_to_fasta_of_all}&download=true"
      # #dbs must be sep by ' '

      retrieval_text       = @all_retrievable_ids.empty? ? '' : "<a href='#{url(link_to_fasta_of_all)}'>FASTA of #{@all_retrievable_ids.length} hit(s)</a> <a class='pull-right icon-download-alt' href='#{download_all_fasta}'></a>"

      "<h2>Results</h2>"+
      retrieval_text +
      "<br/><br/>" +
      formatted_result +
      "<br/>" +
      "<pre>#{reference_string.strip}</pre>"
    end

    # Format `line`, `line_number` in BLAST search `result` generated from the
    # list of `databases`, to our liking.  And append parsed sequence ids to
    # @all_retrievable_ids.
    def format_hit_line!(line, line_number, result, databases)
      sequence_id = parse_sequence_id(line)

      unless sequence_id
        Log.debug "Database formatted without `-parse_seqids`. Hyperlinking hit-sequence disabled."
        return line
      end

      # Store id of all hits so we can generate "Download FASTA of all hits"
      # link later.
      (@all_retrievable_ids ||= []) << sequence_id

      hit_coordinates = parse_hit_coordinates(line_number, result)

      Log.debug "Generating retrieval hyperlink for: #{sequence_id}, #{hit_coordinates}."
      construct_sequence_hyperlink_line(sequence_id, databases, hit_coordinates)
    end

    # Given a line of BLAST+'s HTML output, parse sequence id out of it.
    def parse_sequence_id(line)
      # Strip HTML from the output line, to get plain-text-FASTA-header of the
      # hit.
      header = line.gsub(/<\/?[^>]*>/, '')

      # Characters between leading greater than sign and first whitespace
      # comprise sequence id.
      header[/^>(\S+)\s*.*/, 1]
    end

    # Compute hit coordinates -- useful for linking to genome browsers.
    def parse_hit_coordinates(line_number, result)
      hit_length      = result[line_number..-1].index{|l| l =~ />lcl|Lambda/}
      hit_coordinates = result[line_number, hit_length].grep(/Sbjct/).
        map(&:split).map{|l| [l[1], l[-1]]}.flatten.map(&:to_i).minmax
    end

    # Given sequence id, a list of databases, and hit_coordinates (optional),
    # return a URL that can be used to retrieve that sequence from user's
    # sequence database.
    def construct_sequence_hyperlink(sequence_id, databases, hit_coordinates = nil)
      "/get_sequence/?id=#{sequence_id}&db=#{databases.join(' ')}" # several dbs separate by ' '
    end

    # Given sequence id, a list of databases, and hit_coordinates (optional),
    # return a line to 'mark a hit', that will be slotted into formatted BLAST
    # result in place of the default BLAST+'s output.
    def construct_sequence_hyperlink_line(sequence_id, databases, hit_coordinates = nil)
      link     = construct_sequence_hyperlink(sequence_id, databases, hit_coordinates)
      download = "#{link}&download=true"
      "><a href='#{url(link)}'>#{sequence_id}</a> <a class='pull-right icon-download-alt' title='Download.' href='#{url(download)}'></a>\n"
    end
  end
end
