require 'pathname'

module SequenceServer

  # Model a directory as a read-only, key-value store.
  #
  #   key -> value : basename -> corresponding pathname object
  #
  #   $ pwd
  #   /home/yeban/sequenceserver
  #   $ ls
  #   databases num_threads
  #
  #   >> store
  #   #<Pathname:/home/yeban/.sequenceserver>
  #   >> entry 'databases'
  #   ["databases", #<Pathname:/home/yeban/.sequenceserver/databases>]
  #   >> get 'num_threads'
  #   #<Pathname:/home/yeban/.sequenceserver/num_threads>
  #
  module Store

    include Enumerable

    def store(path = nil)
      return @store unless path
      @store = Pathname.new(File.expand_path(path))
      raise Errno::ENOENT, "Can't find #{path}." unless @store.exist?
    end

    def each(&blk)
      store.each_child do |path|
        yield path.basename.to_s, path
      end
    end

    def get(basename)
      entry(basename).last
    end

    def entry(basename)
      entries.assoc(basename) ||
        raise(Errno::ENOENT, "#{basename} not in #{store}.")
    end

    def store?
      true
    end
  end
end
