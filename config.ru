require 'rubygems'
require 'bundler/setup'
require 'sequenceserver'

runtime = SequenceServer.new
run runtime.web_blast
