require 'logger'
require 'sequenceserver/store'
require 'sequenceserver/helpers'
require 'sequenceserver/database'

module SequenceServer

  Log = Logger.new STDERR

  # Derive settings from user configuration directory.
  class Settings

    include Helpers

    class << self

      # Enable directory-as-a-storage backend for `self`.
      include Store

      # Retrieve a setting.
      def entry(key)
        read(super)
      end

      private

      def readers
        @readers ||= {}
      end

      def read(entry)
        [entry.first, readers[entry.first].call(entry.last)]
      end
    end

    # Declare the directory to read settings from.
    store '~/.sequenceserver'

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
    # To
    readers['binaries'] = lambda do |binaries_dir|
      binaries = {}
      %w|blastn blastp blastx tblastn tblastx blastdbcmd makeblastdb blast_formatter|.each do |method|
        binary = binaries_dir && File.join(binaries_dir, method) || method
        if command?(binary)
          Log.info "Found #{method} at #{binary}."
          binaries[method] = binary
        else
          blasturl = 'http://www.ncbi.nlm.nih.gov/blast/Blast.cgi?CMD=Web&PAGE_TYPE=BlastDocs&DOC_TYPE=Download'
          STDERR.puts <<INFO
Could not find blast binaries.  You may need to download BLAST+ from:
          #{blasturl}.
INFO
#And/or edit #{settings.config_file} to indicate the location of BLAST+
#binaries.
exit
        end
      end

      binaries.freeze
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
    readers['databases'] = lambda do |databases_dir|
      blastdbcmd = Settings.get('binaries')['blastdbcmd']
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

      databases = {}

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
        databases[database.hash] = database
      end

      databases.freeze
    end

    readers['num_threads'] = lambda do |file|
      Integer(file.read.chomp)
    end

    readers['port'] = lambda do |file|
      Integer(file.read.chomp)
    end
  end
end
