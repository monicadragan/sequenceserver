require 'sequenceserver'
require 'minitest/spec'
require 'minitest/autorun'

class SequenceServer

  describe "Blast" do

    def runtime
      return @runtime if @runtime
      @runtime = SequenceServer.new
      @runtime.instance_variable_set '@database_dir', File.expand_path('../database', __FILE__)
      @runtime
    end

    def blast
      runtime.blast
    end

    def method
      'blastp'
    end

    def sequences
<<SEQ
>lcl|SI2.2.0_06267 locus=Si_gnF.scaffold02592[1282609..1284114].pep_2 quality=100.00
MNTLWLSLWDYPGKLPLNFMVFDTKDDLQAAYWRDPYSIPLAVIFEDPQPISQRLIYEIRTNPSYTLPPPPTKLYSAPIS
CRKNKTGHWMDDILSIKTGESCPVNNYLHSGFLALQMITDITKIKLENSDVTIPDIKLIMFPKEPYTADWMLAFRVVIPL
YMVLALSQFITYLLILIVGEKENKIKEGMKMMGLNDSVF
SEQ
    end

    def databases
      [runtime.databases.find{|id, db| db.title =~ /Sinvicta\.prot/}.last.hash]
    end

    def options
      ''
    end

    it 'should successfully run a search if correct parameters are given' do
      result = blast.run(method, sequences, databases, options)
      assert result.is_a?(Blast), "Expected a Blast object."
    end

    it 'should raise argument error if an incorrect search algorithm is given' do

      # completely arbitray word used as search method
      assert_raises Blast::ArgumentError do
        blast.run('foo', sequences, databases, options)
      end

      # another BLAST+ binary used as search method
      assert_raises Blast::ArgumentError do
        blast.run('blastdbcmd', sequences, databases, options)
      end
    end

    it 'should raise argument error if an invalid option is given' do

      # security!
      assert_raises Blast::ArgumentError do
        blast.run(method, sequences, databases, '-word_size 5; rm -rf /')
      end

      # conflicting advanced option
      assert_raises Blast::ArgumentError do
        blast.run(method, sequences, databases, '-db moo')
      end

      # non-existent option
      assert_raises Blast::ArgumentError do
        blast.run(method, sequences, databases, '-foobar moo')
      end

      # correct option, but wrong value
      assert_raises Blast::ArgumentError do
        blast.run(method, sequences, databases, '-matrix moo')
      end
    end

    #it 'should return sequences given their ids and databases to search' do
      #assert_equal sequences, blast.get_sequences(sequence_ids, databases)
    #end

    it 'should raise runtime error if an invalid database is given' do
      assert_raises Blast::ArgumentError do
        blast.run(method, sequences, ['invalid.database'], options)
      end
    end
  end
end
