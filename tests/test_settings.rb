require 'bundler/setup'
require 'sequenceserver'
require 'sequenceserver/settings'
require 'minitest/spec'
require 'minitest/autorun'

module SequenceServer

  describe "Settings" do

    def settings
      @settings ||= Settings.new
    end

    def test_multipart_database_name?
      assert_equal true, settings.send('multipart_database_name?', '/home/ben/pd.ben/sequenceserver/db/nr.00')
      assert_equal false, settings.send('multipart_database_name?', '/home/ben/pd.ben/sequenceserver/db/nr')
      assert_equal true, settings.send('multipart_database_name?', '/home/ben/pd.ben/sequenceserver/db/img3.5.finished.faa.01')
    end
  end
end
