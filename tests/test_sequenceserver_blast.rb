require 'bundler/setup'
require 'sequenceserver'
require 'minitest/spec'
require 'minitest/autorun'
require 'rack/test'

ENV['RACK_ENV'] = 'test'

module SequenceServer
  describe "App" do
    include Rack::Test::Methods

    def self.app
      @app ||= App.new!
    end

    def app
      self.class.app
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
  end
end
