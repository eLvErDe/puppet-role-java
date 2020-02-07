# Class for deploying JRE/JDK
#
# == Parameters
#
# $enable: Deploy JRE, defaults to false
# $enable_jdk: Deploy JDK, defaults to false
# $enable_headless: Deploy headless java, defaults to true
# $java_major: Deploy specific java version, defaults to undef (distrib latest)
#


class role_java (

  Boolean $enable               = false,
  Boolean $enable_jdk           = false,
  Boolean $enable_headless      = true,
  Optional[Integer] $java_major = undef,

) {

  # Sanity checks and defines
  # Cannot enable this if I want to support Debian Stretch with Puppet 4.8
  #$distro_lowercase = downcase($::facts['os']['distro']['id'])
  #$distro_majorver = $::facts['os']['release']['major']
  #$distro_arch = $::facts['os']['architecture']
  $distro_lowercase = $::operatingsystem
  $distro_majorver = $::operatingsystemmajrelease
  $distro_arch = $::architecture

  case $distro_lowercase {
    'debian': {
      case $distro_majorver {
        "10": {
          $default_java_major = 11
        }
        "9": {
          $default_java_major = 8
        }
        default: {
          fail("Only supported on debian 10 or 9, got ${distro_majorver}")
        }
      }
    }
    'ubuntu': {
      case $distro_majorver {
        "18.04": {
          $default_java_major = 11
        }
        "16.04": {
          $default_java_major = 8
        }
        default: {
          fail("Only supported on ubuntu 18.04 or 16.04, got ${distro_majorver}")
        }
      }
    }
    default: {
      fail("Only supported on debian or ubuntu, got ${distro_lowercase}")
    }
  }

  if ($enable) {

    # JRE or JDK
    $computed_distribution = $enable_jdk ? { true => "jdk", default => "jre" }

    # Compute major version
    $computed_java_major = $java_major ? { undef => $default_java_major, default => $java_major }

    # Package name
    $package_base = "openjdk-${java_major}-${computed_distribution}"
    $package_suffix = $enable_headless ? { true => "-headless", default => "" }
    $computed_package = "${package_base}${package_suffix}"

    # Java alternative (to set as default)
    $computed_java_alternative = "java-${computed_java_major}-openjdk-${distro_arch}"
    $computed_java_alternative_path = "/usr/lib/jvm/${computed_java_alternative}/bin/java"

    # OpenJDK 8 is not usable on ARM
    # Deb available from http://packages.le-vert.net/mesos/debian/pool-buster/oracle-java8-installer_for_arm_builds/
    if ($distro_lowercase in ["debian", "ubuntu"] and $distro_arch in ["aarch64", "armv7l"] and $computed_java_major == 8) {

      # Install Oracle non-free file first
      $jdk_version = '8u211'
      $jdk_tarball_filename = $distro_arch ? { "armv7l" => "jdk-${jdk_version}-linux-arm32-vfp-hflt.tar.gz", "aarch64" => "jdk-${jdk_version}-linux-arm64-vfp-hflt.tar.gz" }
      file { 'oracle-8-jdk-cache-folder':
        path   => '/var/cache/oracle-jdk8-installer',
        ensure => 'directory',
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
      }
      file { 'oracle-8-jdk-cache-tarball':
        path => "/var/cache/oracle-jdk8-installer/${jdk_tarball_filename}",
        ensure => 'file',
        owner  => 'root',
        group  => 'root',
        mode   => '0644',
        source => "puppet:///modules/role_java/oracle/8/${jdk_tarball_filename}",
        notify => Exec['debconf-accept-oracle-8-jdk-license'],
      }
      exec { 'debconf-accept-oracle-8-jdk-license':
        command     => '/bin/echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | /usr/bin/debconf-set-selections',
        refreshonly => true,
      }
      class { 'java':
        distribution          => $computed_distribution,
        package               => 'oracle-java8-installer',
        version               => '8u211+1~levert1',
        java_alternative      => 'java-8-oracle',
        java_alternative_path => '/usr/lib/jvm/java-8-oracle/bin/java',
        require               => [File['oracle-8-jdk-cache-tarball'], Exec['debconf-accept-oracle-8-jdk-license']],
      }

    # Regular case, using OpenJDK
    } else {
      class { 'java':
        distribution          => $computed_distribution,
        package               => $computed_package,
        java_alternative      => $computed_java_alternative,
        java_alternative_path => $computed_java_alternative_path,
      }
    }

  }

}
