require 'tempfile'

module SequenceServer

  # Simple wrapper around BLAST+ CLI (command line interface).
  #
  # `Blast` defines runtime settings in which to evaluate a BLAST search:
  # location of BLAST+ binaries and databases, number of threads to use, etc.
  #
  # `Blast::Query` provides the interface to execute a BLAST search.
  #
  # `Blast::ArgumentError` and `Blast::RuntimeError` signal errors encountered
  # when attempting a BLAST search.  The error classes define `code` instance
  # method which returns the equivalent HTTP status code, and is used by
  # Sinatra to dispatch appropriate error handlers to fulfill an HTTP request.
  class Blast

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

    # Encapsulates a BLAST search.
    #
    # `Query` is an abstract class.  A concrete implementation must define
    # `runtime` instance method which returns a `Blast` object, thus providing
    # the runtime context (location of BLAST databases, etc.) in which a BLAST
    # search should be evaluated.
    class Query

      class << self
        # `Query.run` captures the essence better.
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

        compile! && run!
      ensure
        [@qfile, @rfile, @efile].compact.each(&:close).each(&:unlink)
      end

      # Command ran.
      attr_reader :command

      # HTML formatted result.
      attr_reader :result

      private

      # Compile parameters for BLAST search into a shell executable command and
      # stores it in @command, and query sequence into @qfile.
      def compile!
        validate

        binary = runtime.binaries[@method]

        # BLAST+ expects query sequence as a file.
        @qfile = Tempfile.new('sequenceserver_query')
        @qfile.puts(@sequences)
        @qfile.close
        query = @qfile.path

        # map: database id -> file name
        db = @databases.map do |id|
          runtime.databases[id].name
        end.join(' ')

        options = @options + defaults

        @command = "#{binary} -db '#{db}' -query '#{query}' #{options}"
      end

      # Runs BLAST search, and captures stdout and stderr of the command ran to
      # @rfile and @efile.
      def run!
        @rfile = Tempfile.new('sequenceserver_blast_result')
        @efile = Tempfile.new('sequenceserver_blast_error')
        [@rfile, @efile].each(&:close)

        Log.debug("Executing: #{@command}")
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
          !(runtime.databases.keys & @databases) == @databases # not a subset
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
    end # Query

    def initialize(binaries, databases, options = {})
      @binaries  = binaries
      @databases = databases
      @options   = options.dup.freeze

      runtime = self
      @blast  = Class.new(Query) do
        define_method :runtime do
          runtime
        end
      end
    end

    # A table of necessary BLAST+ executables, indexed by BLAST method name.
    attr_reader :binaries

    # A table of available `SequenceServer::Database` objects, each
    # encapsulating a BLAST database, indexed by their hash.
    attr_reader :databases

    # Number of threads to use for a BLAST search.
    def num_threads
      (options['num_threads'] || 1).to_i
    end

    # Run a BLAST search in the context of runtime settings provided by self.
    def run(*args)
      blast.run(*args)
    end

    private

    # A table of 'other' BLAST+ options derived from config file.
    attr_reader :options

    # Pointer to a concrete subclass of `Blast::Query`.
    attr_reader :blast
  end # Blast
end # SequenceServer

# References
# ----------
# [1]: http://www.ncbi.nlm.nih.gov/books/NBK1763/
