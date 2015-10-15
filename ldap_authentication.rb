require 'net/ldap'
require 'digest/md5'



module LdapAuthentication
    
    def included
      @@ldap_config = @@ldap_config || YAML.load_file( File.expand_path('../config/ldap.yml', __FILE__) )
    end
    
    AUTH_TOKEN_SEED = 'AwesomeSuperSecureSecret'

    def authenticate(login, password)
      authenticated_user = ldap_login(login, password)

      if authenticated_user
        {
          #:email => authenticated_user['mail'].first,
          :name  => authenticated_user[@@ldap_config[:displayname_attribute]].first,
          :token => Digest::MD5.hexdigest(AUTH_TOKEN_SEED + authenticated_user['cn'].first)
        }
      else
        false
      end
    end

    def token_ok?(email,token)
      token == Digest::MD5.hexdigest(AUTH_TOKEN_SEED+email)
    end

    private

    # Returns a single Net::LDAP::Entry or false
    def ldap_login(username, password)
      ldap_session       = new_ldap_session
      bind_args          = args_for(username, password)
      authenticated_user = ldap_session.bind_as(bind_args)

      authenticated_user ? authenticated_user.first : false
    end

    # This is where @@ldap_config jumps up and punches you in the face, all the while
    # screaming "You never gunna get this, your wasting your time!".
    def args_for(username, password)
      user_filter = "#{ @@ldap_config[:username_attribute] }=#{ username }"
      args        = { :base     => @@ldap_config[:base],
                      :filter   => "(#{ user_filter })",
                      :password => password }

      unless @@ldap_config[:can_search_anonymously]
        # If you can't search your @@ldap_config directory anonymously we'll try and
        # authenticate you with your user dn before we try and search for your
        # account (dn example. `uid=clowder,ou=People,dc=mycompany,dc=com`).
        user_dn = [user_filter, @@ldap_config[:base]].join(',')
        args.merge({ :auth => { :username => user_dn, :password => password, :method => :simple } })
      end

      args
    end

    def new_ldap_session_old
      Net::LDAP.new(:host       => @@ldap_config[:host],
                    :port       => @@ldap_config[:port],
                    :encryption => @@ldap_config[:encryption],
                    :base       => @@ldap_config[:base])
    end

    def new_ldap_session
      Net::LDAP.new(:host       => @@ldap_config[:host],
                    :port       => @@ldap_config[:port],
                    :base       => @@ldap_config[:base],
                    :auth => {
                        :method => :simple,
                        :username => @@ldap_config[:base],
                        :password => @@ldap_config[:password]
                    })
    end
end
