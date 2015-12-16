haproxy_cfg_source = node['haproxy']['conf_template_source']
haproxy_cfg_cookbook = node['haproxy']['conf_cookbook']
enable_rsyslog_server = node['haproxy']['enable_rsyslog_server']
rsyslog_bind = node['haproxy']['rsyslog_bind']

include_recipe 'alfresco::_certs'
include_recipe 'alfresco::_errorpages'

if node['haproxy']['enable_ssl_header']
  node.default['haproxy']['frontends']['external']['headers'] = [node['haproxy']['ssl_header']]
  node.default['haproxy']['backends']['share']['secure_entries'] =  node['haproxy']['secure_entries']
end

# Install haproxy discovery
install_haproxy_discovery = node['haproxy']['ec2']['install_haproxy_discovery']
if install_haproxy_discovery
  node.default['commons']['chef-client-cron']['cron_name'] = "haproxy-discovery"
  node.default['commons']['chef-client-cron']['chef_json_cookbook'] = "alfresco"
  node.default['commons']['chef-client-cron']['chef_json_source'] = "haproxy/haproxy-discovery.json.erb"
  include_recipe 'commons::chef-client-cron'
end

if node['haproxy']['logging_json_enabled']
  node.default['haproxy']['logformat'] = node['haproxy']['json_logformat']
end

include_recipe 'haproxy::default'
include_recipe 'alfresco::haproxy-config'


# TODO - rsyslog stuff should go somewhere else (not sure where)

# Haproxy rsyslog configuration
directory "/var/log/haproxy" do
  action :create
  owner "haproxy"
  group "haproxy"
end
template "/etc/rsyslog.d/haproxy.conf" do
  source "rsyslog/haproxy.conf.erb"
end

# TODO - this block can be contributed to a lib cookbook, somewhere
# Make sure Rsyslog is configured to receive Haproxy logs
if enable_rsyslog_server and File.exist?('/etc/rsyslog.conf')
  lines_to_append = [
    ["$ModLoad imudp",nil],
    ["$UDPServerAddress #{rsyslog_bind}","$UDPServerAddress"],
    ["$UDPServerRun 514","$UDPServerRun"]
  ]

  lines_to_append.each do |line|
    new_line = line[0]
    line_match = line[1]

    if line_match == nil
      line_match = new_line
    end
    replace_or_add "rsyslog-conf-#{line}" do
      path "/etc/rsyslog.conf"
      pattern line_match
      line new_line
      notifies :restart, 'service[rsyslog]', :delayed
    end
  end

  service 'rsyslog' do
    action :nothing
  end
end

# include_recipe 'rsyslog::server'

# Disable default server configuration, we just need haproxy
# r = resources(template: "#{node['rsyslog']['config_prefix']}/rsyslog.d/35-server-per-host.conf")
# r.action(:nothing)
