module PdnsConnect
  
  class Domains < ActiveRecord::Base
    self.inheritance_column = "ruby_type"

    validates :name,        :presence => true,
                            :uniqueness => true
    scope :name_order, -> { order('domains.name') }

    has_many :dns_records, :foreign_key => 'domain_id'
    alias :records :dns_records

  end


  class DnsRecord < ActiveRecord::Base
  
    self.table_name = "records"
    self.inheritance_column = "ruby_type"
  
    belongs_to :dns_domain, :foreign_key => 'domain_id'
    alias :domain :dns_domain
  
    validates_presence_of :content

    #validate content for PTR|NS|CNAME
    validates_format_of   :content,
      :with => /\A[0-9a-zA-Z\.\-]+\Z/,
      :message => 'can only contain numbers, letters, dashes and \'.\'',
      :if => Proc.new { |dns_record|
        if dns_record.type =~ /(PTR|NS|CNAME)/
          true
        end
    }
    
    #validate content for SOA (perfectible...)
    validates_format_of   :content,
      :with => /\A[0-9a-zA-Z\.\-]+\s[0-9a-zA-Z\.\-]+\.\s[0-9]+\s[0-9]+\s[0-9]+\s[0-9]+\s[0-9]+/,
      :message => 'Not valid SOA need 7 fields',
      :if => Proc.new { |dns_record|
        if dns_record.type == 'SOA'
          true
        end
    }

    #validate content for IN A
    validates_format_of   :content,
      :with => Resolv::IPv4::Regex,
      :message => 'Not valid IP',
      :if => Proc.new { |dns_record|
        if dns_record.type == 'A'
          true
        end
    }

    #validate name for IPV6 reverse
    validates_format_of   :name,
      :with => /\A([0-9a-fA-F]\.){32}ip6\.arpa\Z/,
      :message => 'has bad format (did you include all trailing zeros?)',
      :if => Proc.new { |dns_record|
        if dns_record.type == 'PTR' && dns_record.name =~ /\.ip6\.arpa$/
          true
        end
    }

    #validate name for IPV4 reverse
    validates_format_of   :name,
      :with => /\A([0-9]+\.){4}in-addr\.arpa\Z/,
      :message => 'has bad format',
      :if => Proc.new { |dns_record|
        if dns_record.type == 'PTR' && dns_record.name =~ /\.in-addr\.arpa$/
          true
        end
    }
  
    def validate
      # CNAME must have unique LHS
        if type == 'SOA'
          r = DnsRecord.where("domain_id = ? and type = 'SOA'", domain_id)
          if r && r.size > 0
            return false
          end
        end
        if type == 'CNAME'
          r = DnsRecord.where("name = ? and type != 'CNAME'", name)
          if r && r.size > 0
            #raise "CNAME must have unique LHS (do you have a PTR or NS record with the same IP / Name?)"
            return false
          end
        else
          r = DnsRecord.where("name = ? and type = 'CNAME'", name)
          if r && r.size > 0
            #raise "CNAME must have unique LHS (do you have a PTR or NS record with the same IP / Name?)"
            return false
          end
        end
        return true
    end
  
    def before_save
      if type == 'PTR'
        if content
          self.content = content.sub(/\.+$/, '') + '.'
        end
      end
  
      #set default ttl
      if !ttl
        self.ttl = 3600
      end
  
      #set default prio
      if !prio
        self.prio = 0
      end
    end
  

  end

  def db_connect
    ActiveRecord::Base.establish_connection(connect_spec)
  end

  def connect_spec
    YAML.load_file('config/database.yml')["#{ENV['RACK_ENV']}"]
  end

  def execute(sql)
    ActiveRecord::Base.connection.execute(sql)
  end
end

