require 'rubygems'
require 'sinatra'

set :environment, ENV['RACK_ENV'].to_sym
disable :run, :reload

require "#{File.dirname(__FILE__)}/main"

config = YAML.load_file(File.expand_path("../config/pdns.yaml", __FILE__))


run PdnsManager::App.new(config[:default])
