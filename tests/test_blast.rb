require 'bundler/setup'
require 'sequenceserver'
require 'minitest/spec'
require 'minitest/autorun'

module SequenceServer

  describe "Blast" do
    # Initialize BLAST runtime once for all test cases.
    def self.blast
      return @blast if @blast
      @blast = WebBlast.new!.blast
    end

    def blast
      self.class.blast
    end

    def method
      'blastp'
    end

    def sequence
      # protein sequence
<<SEQ
>SI2.2.0_06267 locus=Si_gnF.scaffold02592[1282609..1284114].pep_2 quality=100.00
MNTLWLSLWDYPGKLPLNFMVFDTKDDLQAAYWRDPYSIPLAVIFEDPQPISQRLIYEIR
TNPSYTLPPPPTKLYSAPISCRKNKTGHWMDDILSIKTGESCPVNNYLHSGFLALQMITD
ITKIKLENSDVTIPDIKLIMFPKEPYTADWMLAFRVVIPLYMVLALSQFITYLLILIVGE
KENKIKEGMKMMGLNDSVF
SEQ
    end

    def database
      [blast.databases.values.find{|db| db.type == :protein}.hash]
    end

    def options
      ''
    end

    it 'should successfully run a BLAST search' do
      result = blast.run(method, sequence, database, options)
      assert result.is_a?(Blast::Query), "Expected a Blast::Query object."
    end

    it 'should raise argument error if an invalid BLAST method is given' do
      assert_raises Blast::ArgumentError do
        blast.run('foo', sequence, database, options)
      end
    end

    it 'should raise argument error if an invalid option is given' do

      # security!
      assert_raises Blast::ArgumentError do
        blast.run(method, sequence, database, '-word_size 5; rm -rf /')
      end

      # conflicting advanced option
      assert_raises Blast::ArgumentError do
        blast.run(method, sequence, database, '-db moo')
      end

      # non-existent option
      assert_raises Blast::ArgumentError do
        blast.run(method, sequence, database, '-foobar moo')
      end

      # correct option, but wrong value
      assert_raises Blast::ArgumentError do
        blast.run(method, sequence, database, '-matrix moo')
      end
    end

    #it 'should raise runtime error if an invalid database is given' do
      #assert_raises Blast::RuntimeError do
        #blast.run(method, sequence, ['invalid.fasta'], options)
      #end
    #end
  end
end
