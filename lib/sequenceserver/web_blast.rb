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

    # get '/get_sequence/?id=sequence_ids&db=retreival_databases'
    #
    # Use whitespace to separate entries in sequence_ids (all other chars exist
    # in identifiers) and retreival_databases (we don't allow whitespace in a
    # database's name, so it's safe).
    get '/get_sequence/' do
      sequenceids = params[:id].split(/\s/).uniq  # in a multi-blast
      # query some may have been found multiply
      retrieval_databases = params[:db].split(/\s/)

      settings.log.info("Looking for: '#{sequenceids.join(', ')}' in '#{retrieval_databases.join(', ')}'")

      # the results do not indicate which database a hit is from.
      # Thus if several databases were used for blasting, we must check them all
      # if it works, refactor with "inject" or "collect"?
      found_sequences = get_sequences(sequenceids, retrieval_databases)

      found_sequences_count = found_sequences.count('>')

      out = ''
      # just in case, checking we found right number of sequences
      if found_sequences_count != sequenceids.length
        out << <<HEADER
<h1>ERROR: incorrect number of sequences found.</h1>
<p>Dear user,</p>

<p><strong>We have found
<em>#{found_sequences_count > sequenceids.length ? 'more' : 'less'}</em>
sequence than expected.</strong></p>

<p>This is likely due to a problem with how databases are formatted. 
<strong>Please share this text with the person managing this website so 
they can resolve the issue.</strong></p>

<p> You requested #{sequenceids.length} sequence#{sequenceids.length > 1 ? 's' : ''}
with the following identifiers: <code>#{sequenceids.join(', ')}</code>,
from the following databases: <code>#{retrieval_databases.join(', ')}</code>.
But we found #{found_sequences_count} sequence#{found_sequences_count> 1 ? 's' : ''}.
</p>

<p>If sequences were retrieved, you can find them below (but some may be incorrect, so be careful!).</p>
<hr/>
HEADER
      end

      out << "<pre><code>#{found_sequences}</pre></code>"
      out
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
