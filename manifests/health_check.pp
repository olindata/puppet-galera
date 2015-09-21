#
# class galera::health_check provides in-depth monitoring of a MySQL Galera Node. 
# The class is meant to be used in conjunction with HAProxy.
# The class  has only been tested on Ubuntu 12.04 and HAProxy 1.4.18-0ubuntu1
#
# Requires augeas puppet module
#
# Here is an example HAProxy configuration that implements Galera health checking
#listen galera 192.168.220.40:3306
#  balance  leastconn
#  mode  tcp
#  option  tcpka
#  option  httpchk
#  server  control01 192.168.220.41:3306 check port 9200 inter 2000 rise 2 fall 5
#  server  control02 192.168.220.42:3306 check port 9200 inter 2000 rise 2 fall 5
#  server  control03 192.168.220.43:3306 check port 9200 inter 2000 rise 2 fall 5
#
# Example Usage:
#
# class {'galera::health_check': }
#
class galera::health_check(
  $mysql_host           = '127.0.0.1',
  $mysql_port           = '3306',
  $mysql_bin_dir        = '/usr/bin/mysql',
  $mysql_datadir        = '/var/lib/mysql',
  $mysqlchk_script_dir  = '/usr/local/bin',
  $xinetd_dir 	        = '/etc/xinetd.d',
  $mysqlchk_user        = 'mysqlchk_user',
  $mysqlchk_password    = 'mysqlchk_password',
  $mysqlchk_port        = 9200,
  $report_donating_node_as_healthy = false,
  $enabled              = true,
  $debug                = 0,
) {

  # Needed to manage /etc/services
  include ::augeas

  # xinetd runs the checking script
  include ::xinetd

  if $enabled {
    $service_ensure = 'running'
  } else {
    $service_ensure = 'stopped'
  }

  file { $mysqlchk_script_dir:
    ensure  => directory,
    mode    => '0755',
    require => Package['xinetd'],
    owner   => 'root',
    group   => 'root',
  }

  file { "${mysqlchk_script_dir}/clustercheck":
    mode    => '0755',
    require => File[$mysqlchk_script_dir],
    content => template("galera/clustercheck.erb"),
    owner   => 'root',
    group   => 'root',
  }

  # setup mysqlchk service
  xinetd::service {"mysqlchk":
    disable     => 'no',
    flags       => 'REUSE',
    socket_type => 'stream',
    port        => $mysqlchk_port,
    wait        => 'no',
    user        => nobody,
    server      => "${mysqlchk_script_dir}/clustercheck",
    log_on_failure => 'USERID',
    only_from   => '0.0.0.0/0',
    per_source  => 'UNLIMITED',
  }

  # manage mysqlchk service for both centos and debian based OS
  file_line { 'mysqlchk':
    path => '/etc/services',
    line => "mysqlchk  ${mysqlchk_port}/tcp            # mysqlchk service",
  }

#  This manage mysqlchk service works only for debian
#  # Manage mysqlchk service in /etc/services
#  augeas { "mysqlchk":
#    require => File["${xinetd_dir}/mysqlchk"],
#    context =>  "/files/etc/services",
#    changes => [
#      "ins service-name after service-name[last()]",
#      "set service-name[last()] mysqlchk",
#      "set service-name[. = 'mysqlchk']/port ${mysqlchk_port}",
#      "set service-name[. = 'mysqlchk']/protocol tcp",
#    ],
#    onlyif => "match service-name[port = '${mysqlchk_port}'] size == 0",
#  }

  # Create a user for script to use for checking MySQL health status.
  mysql_user { "${mysqlchk_user}@${mysql_host}":
    ensure        => present,
    password_hash => mysql_password($mysqlchk_password),
    require       => Class['::mysql::server::service'],
  }
}
