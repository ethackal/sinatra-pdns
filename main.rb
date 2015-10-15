require 'logger'
require 'sinatra' 
require 'active_record'
require 'erb'
require 'yaml'
require 'date'
require 'resolv'
require 'bcrypt'

require_relative 'pdns_connect'
require_relative 'ldap_authentication'
require_relative 'app_helpers' 

module PdnsManager
  class LoginScreen < Sinatra::Base
    config = YAML.load_file(File.expand_path("../config/pdns.yaml", __FILE__))
    include LdapAuthentication if config[:auth_method] == 'ldap'

    enable :sessions
  
      get '/login' do
        if config[:auth_method] == 'ldap'
          @login_msg = 'ldap account'
        else
          @login_msg = 'login'
        end
        erb :login
      end
  
    post('/login') do
      if config[:auth_method] == 'ldap'
        login    = params[:login]
        password = params[:password]        
        @current_user = authenticate(login, password)
        if @current_user
          session['user_name'] = params[:login]
          redirect '/'
        else
          redirect '/login'
        end
      elsif config[:auth_method] == 'simple'
        if params[:login] == config[:username] && params[:password] == BCrypt::Password.new(config[:password])
          session['user_name'] = params[:login]
          redirect '/'
        else
          redirect '/login'
        end
      else
          redirect '/login'
          @error = 'no auth method'
      end
    end
  end


  class App < Sinatra::Base

    include PdnsConnect
    #include LdapAuthentication

    dir = File.dirname(File.expand_path(__FILE__))
    set :public_dir, "#{dir}/public"
    set :views, "#{dir}/views"

    #log:
    file_name = "#{dir}/logs/ar.log"
    ActiveRecord::Base.logger = Logger.new(file_name)
    file_name = "#{dir}/logs/sql.log"
    ActiveSupport::Notifications.subscribe /^sql\./ do |*args| 
      self.log_query(file_name, args)
    end

    def initialize(options = {})
      #@auth_auth_method = auth_method
      #@user = login
      #@passwd = password

      @default_nsserver = options.delete(:nsserver) || ''
      @default_contact = options.delete(:contact) || ''
      @default_refresh = options.delete(:refresh) || 28800
      @default_retry = options.delete(:retry) || 7200
      @default_expire = options.delete(:expire) || 604800
      @default_ttl = options.delete(:ttl) || 300


      super()
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

    use LoginScreen

    before do
      unless session['user_name']
        redirect '/login'
        halt
      end
    end


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
      @error = create_domain(params)
      @domains = Domains.name_order
      erb :index
    end

   get '/delete/dommain/:domain_id' do
      #1st records
      @error = DnsRecord.where("domain_id = ?", params[:domain_id]).destroy_all
      #2 domain
      @error = Domains.destroy(params[:domain_id])
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
      @error = create_records(params)
      domain_id = params[:domain_id]
      domain_name = Domains.where(id: "#{domain_id}").pluck(:name)[0]
      redirect to("/list/#{domain_name}/")
    end

   get '/delete/record/:domain_id/:record_id' do
      type = DnsRecord.where(id: "#{params[:record_id]}").pluck(:type)[0]
      @error = DnsRecord.destroy(params[:record_id])
      domain_name = Domains.where(id: "#{params[:domain_id]}").pluck(:name)[0]
      if type != 'SOA'
        increment_serial(params[:domain_id])
      end

      redirect to("/list/#{domain_name}/")
   end

    get '/logout' do
      session.clear
      redirect to("/")
    end

    not_found do
      erb :"404"
    end

  end
end
