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

def proxy_or_redirect(headers, redirects, proxies, req)
  if proxy = proxies[NginxConfigUtil.match_proxies(proxies.keys, uri)]
    determine_proxy(proxy, headers, req)
  elsif redirect = NginxConfigUtil.match_redirects(redirects.keys, uri)
    Nginx::Stream.log Nginx::Stream::LOG_NOTICE, "Redirecting to: #{redirect}"
    "@#{redirect}"
  else
    Nginx::Stream.log Nginx::Stream::LOG_NOTICE, "Unable to proxy or redirect, returning 404."
    '@404'
  end
end

def determine_proxy(proxy, headers, req)
  if proxy['header_switch']
    value     = headers[proxy['header_switch']['header']]
    backend   = proxy['header_switch']['origin_map'][value.strip] if value
  end

  backend ||= proxy['origin']
  proxy_id = backend.gsub(NginxConfigUtil.proxy_strip_regex, '')
  Nginx::Stream.log Nginx::Stream::LOG_NOTICE, "Proxying to: #{proxy_id}"
  "@#{proxy_id}"
end

proxy_or_redirect(headers, redirects, proxies, req)
