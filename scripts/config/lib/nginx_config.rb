require 'json'
require 'uri'
require_relative 'nginx_config_util'

class NginxConfig
  DEFAULT = {
    root: "public_html/",
    encoding: "UTF-8",
    clean_urls: false,
    https_only: false,
    worker_connections: 512,
    resolver: "8.8.8.8",
    logging: {
      "access" => true,
      "error" => "error"
    }
  }

  def initialize(json_file)
    json = {}
    json = JSON.parse(File.read(json_file)) if File.exist?(json_file)
    json["worker_connections"] ||= ENV["WORKER_CONNECTIONS"] || DEFAULT[:worker_connections]
    json["port"] ||= ENV["PORT"] || 5000
    json["root"] ||= DEFAULT[:root]
    json["encoding"] ||= DEFAULT[:encoding]

    json['proxies']     ||= {}
    json['split_clients'] = false
    json['route_keys']    = []
    json['proxies'].each do |loc, proxy_hash|
      hosts = []
      hosts << proxy_hash['origin']
      proxy_hash['backends'] = {}

      proxy_hash['header_switch'] ||= {}
      proxy_hash['header_switch']['origin_map'] ||= {}
      hosts += proxy_hash['header_switch']['origin_map'].values

      if proxy_hash['split_clients']
        json['split_clients'] = true
        hosts += proxy_hash['split_clients'].values.select{|v| v.is_a?(Array) }.map(&:last)

        proxy_hash['split_clients'].select{|_,v| v.is_a?(Array) }.each do |split_name, split_data|
          split_data[0] = NginxConfigUtil.interpolate(split_data[0], ENV)

          unless split_name == NginxConfigUtil.interpolate(split_name, ENV)
            proxy_hash['split_clients'].delete(split_name)
            proxy_hash['split_clients'][NginxConfigUtil.interpolate(split_name, ENV)]
          end
        end
      end

      hosts.each do |host|
        host_id = host.gsub(NginxConfigUtil.proxy_strip_regex, '')
        uri     = URI(NginxConfigUtil.interpolate(host, ENV))

        cleaned_path = uri.path
        cleaned_path.chop! if cleaned_path.end_with?('/')

        proxy_hash['backends'][host_id] = {}
        proxy_hash['backends'][host_id]['path'] = cleaned_path
        proxy_hash['backends'][host_id]['host'] = uri.dup.tap {|u| u.path = '' }.to_s
        %w(http https).each do |scheme|
          proxy_hash['backends'][host_id]["redirect_#{scheme}"] = uri.dup.tap {|u| u.scheme = scheme }.to_s
          proxy_hash['backends'][host_id]["redirect_#{scheme}"] += '/' if !uri.to_s.end_with?('/')
        end
      end
    end

    json["clean_urls"] ||= DEFAULT[:clean_urls]
    json["https_only"] ||= DEFAULT[:https_only]

    json["routes"] ||= {}
    json["routes"] = NginxConfigUtil.parse_routes(json["routes"])

    json["redirects"] ||= {}
    json["redirects"].each do |loc, hash|
      json["redirects"][loc].merge!("url" => NginxConfigUtil.interpolate(hash["url"], ENV))
    end

    json["error_page"] ||= nil
    json["debug"] = ENV['STATIC_DEBUG']

    logging = json["logging"] || {}
    json["logging"] = DEFAULT[:logging].merge(logging)

    nameservers = []
    if File.exist?("/etc/resolv.conf")
      File.open("/etc/resolv.conf", "r").each do |line|
        next unless md = line.match(/^nameserver\s*(\S*)/)
        nameservers << md[1]
      end
    end
    nameservers << [DEFAULT[:resolver]] unless nameservers.empty?
    json["resolver"] = nameservers.join(" ")

    json.each do |key, value|
      self.class.send(:define_method, key) { value }
    end
  end

  def context
    binding
  end
end
