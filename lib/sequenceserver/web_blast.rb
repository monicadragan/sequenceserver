require 'sinatra/base'
require 'yaml'
require 'logger'
require 'fileutils'
require 'sequenceserver/blast'
require 'sequenceserver/sequencehelpers'
require 'sequenceserver/sinatralikeloggerformatter'
require 'sequenceserver/version'

# Helper module - initialize the blast server.
class SequenceServer
  class WebBlast < Sinatra::Base
    include SequenceHelpers

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
      set :root,       File.dirname(File.dirname(File.dirname(app_file)))

      # path to test database
      #
      # SequenceServer ships with test database (fire ant genome) so users can
      # launch and preview SequenceServer without any configuration, and/or run
      # test suite.
      set :test_database, File.join(root, 'tests', 'database')

      set :log,       Logger.new(STDERR)
      log.formatter = SinatraLikeLogFormatter.new()
    end

    configure :development do
      log.level     = Logger::DEBUG
    end

    def databases
      runtime.databases
    end

    def blast
      runtime.blast
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

      query = blast.run(method, sequences, databases, options)
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
