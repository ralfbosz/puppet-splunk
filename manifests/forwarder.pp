# Class: splunk
#
# This class deploys the Splunk Universal Forwarder on Linux, Windows, Solaris
# platforms.
#
# Parameters:
#
# [*server*]
#   The address of a server to send logs to.
#
# [*package_source*]
#   The source URL for the splunk installation media (typically an RPM, MSI,
#   etc). If a $src_root parameter is set in splunk::params, this will be
#   automatically supplied. Otherwise it is required. The URL can be of any
#   protocol supported by the nanliu/staging module.
#
# [*package_name*]
#   The name of the package(s) as they will exist or be detected on the host.
#
# [*logging_port*]
#   The port to send splunktcp logs to.
#
# [*splunkd_port*]
#   The splunkd port. Used as a default for both splunk and splunk::forwarder.
#
# [*install_options*]
#   The splunkd forwarder installation options. Only applicable for Windows.
#
# [*splunkd_listen*]
#   The address on which splunkd should listen. Defaults to localhost only.
#
# [*purge_inputs*]
#   If set to true, will remove any inputs.conf configuration not supplied by
#   Puppet from the target system. Defaults to false.
#
# [*purge_outputs*]
#   If set to true, will remove any outputs.conf configuration not supplied by
#   Puppet from the target system. Defaults to false.
#
# Actions:
#
#   Declares parameters to be consumed by other classes in the splunk module.
#
# Requires: nothing
#
class splunk::forwarder (
  $server            = $splunk::params::server,
  $package_source    = $splunk::params::forwarder_pkg_src,
  $package_name      = $splunk::params::forwarder_pkg_name,
  $package_ensure    = $splunk::params::forwarder_pkg_ensure,
  $logging_port      = $splunk::params::logging_port,
  $splunkd_port      = $splunk::params::splunkd_port,
  $install_options   = $splunk::params::forwarder_install_options,
  $splunk_user       = $splunk::params::splunk_user,
  $splunkd_listen    = '127.0.0.1',
  $purge_inputs      = false,
  $purge_outputs     = false,
  $purge_props       = false,
  $purge_transforms  = false,
  $purge_web         = false,
  $pkg_provider      = $splunk::params::pkg_provider,
  $forwarder_confdir = $splunk::params::forwarder_confdir,
  $forwarder_output  = $splunk::params::forwarder_output,
  $forwarder_input   = $splunk::params::forwarder_input,
  $create_password   = $splunk::params::create_password,
  $addons            = {},
) inherits splunk::params {

  $virtual_service = $splunk::params::forwarder_service
  $staging_subdir  = $splunk::params::staging_subdir

  $path_delimiter  = $splunk::params::path_delimiter
  #no need for staging the source if we have yum or apt
  if $pkg_provider != undef and $pkg_provider != 'yum' and $pkg_provider != 'apt' and $pkg_provider != 'chocolatey' {
    include ::staging

    $staged_package  = staging_parse($package_source)
    $pkg_path_parts  = [$staging::path, $staging_subdir, $staged_package]
    $pkg_source      = join($pkg_path_parts, $path_delimiter)

    staging::file { $staged_package:
      source => $package_source,
      subdir => $staging_subdir,
      before => Package[$package_name],
    }
  }
  package { $package_name:
    ensure          => $package_ensure,
    provider        => $pkg_provider,
    source          => $pkg_source,
    before          => Service[$virtual_service],
    install_options => $install_options,
    tag             => 'splunk_forwarder',
  }

  # Declare addons
  create_resources('splunk::addon', $addons)

  # Ensure that the service restarts upon changes to addons
  Package[$package_name] -> Splunk::Addon <||> ~> Service[$virtual_service]

  # Declare inputs and outputs specific to the forwarder profile
  $tag_resources = { tag => 'splunk_forwarder' }
  create_resources( 'splunkforwarder_input',$forwarder_input, $tag_resources)
  create_resources( 'splunkforwarder_output',$forwarder_output, $tag_resources)
  # this is default
  splunkforwarder_web { 'forwarder_splunkd_port':
    section => 'settings',
    setting => 'mgmtHostPort',
    value   => "${splunkd_listen}:${splunkd_port}",
    tag     => 'splunk_forwarder',
  }

  # If the purge parameters have been set, remove all unmanaged entries from
  # the respective config files.

  Splunk_config['splunk'] {
    purge_forwarder_outputs    => $purge_outputs,
    purge_forwarder_inputs     => $purge_inputs,
    purge_forwarder_props      => $purge_props,
    purge_forwarder_transforms => $purge_transforms,
    purge_forwarder_web        => $purge_web,
  }

  # This is a module that supports multiple platforms. For some platforms
  # there is non-generic configuration that needs to be declared in addition
  # to the agnostic resources declared here.
  case $::kernel {
    'Linux': {
      class { '::splunk::platform::posix':
        splunkd_port => $splunkd_port,
        splunk_user  => $splunk_user,
      }
    }
    'SunOS': { include ::splunk::platform::solaris }
    default: { } # no special configuration needed
  }

  # Realize resources shared between server and forwarder profiles, and set up
  # dependency chains.
  include ::splunk::virtual

  realize Service[$virtual_service]

  Package[$package_name] ->
  File <| tag   == 'splunk_forwarder' |> ->
  Exec <| tag   == 'splunk_forwarder' |> ->
  Service[$virtual_service]

  Package[$package_name] -> Splunkforwarder_output<||>     ~> Service[$virtual_service]
  Package[$package_name] -> Splunkforwarder_input<||>      ~> Service[$virtual_service]
  Package[$package_name] -> Splunkforwarder_props<||>      ~> Service[$virtual_service]
  Package[$package_name] -> Splunkforwarder_transforms<||> ~> Service[$virtual_service]
  Package[$package_name] -> Splunkforwarder_web<||>        ~> Service[$virtual_service]

  if $::osfamily == 'windows' {
    File {
      owner => $splunk_user,
      group => $splunk_user,
    }
  } else {
    File {
      owner => $splunk_user,
      group => $splunk_user,
      mode => '0644',
    }
  }

  file { "${forwarder_confdir}/system/local/inputs.conf":
    ensure => file,
    tag    => 'splunk_forwarder',
  }

  file { "${forwarder_confdir}/system/local/outputs.conf":
    ensure => file,
    tag    => 'splunk_forwarder',
  }

  file { "${forwarder_confdir}/system/local/web.conf":
    ensure => file,
    tag    => 'splunk_forwarder',
  }

  # Validate: if both Splunk and Splunk Universal Forwarder are installed on
  # the same system, then they must use different admin ports.
  if (defined(Class['splunk']) and defined(Class['splunk::forwarder'])) {
    $s_port = $splunk::splunkd_port
    $f_port = $splunk::forwarder::splunkd_port
    if $s_port == $f_port {
      fail(regsubst("Both splunk and splunk::forwarder are included, but both
        are configured to use the same splunkd port (${s_port}). Please either
        include only one of splunk, splunk::forwarder, or else configure them
        to use non-conflicting splunkd ports.", '\s\s+', ' ', 'G')
      )
    }
  }
}
