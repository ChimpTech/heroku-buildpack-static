# ghetto require, since mruby doesn't have require
eval(File.read('/app/bin/config/lib/nginx_config_util.rb'))

USER_CONFIG = '/app/static.json'

config    = {}
config    = JSON.parse(File.read(USER_CONFIG)) if File.exist?(USER_CONFIG)
req       = Nginx::Request.new
uri       = req.var.uri
headers   = req.headers_in
proxies   = config['proxies'] || {}
redirects = config['redirects'] || {}
cookies   = Hash[
  headers['Cookie'].
  split(';').
  map(&:strip).
  map{|kvp| kvp.split('=') }.
  select{|kvp| kvp.is_a?(Array) && kvp.size == 2}
] if headers['Cookie']
cookies ||= {}

if proxy = proxies[NginxConfigUtil.match_proxies(proxies.keys, uri)]
  if proxy['header_switch']
    value   = headers[proxy['header_switch']['header']]
    backend = proxy['header_switch']['origin_map'][value.strip] if value
  end

  if proxy['split_clients']
    route_key    = proxy['split_clients']['route_key']
    destinations = proxy['split_clients'].select{|_,v| v.is_a?(Array) }.keys
    param        = req.var.__send__("arg_#{route_key}".to_sym)
    split_var    = req.var.__send__(route_key.to_sym)

    destination   = param if destinations.include?(param)
    destination ||= cookies[route_key] if destinations.include?(cookies[route_key])
    destination ||= split_var

    proxy['split_clients'].select{|_,v| v.is_a?(Array) }.each do |dest, dest_info|
      if dest == destination
        backend ||= dest_info.last
        break
      end
    end

    req.headers_out['Set-Cookie'] = "#{route_key}=#{destination}"
  end

  backend ||= proxy['origin']

  "@#{backend.gsub(NginxConfigUtil.proxy_strip_regex, '')}"
elsif redirect = NginxConfigUtil.match_redirects(redirects.keys, uri)
  "@#{redirect}"
else
  '@404'
end
