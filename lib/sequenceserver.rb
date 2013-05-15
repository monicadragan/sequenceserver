require 'optparse'
require 'yaml'
require 'logger'
require 'fileutils'
require 'sinatra/base'
require 'sequenceserver/cli'
require 'sequenceserver/logger'
require 'sequenceserver/database'
require 'sequenceserver/search'
require 'sequenceserver/sequencehelpers'

# Act as namespace for sub components, and a container for runtime objects.
module SequenceServer

  VERSION = '0.8.3'

  class App < Sinatra::Base

    include SequenceHelpers

    #configure do
      #set :config_dir,    File.expand_path('~/.sequenceserver')

      #set :binaries_dir,  &:bin_dir

      #set :databases_dir, File.join(config_dir, 'databases')

      set :logfile,       STDERR

      #set :port,          4567
    #end

    # App root -- where to look for and static assets and views.
    set :root,       File.expand_path('../../app', __FILE__)

    # Log HTTP requests in CLI format.
    enable  :logging

    # Enable trapping internal server error in controller.
    disable :show_exceptions

    # Logger to use for everything.
    set :log, Logger.new(logfile)

    configure :production  do
      log.level = Logger::FATAL
    end

    configure :development do
      log.level = Logger::DEBUG
    end

    configure :test do
      set :database, File.join(root, 'tests', 'database')
    end

    #def new(config_dir)
    #end

    def search
      settings.search
    end

    class << self
      def search
        return @search if @search
        settings = self.settings
        @search  = Class.new(Search) do
          define_method :settings do
            settings
          end
        end
      end

      def database_formatter
        @dbf ||= DatabaseFormatter.new(binaries, database_dir)
      end

      def binaries
        @binaries ||= %w|blastn blastp blastx tblastn tblastx blastdbcmd makeblastdb blast_formatter|.reduce({}) do |collection, method|
          collection[method] = File.join(settings.bin_dir, method)
          collection
        end
      end

      def databases
        return @databases if @databases
        blastdbcmd = binaries['blastdbcmd']
        find_dbs_command = %|#{blastdbcmd} -recursive -list #{database_dir} -list_outfmt "%p %f %t" 2>&1|

        puts "Scanning #{database_dir} ..."
        output = %x|#{find_dbs_command}|
        if output.empty?
          puts "No formatted blast databases found in '#{database_dir}'."

          print "Do you want to format your blast databases now? [Y/n]: "
          choice = gets.chomp[0,1].downcase

          unless choice == 'n'
            database_formatter = File.join(settings.root, 'database_formatter.rb')
            system("#{database_formatter} #{db_root}")
          end
        end

        if output.match(/BLAST Database error/)
          puts "Error parsing blast databases.\n" + "Tried: '#{find_dbs_command}'\n"+
            "It crashed with the following error: '#{databases}'\n" +
            "Try reformatting databases using makeblastdb.\n"
        end

        databases = {}
        output.each_line do |line|
          next if line.empty?  # required for BLAST+ 2.2.22
          type, name, *title =  line.split(' ')
          type = type.downcase.intern
          name = name.freeze
          title = title.join(' ').freeze

          # skip past all but alias file of a NCBI multi-part BLAST database
          if !(name.match(/.+\/\S+\d{2}$/).nil?)
            puts %|Found a multi-part database volume at #{name} - ignoring it.|
            next
          end

          database = SequenceServer::Database.new(name, title, type)
          puts "Found #{database.type} database: #{database.title} at #{database.name}"
          databases[database.id] = database
        end
        @databases = databases
      end

      def bin_dir
        return @bin_dir if @bin_dir
        bin_dir = config['bin']
        if bin_dir
          print "== Locating #{bin_dir} ... "
          bin_dir = File.expand_path(bin_dir)
          if File.directory?(bin_dir)
            puts "done."
          else
            puts "failed."
            exit
          end
        else
          print "== Searching PATH for BLAST+ binaries ... "
          blastp = %x"which blastp 2> /dev/null"
          if blastp.empty?
            puts "failed."
            blasturl = 'http://www.ncbi.nlm.nih.gov/blast/Blast.cgi?CMD=Web&PAGE_TYPE=BlastDocs&DOC_TYPE=Download'
            puts "You may need to download BLAST+ from #{blasturl}." +
              " And/or edit configuration file to indicate the location of BLAST+ binaries."
            exit
          else
            puts "found."
            bin_dir = File.dirname(blastp)
          end
        end
        @bin_dir = bin_dir
      end

      def database_dir
        return @database_dir if @database_dir
        database_dir = config.delete('database')
        unless database_dir
          puts "Where to look?"
          exit
        end

        print "== Locating #{database_dir} ... "
        database_dir = File.expand_path database_dir
        if File.directory?(database_dir)
          puts "done."
        else
          puts "failed."
          exit
        end
        @database_dir = database_dir
      end

      def num_threads
        @num_threads ||= config['num_threads']
      end

      def config
        return @config if @config
        print "== Reading configuration file ... "
        if read = YAML.load_file(config_file)
          config = defaults.merge read
          puts "done."
        else
          puts "empty."
        end
        @config = config || defaults
      rescue ArgumentError => error
        # _possibly_ triggered by an error in YAML
        puts "Error in #{config_file}: #{error}"
        puts "YAML is white space sensitive. Is your config.yml properly indented?"
        exit
      end

      def config_file
        return @config_file if @config_file
        config_file = options['config_file']
        unless File.exists?(config_file)
          puts "couldn't find."
          example_config_file = File.expand_path('../../example.config.yml', __FILE__)
          FileUtils.cp(example_config_file, config_file)
          puts "Generated a dummy configuration file: #{config_file}."
          puts "Please edit #{config_file} to indicate the location of BLAST binaries and databases, and run SequenceServer again."
          exit
        end
        @config_file = config_file
      end

      def defaults
        @defaults ||= {
          'database' => File.expand_path('../../.sequenceserver/database', __FILE__),
          'num_threads' => 1
        }
      end

      def options
        @options ||= {
          'config_file' => File.expand_path('~/.sequenceserver.conf')
        }
      end
    end

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

      query = search.run(method, sequences, databases, options)
      settings.log.debug("Executing: #{query.command}")
      erb :results, :locals => {:query => query}
    end

    # get '/get_sequence/?id=sequence_ids&db=retreival_databases&download=true'
    #
    # Use whitespace to separate entries in sequence_ids (all other chars exist
    # in identifiers) and retreival_databases (we don't allow whitespace in a
    # database's name, so it's safe).
    get '/get_sequence/' do
      sequence_ids = params[:id].split(/\s/).uniq  # in a multi-blast
      retrieval_databases = params[:db].split(/\s/)
      settings.log.info("Looking for: '#{sequence_ids.join(', ')}' in '#{retrieval_databases.join(', ')}'")
      sequences = get_sequences(sequence_ids, retrieval_databases)
      error     = nil
      unless sequences.count == sequence_ids.count
        error = {
          :nexpected    => sequence_ids.count,
          :nfound       => sequences.count,
          :sequence_ids => sequence_ids,
          :databases    => retrieval_databases
        }
      end

      if params[:download]
        download_name = "sequenceserver_#{sequence_ids.first}.txt"
        file = Tempfile.open(download_name) do |f|
          f.puts sequences
          f
        end

        send_file file.path, :filename => download_name
      else
        erb :'sequence-viewer/show', :locals => {:sequences => sequences, :error => error}
      end
    end

    error 400 do
      error = env['sinatra.error']
      settings.log.error(error) # TODO: figure out how to make Sinatra log this automatically with backtrace, like InternalServerError (500).
      erb :'errors/400', :locals => {:error => error}
    end

    error 500 do
      erb :'errors/500', :locals => {:error => env['sinatra.error']}
    end
  end
end
