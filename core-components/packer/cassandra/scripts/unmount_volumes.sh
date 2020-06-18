#!/bin/bash

# This script unmounts the primary and secondary-data

v=$(df | grep "/mnt/cassandra-data-secondary" | awk '{print $1}')
if [[ ! -z ${v//} ]]; then
  sudo umount /mnt/cassandra-data-secondary
fi

v=$(df | grep "/mnt/cassandra-data-primary" | awk '{print $1}')
if [[ ! -z ${v//} ]]; then
  sudo umount /mnt/cassandra-data-primary

  lvm_devices=$(sudo pvscan | grep cas-data-vg | wc -l)

  if [[ ${lvm_devices} -gt 1 ]]; then
      # Marking the volume group inactive removes it from the kernel and prevents any
      # further activity on it.
      sudo vgchange -an cas-data-vg

      # We export the layout during attach but doing it again to make sure that no more
      # disks are added export the volume group. This prevents it from being accessed on
      # the "old" host system and prepares it to be removed.
      sudo vgexport cas-data-vg
  fi
fi
