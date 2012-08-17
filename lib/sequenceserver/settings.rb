require 'sequenceserver/database'

module SequenceServer

  class Settings

    def initialize
      migrate!
    end

    attr_reader :binaries, :databases, :num_threads

    # Path to SequenceServer's configuration file.
    #
    # The configuration file is a simple, YAML data store.
    def dot_dir
      @dot_dir ||= File.expand_path('~/.sequenceserver')
    end

    private

    def migrate!
      migrate_binaries! && migrate_databases! && migrate_num_threads!
    end

    # Scan the given directory for blast executables. Passing `nil` scans the
    # system `PATH`.
    # ---
    # Arguments:
    # * bin(String) - absolute path to the directory containing blast binaries
    # ---
    # Returns:
    # * a hash of blast methods, and their corresponding absolute path
    # ---
    # Raises:
    # * IOError - if the executables can't be found
    def migrate_binaries!
      binaries_dir = File.expand_path('binaries', dot_dir)

      unless File.directory? binaries_dir
        Log.debug "#{binaries_dir} doesn't exist. " +
                    "Will check system PATH for BLAST+ binaries."
        binaries_dir = nil
      end

      @binaries = {}
      %w|blastn blastp blastx tblastn tblastx blastdbcmd makeblastdb blast_formatter|.each do |method|
        binary = binaries_dir && File.join(binaries_dir, method) || method
        if command?(binary)
          Log.info "Found #{method} at #{binary}."
          @binaries[method] = binary
        else
          blasturl = 'http://www.ncbi.nlm.nih.gov/blast/Blast.cgi?CMD=Web&PAGE_TYPE=BlastDocs&DOC_TYPE=Download'
          STDERR.puts <<INFO
Could not find blast binaries.  You may need to download BLAST+ from:
#{blasturl}.
And/or edit #{settings.config_file} to indicate the location of BLAST+
binaries.
INFO
          exit
        end
      end

      @binaries.freeze
    end

    # Scan the given directory (including subdirectory) for blast databases.
    # ---
    # Arguments:
    # * db_root(String) - absolute path to the blast databases
    # ---
    # Returns:
    # * a hash of sorted blast databases grouped by database type:
    # protein, or nucleotide
    # ---
    # Raises:
    # * IOError - if no database can be found
    #
    #   > scan_blast_db('/home/yeban/blast_db')
    #   => { "protein" => [], "nucleotide" => [] }
    def migrate_databases!
      databases_dir  = File.expand_path('databases', dot_dir)
      @databases_dir = databases_dir if File.directory? databases_dir

      unless File.directory? databases_dir
        raise IOError, "Database directory doesn't exist: #{databases_dir}"
      end

      blastdbcmd = binaries['blastdbcmd']
      find_dbs_command = %|#{blastdbcmd} -recursive -list #{databases_dir} -list_outfmt "%p %f %t" 2>&1|

      db_list = %x|#{find_dbs_command}|
      if db_list.empty?
        raise IOError, "No formatted blast databases found in '#{databases_dir}'."
      end

      if db_list.match(/BLAST Database error/)
        raise IOError, "Error parsing blast databases.\n" + "Tried: '#{find_dbs_command}'\n"+
          "It crashed with the following error: '#{db_list}'\n" +
          "Try reformatting databases using makeblastdb.\n"
      end

      @databases = {}

      db_list.each_line do |line|
        next if line.empty?  # required for BLAST+ 2.2.22
        type, name, *title =  line.split(' ') 
        type = type.downcase.intern
        name = name.freeze
        title = title.join(' ').freeze

        # skip past all but alias file of a NCBI multi-part BLAST database
        if multipart_database_name?(name)
          Log.info(%|Found a multi-part database volume at #{name} - ignoring it.|)
          next
        end

        Log.info("Found #{type} database '#{title}' at #{name}.")
        database = Database.new(name, title, type)
        @databases[database.hash] = database
      end

      @databases.freeze
    end

    def migrate_num_threads!
      num_threads_file = File.expand_path('num_threads', dot_dir)

      unless File.exists? num_threads_file
        Log.debug "#{num_threads_file} doesn't exist. Will assume one thread."
        num_threads_file = nil
      end

      @num_threads = num_threads_file && Integer(File.read(num_threads_file).chomp) || 1
    end

    # check if the given command exists and is executable
    # returns True if all is good.
    def command?(command)
      system("which #{command} > /dev/null 2>&1")
    end

    # Returns true if the database name appears to be a multi-part database name.
    #
    # e.g.
    # /home/ben/pd.ben/sequenceserver/db/nr.00 => yes
    # /home/ben/pd.ben/sequenceserver/db/nr => no
    # /home/ben/pd.ben/sequenceserver/db/img3.5.finished.faa.01 => yes
    def multipart_database_name?(db_name)
      !(db_name.match(/.+\/\S+\d{2}$/).nil?)
    end
  end
end
