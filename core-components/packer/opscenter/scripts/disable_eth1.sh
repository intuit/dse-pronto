#!/bin/bash

cd /etc/sysconfig/network-scripts
if [[ -e /etc/sysconfig/network-scripts/ifcfg-eth1 ]]; then
  sed -i 's/ONBOOT=no/ONBOOT=yes/g' ifcfg-eth0

  /sbin/ifup eth0
  sleep 10
  /sbin/ifdown eth1
  sleep 10

  my_eni_ip=$(ifconfig -a eth0 | grep -w inet | awk '{print $2}' | sed 's,/.*$,,' | sed 's/\./-/g')
  my_eni_hostname=ip-${my_eni_ip}.us-west-2.compute.internal
  hostnamectl set-hostname ${my_eni_hostname}
  echo "preserve_hostname: true" >> /etc/cloud/cloud.cfg
  rm ifcfg-eth1
fi
