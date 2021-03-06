# Setting Tomcat version
# Needs to be done before invoking "tomcat::_attributes"
# TODO: - try using node.default or node.set
node.override['tomcat']['base_version'] = 7

# Invoke attribute recipes; if defined as attributes/*.rb files,
# The derived values (ie node['artifacts']['share']['version'] = node['alfresco']['version'])
# would not take the right value, if a calling cookbook changes (ie default['alfresco']['version'])
#
include_recipe 'tomcat::_attributes'
include_recipe 'alfresco::_common-attributes'
include_recipe 'alfresco::_tomcat-attributes'
include_recipe 'alfresco::_activiti-attributes'
include_recipe 'alfresco::_alfrescoproperties-attributes'
include_recipe 'alfresco::_repo-attributes'
include_recipe 'alfresco::_share-attributes'
include_recipe 'alfresco::_solr-attributes'
include_recipe 'alfresco::_googledocs-attributes'
include_recipe 'alfresco::_aos-attributes'
include_recipe 'alfresco::_media-attributes'
include_recipe 'alfresco::_analytics-attributes'

# If there is no media nor analytics, don't install activemq
install_activemq = false

# Install/configure awscli, as it's used by haproxy ec2 discovery
include_recipe 'artifact-deployer::awscli'

# [old implementation]
# Change artifactIds for alfresco and share WARs, if
# we're using an Enterprise version (ends with a digit)
# enterprise = true if Float(node['alfresco']['version'].split('').last) or node['alfresco']['version'].end_with?("SNAPSHOT") rescue false
# [New implementation]

if node['alfresco']['edition'] == 'enterprise'
  if alf_version_ge?('5.0')
    node.default['artifacts']['share']['artifactId'] = 'share'
    node.default['artifacts']['alfresco']['artifactId'] = if alf_version_ge?('5.1')
                                                            'alfresco-platform-enterprise'
                                                          else
                                                            'alfresco-enterprise'
                                                          end
  else
    node.default['artifacts']['share']['artifactId'] = 'share-enterprise'
  end
end

# Chef::Log.warn("this is my condition2 #{node['alfresco']['enable.web.xml.nossl.patch'] or node['alfresco']['edition'] == 'enterprise'}")
unless node['alfresco']['enable.web.xml.nossl.patch'] || node['alfresco']['edition'] == 'enterprise'
  node.default['artifacts']['alfresco']['classifier'] = 'nossl'
end

if alf_version_gt?('5.0') && node['alfresco']['components'].include?('repo')
  node.default['artifacts']['share-services']['enabled'] = true
  node.default['artifacts']['ROOT']['artifactId'] = 'alfresco-server-root'
end

include_recipe 'alfresco::package-repositories'

if node['alfresco']['components'].include? 'postgresql'
  include_recipe 'alfresco::postgresql-local-server'
elsif node['alfresco']['components'].include? 'mysql'
  include_recipe 'alfresco::mysql-local-server'
end

include_recipe 'java::default'

if node['alfresco']['components'].include?('yourkit')
  include_recipe 'alfresco::yourkit'
end

if node['alfresco']['components'].include?('tomcat')
  include_recipe 'alfresco::tomcat'
end

if node['alfresco']['components'].include?('nginx')
  include_recipe 'alfresco-webserver::default'
end

if node['alfresco']['components'].include?('transform')
  include_recipe 'alfresco::transformations'
end

include_recipe 'alfresco::aos' if node['alfresco']['components'].include?('aos')

if node['alfresco']['components'].include?('googledocs')
  include_recipe 'alfresco::googledocs'
end

include_recipe 'alfresco::rm' if node['alfresco']['components'].include?('rm')

if node['media']['install.content.services']
  include_recipe 'alfresco::media-content-services'
  install_activemq = true
end

if node['alfresco']['components'].include? 'media'
  include_recipe 'alfresco::media-alfresco'
end

if node['alfresco']['components'].include? 'repo'
  node.set['alfresco']['apply_amps'] = true
  include_recipe 'alfresco::repo'
end

if node['alfresco']['components'].include? 'share'
  node.set['alfresco']['apply_amps'] = true
  include_recipe 'alfresco::share'
end

if node['alfresco']['components'].include?('solr')
  include_recipe 'alfresco::solr'
end

if node['alfresco']['components'].include?('solr6')
  include_recipe 'alfresco::solr6'
end

if node['alfresco']['components'].include? 'haproxy'
  include_recipe 'alfresco::haproxy'
end

if node['alfresco']['components'].include? 'tomcat'
  include_recipe 'alfresco::tomcat-instance-config'
end

if node['alfresco']['components'].include? 'haproxy'
  include_recipe 'openssl::default'
  include_recipe 'alfresco::haproxy'
end

include_recipe 'artifact-deployer::default'

if node['alfresco']['components'].include?('solr6')
  include_recipe 'alfresco::solr6-config'
end

include_recipe 'alfresco::apply-amps' if node['alfresco']['apply_amps']

# This must go after Alfresco installation
if node['alfresco']['components'].include? 'analytics'
  include_recipe 'alfresco::analytics'
  install_activemq = true
end

include_recipe 'activemq::default' if install_activemq

if node['alfresco']['components'].include? 'rsyslog'
  include_recipe 'rsyslog::default'
end

if node['alfresco']['components'].include? 'logstash-forwarder'
  include_recipe 'alfresco::logstash-forwarder'
end

if node['alfresco']['components'].include? 'activiti'
  include_recipe 'alfresco::activiti'
end

# TODO: - This should go... as soon as Alfresco Community NOSSL war is shipped
# Patching web.xml to configure Alf-Solr comms to none (instead of https)
#
if node['alfresco']['components'].include?('tomcat') && node['alfresco']['enable.web.xml.nossl.patch']
  cookbook_file '/usr/local/bin/nossl-patch.sh' do
    source 'nossl-patch.sh'
    mode '0755'
  end
  execute 'run-nossl-patch.sh' do
    command '/usr/local/bin/nossl-patch.sh'
    user 'root'
  end
end

# Restarting services, if enabled
alfresco_start = node['alfresco']['start_service']
restart_services = node['alfresco']['restart_services']
restart_action = node['alfresco']['restart_action']
if alfresco_start && node['alfresco']['components'].include?('tomcat')
  restart_services.each do |service_name|
    # => Fix file permissions
    ["/var/cache/#{service_name}", "/var/log/#{service_name}"].each do |service|
      directory(service) do
        owner 'tomcat'
        group 'tomcat'
        mode '0750'
        recursive true
        only_if { service_name.start_with?('tomcat-') }
      end
    end

    service service_name do
      action restart_action
    end
  end
end
