require 'optparse'
require 'sequenceserver/version'
require 'sequenceserver/server'
require 'sequenceserver/database'
require 'sequenceserver/web_blast'
require 'sequenceserver/database_formatter'

# Act as namespace for sub components, and a container for runtime objects.
class SequenceServer

  def initialize
    optspec.order!
  rescue OptionParser::InvalidOption =>e
    puts e
    puts "Run '#{$0} -h' for help with command line options."
    exit
  end

  def server
    @server ||= Server.new(web_blast)
  end

  def web_blast
    @web_blast ||= WebBlast.new(binaries, databases, config)
  end

  def database_formatter
    @dbf ||= DatabaseFormatter.new(binaries, database_dir)
  end

  def binaries
    @binaries ||= %w|blastn blastp blastx tblastn tblastx blastdbcmd makeblastdb blast_formatter|.reduce({}) do |collection, method|
      collection[method] = File.join(bin_dir, method)
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
      databases[database.hash] = database
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
      'database' => File.expand_path('../../tests/database', __FILE__),
      'num_threads' => 1
    }
  end

  def options
    @options ||= {
      'config_file' => File.expand_path('~/.sequenceserver.conf')
    }
  end

  def optspec
    @optspec ||= OptionParser.new do |opts|
      opts.banner =<<BANNER

SUMMARY

  custom, local, BLAST server

USAGE

  sequenceserver [options] [subcommand] [subcommand's options]

Example:

    # launch SequenceServer with the given config file
    $ sequenceserver --config ~/.sequenceserver.ants.conf

    # use the bundled database formatter utility to prepare databases for use
    # with SequenceServer
    $ sequenceserver format-databases

DESCRIPTION

  SequenceServer lets you rapidly set up a BLAST+ server with an intuitive user
  interface for use locally or over the web.

SUB-COMMANDS

  server
    launch built-in web server (default action)

    Run '#{$0} server -h' for help.

  format-databases
    prepare BLAST databases for use with SequenceServer

    Run '#{$0} format-databases -h' for help.

OPTIONS

BANNER

      opts.on('-c', '--config CONFIG_FILE', 'Use the given configuration file') do |config_file|
        options['config_file'] = File.expand_path(config_file)
        unless File.exist?(config_file)
          puts "Couldn't find #{config_file}. Typo?"
          exit
        end
      end

      opts.on('-v', '--version', 'Print version number of SequenceServer that will be loaded.' ) do |config_file|
        puts SequenceServer.version
        exit
      end
    end
  end
end
