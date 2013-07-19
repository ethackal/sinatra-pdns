require 'logger'
require 'sinatra' 
require 'active_record'
require 'erb'
require 'yaml'
require 'date'
require 'resolv'

require_relative 'pdns_connect'
require_relative 'app_helpers' 

module PdnsManager

  class App < Sinatra::Base
    include PdnsConnect

    dir = File.dirname(File.expand_path(__FILE__))
    set :public, "#{dir}/public"
    set :views, "#{dir}/views"

    #log:
    file_name = "#{dir}/logs/ar.log"
    ActiveRecord::Base.logger = Logger.new(file_name)
    file_name = "#{dir}/logs/sql.log"
    ActiveSupport::Notifications.subscribe /^sql\./ do |*args| 
      self.log_query(file_name, args)
    end

    def initialize(*args)
      super
      db_connect
    end

    def self.log_query(file_name,args)
      File.open(file_name,'a') do |f|
        f.print "#{args[0]}|"
        f.print "#{args[1].strftime('%Y-%m-%d %H:%M:%S')}|"
        f.print "#{args[2].strftime('%Y-%m-%d %H:%M:%S')}|"
        f.print "#{args[2]-args[1]}|"
        f.print "#{args[4][:name]}|"
        f.print "#{args[4][:sql].strip.gsub(/\n/,'').squeeze(' ')}"
        f.puts
      end
    end

    helpers AppHelpers

    get '/' do
      if params[:searchdom]  
        @domains = Domains.where("name LIKE :dom", dom: "#{params[:searchdom]}%")
      else
        @domains = Domains.name_order
      end
      erb :index
    end

    get '/add' do
      d=DateTime.now
      @serial_date=d.strftime("%Y%m%d01")
      erb :add_domain
    end

    post '/add/domain' do
      @errors = create_domain(params)
      @domains = Domains.name_order
      erb :index
    end

   get '/delete/dommain/:domain_id' do
      #1st records
      @errors = DnsRecord.where("domain_id = ?", params[:domain_id]).destroy_all
      #2 domain
      @errors = Domains.destroy(params[:domain_id])
      redirect to('/')
   end

    get '/list/:domain/' do
      @domain_id = Domains.where(name: "#{params[:domain]}").pluck(:id)[0]
      @records = DnsRecord.where("domain_id = ?", @domain_id).order("type DESC")

      erb :list_records
    end

    get '/add/record/:domain_id' do
      @domain_id = params[:domain_id]
      @records = DnsRecord.where("domain_id = ?", @domain_id).order("type DESC")
      erb :add_records
    end

    post '/add/record' do
      @errors = create_records(params)
      domain_id = params[:domain_id]
      domain_name = Domains.where(id: "#{domain_id}").pluck(:name)[0]
      redirect to("/list/#{domain_name}/")
    end

   get '/delete/record/:domain_id/:record_id' do
      type = DnsRecord.where(id: "#{params[:record_id]}").pluck(:type)[0]
      @errors = DnsRecord.destroy(params[:record_id])
      domain_name = Domains.where(id: "#{params[:domain_id]}").pluck(:name)[0]
      if type != 'SOA'
        increment_serial(params[:domain_id])
      end

      redirect to("/list/#{domain_name}/")
   end


    not_found do
      erb :"404"
    end

    error do
      @msg = "ERROR!!! " + env['sinatra.error'].name
      erb :error
    end
  end
end