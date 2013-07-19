module AppHelpers
  include PdnsConnect

  def format_errors(obj)
    return nil if obj.errors.size < 1
    errors = ''
    obj.errors.each do |fld,msg|
      errors << "error on #{fld}: #{msg}.  "
    end  
    errors
  end

  def create_domain(params)
    domain = Domains.new
    domain.name = params['name']
    domain.master = params['master']
    domain.type = params['type']
    domain.save
    #puts "id: #{domain.id}"
    r_soa = DnsRecord.new
    r_soa.domain_id = domain.id
    r_soa.name = params['name']
    r_soa.type = 'SOA'
    r_soa.ttl = params['ttl']
    r_soa.content = params['nsserver'] + ' ' + params['mail'] + ' ' + params['serial'] + ' ' + params['refresh'] + ' ' + params['retry'] + ' ' + params['expire'] + ' ' + params['ttl']
    r_soa.prio = '0'
    r_soa.pop = 'any'
    r_soa.save

    format_errors(domain)
  end

  def create_records(params)
    record = DnsRecord.new(params)
    record.before_save
    test = record.validate
    if test
      record.save
      if record.type != 'SOA'
        increment_serial(record.domain_id)
      end
    end
    format_errors(record)
  end

  def increment_serial(domain_id)
    content_soa = DnsRecord.where("domain_id = ? and type = 'SOA'", domain_id).pluck(:content)[0]
  
    if content_soa
      parts = content_soa.split(' ')
      parts[2] =  content_soa.split(' ')[2].to_i + 1
      content_soa = parts.join(' ')
      DnsRecord.where("domain_id = ? and type = 'SOA'", domain_id).update_all("content = '" + content_soa + "'")
    end
  end
end
