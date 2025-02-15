#!/bin/bash -x

# Copyright 2013 OpenStack Foundation.
# Copyright 2013 Hewlett-Packard Development Company, L.P.
# Copyright 2013 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# NOTE(pabelanger): We now use the pip-and-virtualenv element from
# diskimage-builder to do this. Default to true for backwards compatibility.
SETUP_PIP=${SETUP_PIP:-true}

#
# Distro identification functions
#  note, can't rely on lsb_release for these as we're bare-bones and
#  it may not be installed yet)


function is_fedora {
    [ -f /usr/bin/yum ] && cat /etc/*release | grep -q -e "Fedora"
}

function is_rhel7 {
    [ -f /usr/bin/yum ] && \
        cat /etc/*release | grep -q -e "Red Hat" -e "CentOS" -e "CloudLinux" && \
        cat /etc/*release | grep -q 'release 7'
}

function is_ubuntu {
    [ -f /usr/bin/apt-get ]
}

function is_opensuse {
    [ -f /usr/bin/zypper ] && \
        cat /etc/os-release | grep -q -e "openSUSE"
}

function is_gentoo {
    [ -f /usr/bin/emerge ]
}

# dnf is a drop-in replacement for yum on Fedora>=22
YUM=yum
if is_fedora && [[ $(lsb_release -rs) -ge 22 ]]; then
    YUM=dnf
fi


#
# Distro specific puppet installs
#

function _systemd_update {
    # there is a bug (rhbz#1261747) where systemd can fail to enable
    # services due to selinux errors after upgrade.  A work-around is
    # to install the latest version of selinux and systemd here and
    # restart the daemon for good measure after it is upgraded.
    $YUM install -y selinux-policy
    $YUM install -y systemd
    systemctl daemon-reload
}

function setup_puppet_fedora {
    _systemd_update

    $YUM update -y

    # NOTE: we preinstall lsb_release here to ensure facter sets
    # lsbdistcodename
    #
    # Fedora declares some global hardening flags, which distutils
    # pick up when building python modules.  redhat-rpm-config
    # provides the required config options.  Really this should be a
    # dependency of python-devel (fix in the works, see
    # https://bugzilla.redhat.com/show_bug.cgi?id=1217376) and can be
    # removed when that is sorted out.

    $YUM install -y redhat-lsb-core git puppet \
        redhat-rpm-config

    mkdir -p /etc/puppet/modules/

    if $SETUP_PIP; then
        # Puppet expects the pip command named as pip-python on
        # Fedora, as per the packaged command name.  However, we're
        # installing from get-pip.py so it's just 'pip'.  An easy
        # work-around is to just symlink pip-python to "fool" it.
        # See upstream issue:
        #  https://tickets.puppetlabs.com/browse/PUP-1082
        ln -fs /usr/bin/pip /usr/bin/pip-python
    fi

    # Wipe out templatedir so we don't get warnings about it
    sed -i '/templatedir/d' /etc/puppet/puppet.conf

    # upstream is currently looking for /run/systemd files to check
    # for systemd.  This fails in a chroot where /run isn't mounted
    # (like when using dib).  Comment out this confine as fedora
    # always has systemd
    #  see
    #   https://github.com/puppetlabs/puppet/pull/4481
    #   https://bugzilla.redhat.com/show_bug.cgi?id=1254616
    sudo sed -i.bak  '/^[^#].*/ s|\(^.*confine :exists => \"/run/systemd/system\".*$\)|#\ \1|' \
        /usr/share/ruby/vendor_ruby/puppet/provider/service/systemd.rb

    # upstream "requests" pip package vendors urllib3 and chardet
    # packages.  The fedora packages un-vendor this, and symlink those
    # sub-packages back to packaged versions.  We get into a real mess
    # of if some of the puppet ends up pulling in "requests" from pip,
    # and then something like devstack does a "yum install
    # python-requests" which does a very bad job at overwriting the
    # pip-installed version (symlinks and existing directories don't
    # mix).  A solution is to pre-install the python-requests
    # package; clear it out and re-install from pip.  This way, the
    # package is installed for dependencies, and we have a pip-managed
    # requests with correctly vendored sub-packages.
    sudo ${YUM} install -y python2-requests
    sudo rm -rf /usr/lib/python2.7/site-packages/requests/*
    sudo rm -rf /usr/lib/python2.7/site-packages/requests-*.{egg,dist}-info
    sudo pip install requests
}

function setup_puppet_rhel7 {
    local puppet_pkg="https://yum.puppetlabs.com/puppetlabs-release-el-7.noarch.rpm"

    _systemd_update
    yum update -y

    # NOTE: we preinstall lsb_release to ensure facter sets lsbdistcodename
    yum install -y redhat-lsb-core git

    # Install puppetlabs repo & then puppet comes from there
    rpm -ivh $puppet_pkg
    yum install -y puppet

    if $SETUP_PIP; then
        # see comments in setup_puppet_fedora
        ln -s /usr/bin/pip /usr/bin/pip-python
    fi

    # Wipe out templatedir so we don't get warnings about it
    sed -i '/templatedir/d' /etc/puppet/puppet.conf

    # install CentOS OpenStack repos as well (rebuilds of RDO
    # packages).  We don't use openstack project rpm files, but covers
    # a few things like qemu-kvm-ev (the forward port of qemu with
    # later features) that aren't available in base.  We need this
    # early for things like openvswitch (XXX: should be installed via
    # dib before this?)
    yum install -y centos-release-openstack-ocata
}

function setup_puppet_ubuntu {
    if ! which lsb_release > /dev/null 2<&1 ; then
        DEBIAN_FRONTEND=noninteractive apt-get --option 'Dpkg::Options::=--force-confold' \
            --assume-yes install -y --force-yes lsb-release
    fi

    lsbdistcodename=`lsb_release -c -s`
    if [ $lsbdistcodename != 'trusty' ] ; then
        rubypkg=rubygems
    else
        rubypkg=ruby
    fi


    PUPPET_VERSION=3.*
    PUPPETDB_VERSION=2.*
    FACTER_VERSION=2.*

    cat > /etc/apt/preferences.d/00-puppet.pref <<EOF
Package: puppet puppet-common puppetmaster puppetmaster-common puppetmaster-passenger
Pin: version $PUPPET_VERSION
Pin-Priority: 501

Package: puppetdb puppetdb-terminus
Pin: version $PUPPETDB_VERSION
Pin-Priority: 501

Package: facter
Pin: version $FACTER_VERSION
Pin-Priority: 501
EOF

    # NOTE(pabelanger): Puppetlabs does not support ubuntu xenial. Instead use
    # the version of puppet ship by xenial.
    if [ $lsbdistcodename != 'xenial' ]; then
        puppet_deb=puppetlabs-release-${lsbdistcodename}.deb
    else
        puppet_deb=puppetlabs-release-pc1-${lsbdistcodename}.deb
    fi
    if type curl >/dev/null 2>&1; then
        curl -O http://apt.puppetlabs.com/$puppet_deb
    else
        wget http://apt.puppetlabs.com/$puppet_deb -O $puppet_deb
    fi
    dpkg -i $puppet_deb
    rm $puppet_deb

	DEBIAN_FRONTEND=noninteractive apt-get update

    # ansible also requires python2 on the host to run correctly.
    # Make sure we have it, as some images come without it
    DEBIAN_FRONTEND=noninteractive apt-get --option 'Dpkg::Options::=--force-confold' \
        --assume-yes install python-minimal

    DEBIAN_FRONTEND=noninteractive apt-get --option 'Dpkg::Options::=--force-confold' \
        --assume-yes dist-upgrade
    DEBIAN_FRONTEND=noninteractive apt-get --option 'Dpkg::Options::=--force-confold' \
        --assume-yes install -y --force-yes puppet git $rubypkg
    # Wipe out templatedir so we don't get warnings about it
    sed -i '/templatedir/d' /etc/puppet/puppet.conf
    if [ -f /bin/systemctl ]; then
        systemctl disable puppet
    else
        update-rc.d -f puppet disable
    fi
}

function setup_puppet_opensuse {
    zypper --non-interactive install --force-resolution puppet
    # Wipe out templatedir so we don't get warnings about it
    sed -i '/templatedir/d' /etc/puppet/puppet.conf
}

function setup_puppet_gentoo {
    echo yes | emaint sync -a
    emerge -q --jobs=4 puppet-agent
    sed -i '/templatedir/d' /etc/puppetlabs/puppet/puppet.conf
}

#
# pip setup
#

function setup_pip {
    # Install pip using get-pip
    local get_pip_url=https://bootstrap.pypa.io/get-pip.py
    local ret=1

    if [ -f ./get-pip.py ]; then
        ret=0
    elif type curl >/dev/null 2>&1; then
        curl -O $get_pip_url
        ret=$?
    elif type wget >/dev/null 2>&1; then
        wget $get_pip_url
        ret=$?
    fi

    if [ $ret -ne 0 ]; then
        echo "Failed to get get-pip.py"
        exit 1
    fi

    if is_opensuse; then
        zypper --non-interactive install --force-resolution python python-xml
    fi

    # ubuntu get-pip.py dependencies
    if is_ubuntu; then
        DEBIAN_FRONTEND=noninteractive apt-get --option 'Dpkg::Options::=--force-confold' \
            --assume-yes install -y --force-yes python software-properties-common
    fi

    python get-pip.py
    rm get-pip.py

    # we are about to overwrite setuptools, but some packages we
    # install later might depend on the python-setuptools package.  To
    # avoid later conflicts, and because distro packages don't include
    # enough info for pip to certain it can fully uninstall the old
    # package, for safety we clear it out by hand (this seems to have
    # been a problem with very old to new updates, e.g. centos6 to
    # current-era, but less so for smaller jumps).  There is a bit of
    # chicken-and-egg problem with pip in that it requires setuptools
    # for some operations, such as wheel creation.  But just
    # installing setuptools shouldn't require setuptools itself, so we
    # are safe for this small section.
    if is_rhel7 || is_fedora; then
        yum install -y python-setuptools
        rm -rf /usr/lib/python2.7/site-packages/setuptools*
    fi

    pip install -U setuptools
}

# single apt-get update for setup_pip and setup_puppet
if is_ubuntu; then
    apt-get update
fi

if $SETUP_PIP; then
    setup_pip
fi

if is_fedora; then
    setup_puppet_fedora
elif is_rhel7; then
    setup_puppet_rhel7
elif is_ubuntu; then
    setup_puppet_ubuntu
elif is_opensuse; then
    setup_puppet_opensuse
elif is_gentoo; then
    setup_puppet_gentoo
else
    echo "*** Can not setup puppet: distribution not recognized"
    exit 1
fi
