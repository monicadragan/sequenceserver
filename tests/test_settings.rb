require 'bundler/setup'
require 'sequenceserver'
require 'sequenceserver/settings'
require 'minitest/spec'
require 'minitest/autorun'

module SequenceServer

  describe "Settings" do

    describe '.root' do
      it "should return absolute path to SequenceServer's installation directory" do
        root = File.dirname File.dirname File.dirname __FILE__
        root = File.expand_path root
        assert_equal root, Settings.root
      end
    end

    describe '.bundled_dot_dir' do
      it "should return the absolute path to the dot dir bundled with SequenceServer" do
        root = File.dirname File.dirname File.dirname __FILE__
        root = File.expand_path root
        bundled_dot_dir = File.expand_path('.sequenceserver', root)
        assert_equal bundled_dot_dir, Settings.bundled_dot_dir
      end
    end

    def test_multipart_database_name?
      assert_equal true, settings.send('multipart_database_name?', '/home/ben/pd.ben/sequenceserver/db/nr.00')
      assert_equal false, settings.send('multipart_database_name?', '/home/ben/pd.ben/sequenceserver/db/nr')
      assert_equal true, settings.send('multipart_database_name?', '/home/ben/pd.ben/sequenceserver/db/img3.5.finished.faa.01')
    end
  end
end
