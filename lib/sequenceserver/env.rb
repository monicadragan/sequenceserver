module SequenceServer
  module Env

    extend self

    def environment
      @environment ||= (ENV['RACK_ENV'] || :development).to_sym
    end

    def production?
      (environment == :production)
    end

    def development?
      (environment == :development)
    end

    def test?
      (environment == :test)
    end

    # Evaluate given block only for the environments passed to it.
    def env(*envs, &block)
      yield self if envs.empty? || envs.include?(environment)
    end

    def self.included(klass)
      klass.extend self
    end
  end

  include Env
end
