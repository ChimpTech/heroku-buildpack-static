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

if proxy = proxies[NginxConfigUtil.match_proxies(proxies.keys, uri)]
  backend = nil
  if proxy['header_switch']
    value     = headers[proxy['header_switch']['header']]
    backend   = proxy['header_switch']['origin_map'][value.strip] if value
  end

  if proxy['split_clients']
    route_key     = proxy['split_clients']['route_key']
    cookie_regex  = Regexp.compile("#{route_key}=([\\S][^;]*)")

    Nginx.log Nginx::INFO, "arg_#{route_key}: " + req.var.__send__("arg_#{route_key}".to_sym)
    Nginx.log Nginx::INFO, "Cookies: " + headers['Cookies'].inspect
    Nginx.log Nginx::INFO, "variable: " + req.var.__send__(route_key.to_sym)


    destination   = req.var.__send__("arg_#{route_key}".to_sym)
    destination ||= headers['Cookies'].matches(cookie_regex)[1] if cookie_regex =~ headers['Cookies']
    destination ||= req.var.__send__(route_key.to_sym)

    proxy['split_clients'].select{|_,v| v.is_a?(Array) }.each do |dest, dest_info|
      if dest == destination
        backend ||= dest_info.last
        req.headers_out['Set-Cookie'] = "split=#{destination}"
        break
      end
    end

    unless backend
      backend = proxy['split_clients'].select{|_,v| v.is_a?(Array) }.values.detect{|v| v.first == '*'}.last
      req.headers_out['Set-Cookie'] = "split=#{req.var.__send__(route_key.to_sym)}"
    end
  end

  backend ||= proxy['origin']

  "@#{backend.gsub(NginxConfigUtil.proxy_strip_regex, '')}"
elsif redirect = NginxConfigUtil.match_redirects(redirects.keys, uri)
  "@#{redirect}"
else
  Nginx.log Nginx::LOG_INFO, "404 from proxy handler"
  '@404'
end
