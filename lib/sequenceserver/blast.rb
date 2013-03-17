require 'sequenceserver/sequencehelpers'
require 'tempfile'

class SequenceServer

  # Simple wrapper around BLAST+ CLI (command line interface).
  #
  # `Blast` is an abstract class.  A concrete implementation must define
  # `runtime` instance method which returns a `SequenceServer` object, thus
  # providing the runtime context (location of BLAST databases, binaries, etc.)
  # in which a BLAST search should be evaluated.
  #
  # `Blast::ArgumentError` and `Blast::RuntimeError` signal errors encountered
  # when attempting a BLAST search.  The error classes define `code` instance
  # method which returns the equivalent HTTP status code, and is used by
  # Sinatra to dispatch appropriate error handlers to fulfill an HTTP request.
  class Blast

    include SequenceHelpers

    # To signal error in query sequence or options.
    #
    # ArgumentError is raised when BLAST+'s exit status is 1; see [1].
    class ArgumentError < ArgumentError

      # Instruct Sinatra to treat this exception object as HTTP BadRequest
      # (400).
      def code
        400
      end
    end

    # To signal internal errors.
    #
    # RuntimeError is raised when BLAST+'s exits status is one of 2, 3, 4, or
    # 255; see [1].  These are rare, infrastructure errors, used internally,
    # and of concern only to the admins/developers.
    class RuntimeError  < RuntimeError

      def initialize(status, message)
        @status  = status
        @message = message
      end

      attr_reader :status, :message

      # Instruct Sinatra to treat this exception object as HTTP
      # InternalServerError (500).
      def code
        500
      end

      def to_s
        "#{status}, #{message}"
      end
    end

    ERROR_LINE = /\(CArgException.*\)\s(.*)/

    # Capture results per query of a BLAST search.
    #
    # @member [String]     id
    # @member [String]     index
    # @member [Array(Hit)] hits
    Query = Struct.new(:id, :index, :hits)

    # Capture a BLAST search hit.
    #
    # @member [String] id
    # @member [String] meta
    # @member [String] alignments
    # @member [Array]  coordinates
    # @member [Database]  database
    Hit = Struct.new(:id, :meta, :alignments, :coordinates, :database) do

      # Include an anonymous module to define `refs` method so Hit can be
      # extended externally by including another module in front that calls
      # `super`.
      include Module.new {
        def refs
          @refs ||= {
            'FASTA' => "/get_sequence/?id=#{id}&db=#{database}"
          }
        end
      }
    end

    class << self
      # `Blast.run` captures the essence better.
      alias run new
    end

    # Run a BLAST search.  Returns `self` if the BLAST ran successfully.
    # Returns `nil` and raises `ArgumentError` or `RuntimeError`, if failed.
    #
    #     query = Blast.run("blastn", <<SEQ, "S.cdna.fasta", "-num_threads 4")
    #                       ATGTCCGCGAATCGATTGAACGTGCTGGTGACCCTGATGCTCGCCGTCG
    #     SEQ
    #
    #     puts query.result
    def initialize(method, sequences, databases, options = nil)
      @method    = method.to_s
      @sequences = sequences.to_s
      @databases = databases.to_a
      @options   = options.to_s

      compile! && run! && report!
    ensure
      [@qfile, @rfile, @efile].compact.each(&:close).each(&:unlink)
    end

    attr_reader :method, :sequences, :databases

    # Command ran.
    attr_reader :command

    # HTML formatted result.
    attr_reader :result

    # Summary of search parameters: database, matrix, gap penalties, etc.
    attr_reader :summary

    def ids
      queries.map do |query_id, query|
        query.hits.keys.to_a
      end.flatten
    end

    def each(&block)
      queries.each(&block)
    end

    private

    attr_reader :queries

    # Compile parameters for BLAST search into a shell executable command and
    # stores it in @command, and query sequence into @qfile.
    def compile!
      validate

      binary = runtime.binaries[@method]

      # BLAST+ expects query sequence as a file.
      @qfile = Tempfile.new('sequenceserver_query')
      @qfile.puts(@sequences)
      @qfile.close

      # map: database id -> file name
      db = @databases.map do |id|
        runtime.databases[id].name
      end.join(' ')

      options = @options + defaults

      @command = "#{binary} -db '#{db}' -query '#{@qfile.path}' #{options}"
    end

    # Runs BLAST search, and captures stdout and stderr of the command ran to
    # @rfile and @efile.
    def run!
      @rfile = Tempfile.new('sequenceserver_blast_result')
      @efile = Tempfile.new('sequenceserver_blast_error')
      [@rfile, @efile].each(&:close)

      system("#{command} > #{@rfile.path} 2> #{@efile.path}")

      status = $?.exitstatus
      case status
      when 1 # error in query sequence or options; see [1]
        @efile.open

        # Most of the time BLAST+ generates a verbose error message with
        # details we don't require.  So we parse out the relevant lines.
        error = @efile.each_line do |l|
          break Regexp.last_match[1] if l.match(ERROR_LINE)
        end

        # But sometimes BLAST+ returns the exact/relevant error message.
        # Trying to parse such messages returns nil, and we use the error
        # message from BLAST+ as it is.
        error = @efile.rewind && @efile.read unless error.is_a? String

        raise ArgumentError.new(error)
      when 2, 3, 4, 255 # see [1]
        @efile.open
        error = @efile.read
        raise RuntimeError.new(status, error)
      end

      @rfile.open
      @result = @rfile.readlines
    end

    def report!
      query_id = nil
      hit_id   = nil
      result.each do |line|
        next if /^<(\/)(HTML|BODY|PRE)/.match(line)

        if matches = line.match(/^<b>Query=<\/b> (.*)/)
          hit_id   = nil
          query_id = matches[1]
          @queries ||= {}
          @queries[query_id] = Query.new(query_id, '', {})
          next
        end

        # Parsing results of a query.
        if query_id
          # Remove the javascript inclusion
          line.gsub!(/^<script src=\"blastResult.js\"><\/script>/, '')

          if not hit_id and not line.match(/^>/)
            @queries[query_id].index << line
            next
          end

          if line.match(/^>/)
            hit_id, hit_meta = parse_fasta_header(line)
            # Identify which database hit came from
            hit_database = @databases.find{|db| !get_sequences(hit_id, db).empty?}
            @queries[query_id][:hits][hit_id] = Hit.new(hit_id, hit_meta, '', [], hit_database)
          else
            @queries[query_id].hits[hit_id].alignments << line
          end

          if line.match(/Query|Sbjct/)
            @queries[query_id].hits[hit_id].coordinates << parse_hit_coordinates(line)
          end
        end

        if line.match(/^  Database: /)
          query_id = nil
          hit_id   = nil
          @summary = ''
        end

        # FIXME: SS shouldn't really have to rely on BLAST output for this
        if @summary
          @summary << line
        end
      end
    end

    # Given a line of BLAST+'s HTML output, parse sequence id out of it.
    def parse_fasta_header(line)
      # Strip HTML from the output line, to get plain-text-FASTA-header of the
      # hit.
      header = line.gsub(/<\/?[^>]*>/, '')

      # Characters between leading greater than sign and first whitespace
      # comprise sequence id.
      header.match(/^>\s?(\S+)\s*(.*)/)[1..2]
    end

    # Compute hit coordinates -- useful for linking to genome browsers.
    def parse_hit_coordinates(line)
      line.split.values_at(1, -1)
    end

    def validate
      validate_method && validate_sequences &&
        validate_databases && validate_options
    end

    def validate_method
      unless runtime.binaries.include? @method
        raise ArgumentError.new("BLAST method should be one of:
                                #{runtime.binaries.keys.join(',')}.")
      end

      true
    end

    def validate_sequences
      if @sequences.empty?
        raise ArgumentError.new("Sequences should be a non-empty string.")
      end

      true
    end

    def validate_databases
      if @databases.empty? ||
        (runtime.databases.keys & @databases) != @databases # not a subset
        raise ArgumentError.new("Databases should be a list of one ore more
                                of the following ids:
                                #{runtime.databases.keys.join(',')}")
      end

      true
    end

    # Raises ArgumentError if an error has occurred, otherwise return true.
    def validate_options
      return true if @options.empty?

      unless @options =~ /\A[a-z0-9\-_\. ']*\Z/i
        raise ArgumentError.new("Invalid characters detected in options.")
      end

      disallowed_options = %w(-out -html -outfmt -db -query)
      disallowed_options.each do |o|
        if @options =~ /#{o}/i
          raise ArgumentError.new("Option \"#{o}\" is prohibited.")
        end
      end

      true
    end

    def defaults
      defaults = ' -html'

      # blastn implies blastn, not megablast; but let's not interfere if a user
      # specifies `task` herself.
      if @method == 'blastn' and not @options =~ /task/
        defaults << ' -task blastn'
      end

      defaults
    end
  end # Blast
end # SequenceServer

# References
# ----------
# [1]: http://www.ncbi.nlm.nih.gov/books/NBK1763/
