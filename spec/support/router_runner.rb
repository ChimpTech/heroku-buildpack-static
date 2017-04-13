require_relative "router_builder"
require_relative "container_runner"

class RouterRunner < ContainerRunner
  def self.boot2docker_ip
    %x(boot2docker ip).match(/([0-9]{1,3}\.){3}[0-9]{1,3}/)[0]
  rescue Errno::ENOENT
  end

  HTTP_PORT  = (1024 + rand(65535 - 1024)).to_s
  HTTPS_PORT = (1024 + rand(65535 - 1024)).to_s
  HOST_IP    = boot2docker_ip || "127.0.0.1"

  def initialize(app_id, delete = true)
    super({
      "Image"      => RouterBuilder::TAG,
      "HostConfig" => {
        "Links" => ["#{app_id}:app"],
        "PortBindings" => {
          "80/tcp" => [{
            "HostIp"   => HOST_IP,
            "HostPort" => HTTP_PORT
          }],
          "443/tcp" => [{
            "HostIp"   => HOST_IP,
            "HostPort" => HTTPS_PORT
          }]
        }
      }
    }, delete)
  end
end
