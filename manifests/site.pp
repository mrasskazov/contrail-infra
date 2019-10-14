# make sure we do the minimum configuration for all nodes that
# join our puppetmaster (set-up accounts, common packages etc.)
node default {
  class { '::opencontrail_ci::server': }
}

node /tf-infra-puppetmaster2?.mosi.mirantis.net/ {
  class { '::opencontrail_ci::server': }
  class { '::opencontrail_ci::puppetmaster': }
}

node /tf-infra-puppetdb2?.mosi.mirantis.net/ {
  class { '::opencontrail_ci::server': }
  class { '::opencontrail_ci::puppetdb': }
}

node /tf-infra-logs2?.mosi.mirantis.net/ {
  class { '::opencontrail_ci::server': }
  class { '::opencontrail_ci::logserver':
    logserver_ssl_key  => hiera('logserver_ssl_key'),
    logserver_ssl_cert => hiera('logserver_ssl_cert'),
    zuul_jobs_stats    => hiera('zuul_jobs_stats'),
  }
}

node /tf-infra-zuulv3(-dev)?.mosi.mirantis.net/ {
  class { '::opencontrail_ci::server': }
  class { '::opencontrail_ci::zuul_scheduler': }
  class { '::opencontrail_ci::zuul_merger': }
  class { '::opencontrail_ci::zookeeper': }
}

node /tf-infra-nl\d+(-dev|-jnpr)?.mosi.mirantis.net/ {
  class { '::opencontrail_ci::server': }
  class { '::opencontrail_ci::nodepool_launcher': }
}

node /tf-infra-nb\d+(-dev|-jnpr)?.mosi.mirantis.net/ {
  class { '::opencontrail_ci::server': }
  class { '::opencontrail_ci::nodepool_builder': }
}

node /tf-infra-ze\d+(-dev|-jnpr)?.mosi.mirantis.net/ {
  class { '::opencontrail_ci::server': }
  class { '::opencontrail_ci::zuul_executor': }
  class { '::opencontrail_ci::zuul_executor_autossh': }
}

node /tf-infra-ci-repo.mosi.mirantis.net/ {
  class { '::opencontrail_ci::server': }
  class { '::opencontrail_ci::pulp_server': }
  class { '::opencontrail_ci::pulp_ci_repo': }
}

node /tf-infra-repo.mosi.mirantis.net/ {
  class { '::opencontrail_ci::server': }
  class { '::opencontrail_ci::pulp_server': }
  class { '::opencontrail_ci::pulp_public_repo': }
}

node /tf-infra-stats.mosi.mirantis.net/ {
  class { '::opencontrail_ci::server': }
  class { '::opencontrail_ci::stats': }
}

node /tf-infra-mirrors.mosi.mirantis.net/ {
  class {'::opencontrail_ci::server': }
  class {'::opencontrail_ci::mirror':
    vhost_name => $::fqdn,
  }
  class {'::opencontrail_ci::mirror_update': }
}

node /tf-infra-nexus.mosi.mirantis.net/ {
  class {'::opencontrail_ci::server': }
  class {'::opencontrail_ci::nexus_repository':
    registry_ports => [5001, 5002, 5003, 5005, 5006, 5007, 5010],
  }
}
