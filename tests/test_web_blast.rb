require 'bundler/setup'
require 'sequenceserver'
require 'minitest/spec'
require 'minitest/autorun'
require 'rack/test'

ENV['RACK_ENV'] = 'test'

module SequenceServer

  describe 'WebBlast settings' do

    def app
      @app ||= WebBlast
    end

    it 'should log all requests forwarded to it' do
      assert app.logging?
    end

    it 'should let internal server error handler take precedence over the default ShowExceptions middleware' do
      assert !app.show_exceptions?
    end
  end

  describe "WebBlast instance" do

    include Rack::Test::Methods

    def app
      @app ||= WebBlast.new!
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

    def databases
      databases = app.blast.databases
      [databases.values.find{|db| db.type == :protein}.hash]
    end

    def setup
      @params = {'method' => method, 'sequences' => sequence, 'databases' => databases}
    end

    it 'returns Bad Request (400) if no blast method is provided' do
      @params.delete('method')
      post '/', @params
      last_response.status.must_equal 400
    end

    it 'returns Bad Request (400) if no input sequence is provided' do
      @params.delete('sequences')
      post '/', @params
      last_response.status.must_equal 400
    end

    it 'returns Bad Request (400) if no database id is provided' do
      @params.delete('databases')
      post '/', @params
      last_response.status.must_equal 400
    end

    it 'returns Bad Request (400) if an empty database list is provided' do
      @params['databases'].pop

      # ensure the list of databases is empty
      @params['databases'].length.must_equal 0

      post '/', @params
      last_response.status.must_equal 400
    end

    it 'returns Bad Request (400) if an incorrect blast method is supplied' do
      @params['method'] = 'foo'
      post '/', @params
      last_response.status.must_equal 400
    end

    it 'returns Bad Request (400) if incorrect advanced params are supplied' do
      @params['options'] = '-word_size 5; rm -rf /'
      post '/', @params
      last_response.status.must_equal 400
    end

    describe "hit-sequence-hyperlinking" do

      include Rack::Test::Methods

      def app
        @app ||= WebBlast.new!
      end

      def parse_seqids_line
        ">lcl|Aech_17012<a name=Aech_17012></a>  [mRNA]  locus=scaffold821:43240:43587:+ [translate_table: standard]\n"
      end

      def sans_parse_seqids_line
        "><a name=BL_ORD_ID:15102></a> ACEP_00008472-RA protein AED:1 QI:0|0|0|0|0|0|11|0|967\n"
      end

      def sequence_id
        "lcl|Aech_17012"
      end

      def databases
        return @databases if @databases
        databases = app.blast.databases
        @databases = [databases.values.find{|db| db.type == :protein}.hash]
      end

      def hit_line_hyperlink
        "/get_sequence/?id=#{sequence_id}&db=#{databases.join(' ')}"
      end

      def line_number
        1
      end

      def result
        [
          ">lcl|Aech_17012<a name=Aech_17012></a>  [mRNA]  locus=scaffold821:43240:43587:+ [translate_table: standard]\n",
          "Length=115\n",
          "\n",
          " Score = 28.1 bits (61),  Expect = 5.9, Method: Composition-based stats.\n",
          " Identities = 19/41 (47%), Positives = 24/41 (59%), Gaps = 1/41 (2%)\n",
          "\n",
          "Query  115  KFDEFIRQVALLDEGSCSIMYSLLATSSVTGVTVRSVLNPM  155\n",
          "            KF++   Q ALLDE S  I+  L A  SVT +TV   L+ M\n",
          "Sbjct  68   KFEDTELQ-ALLDENSAQILUELSAALSVTPMTVFKRLHTM  107\n",
          "\n",
          "\n",
          ">lcl|Aech_14660<a name=Aech_14660></a>  [mRNA]  locus=scaffold83:86534:86893:+ [translate_table: standard]\n"
        ]
      end

      def hit_coordinates
        [68, 107]
      end

      it "should return sequence id of a hit from a database formatted with `-parse_seqids`" do
        assert_equal sequence_id, app.parse_sequence_id(parse_seqids_line)
      end

      it "should return nil for a hit from a database formatted without `-parse_seqids`" do
        assert_nil app.parse_sequence_id(sans_parse_seqids_line)
      end

      it "should be able to compute cooridnates of a hit" do
        assert_equal hit_coordinates, app.parse_hit_coordinates(line_number, result)
      end

      it "should be able to construct hit-sequence-download-link" do
        assert_equal hit_line_hyperlink,
          app.construct_sequence_hyperlink(sequence_id, databases, nil)
      end

      it "should return the same line if database is formatted without `-parse_seqids`" do
        assert_equal sans_parse_seqids_line,
          app.format_hit_line!(sans_parse_seqids_line, line_number, result,
                               databases)
      end
    end
  end
end
