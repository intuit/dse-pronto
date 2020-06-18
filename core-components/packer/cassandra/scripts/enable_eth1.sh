#!/bin/bash

if [[ "$(uname -a)" =~ amzn2 ]]; then
  # ensure eth1 config is present, and used on next boot
  cd /etc/sysconfig/network-scripts
  cp ifcfg-eth0 ifcfg-eth1
  cp ifcfg-eth0 ifcfg-eth0.bak
  sed -i 's/eth0/eth1/g' ifcfg-eth1
  sed -i 's/ONBOOT=yes/ONBOOT=no/g' ifcfg-eth0

  # make sure eth1 is UP
  if [[ $(ip link show | grep -c "eth1.*state UP") == 0 ]]; then
    /sbin/ifup eth1
    sleep 10
  fi

  # make sure eth0 is DOWN
  if [[ $(ip link show | grep -c "eth0.*state DOWN") == 0 ]]; then
    echo "FYI: if running this manually while SSHing on eth0, your session is about to hang..."
    /sbin/ifdown eth0
    sleep 3
  fi

  # capture current IP
  my_eni_ip=$(ifconfig -a eth1 | grep -w inet | awk '{print $2}' | sed 's,/.*$,,' | sed 's/\./-/g')
  my_eni_hostname=ip-${my_eni_ip}.compute.internal
  ip=$(ifconfig -a eth1 | grep -w inet | awk '{print $2}')

  # make sure hostname is set properly in /etc/hosts
  if [[ ! $(hostname -i) =~ "${ip}" ]]; then
    hostnamectl set-hostname ${my_eni_hostname}
    echo "${ip} ${my_eni_hostname} ip-${my_eni_ip}" >> /etc/hosts
    echo "preserve_hostname: true" >> /etc/cloud/cloud.cfg
  fi
else
  # this is the old (rhel-7.4) version of the script, this whole "else" can be removed if/when we completely deprecate RHEL
  cd /etc/sysconfig/network-scripts
  if [[ ! -e /etc/sysconfig/network-scripts/ifcfg-eth1 ]]; then
    cp ifcfg-eth0 ifcfg-eth1
    cp ifcfg-eth0 ifcfg-eth0.bak
    sed -i 's/eth0/eth1/g' ifcfg-eth1
    sed -i 's/ONBOOT=yes/ONBOOT=no/g' ifcfg-eth0

    echo "FYI: if running this manually while SSHing on eth0, your session is about to hang..."

    /sbin/ifup eth1
    sleep 10
    /sbin/ifdown eth0
    sleep 3

    my_eni_ip=$(ifconfig -a eth1 | grep -w inet | awk '{print $2}' | sed 's,/.*$,,' | sed 's/\./-/g')
    my_eni_hostname=ip-${my_eni_ip}.compute.internal
    ip=$(ifconfig -a eth1 | grep -w inet | awk '{print $2}')
    hostnamectl set-hostname ${my_eni_hostname}
    echo "${ip} ${my_eni_hostname} ip-${my_eni_ip}" >> /etc/hosts
    echo "preserve_hostname: true" >> /etc/cloud/cloud.cfg
  fi
fi
