require 'bundler/setup'
require 'sequenceserver'
require 'minitest/spec'
require 'minitest/autorun'
require 'rack/test'

ENV['RACK_ENV'] = 'test'

module SequenceServer

  describe "App" do

    include Rack::Test::Methods

    def app
      App
    end

    it 'should log all requets' do
      assert app.logging?
    end
  end
end
