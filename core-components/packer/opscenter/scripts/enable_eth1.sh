#!/bin/bash

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
