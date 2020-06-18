#!/usr/bin/env bash

function make_tuning_changes() {
  # k1 - change the read_ahead_kb for the ssd drives
  lsblk | awk '$6 == "disk" {print "/sys/class/block/"$1"/queue/read_ahead_kb"}' | xargs -I {} -n 1 sh -c 'echo 8 >  {}'
  # k2
  lsblk | awk '$6 == "disk" {print "/sys/block/"$1"/queue/nomerges"}' | xargs -I {} -n 1 sh -c 'echo 1 >  {}'
  # k3
  echo never > /sys/kernel/mm/transparent_hugepage/defrag
  # k5
  sysctl -w net.core.rmem_max=16777216 net.core.wmem_max=16777216 net.core.rmem_default=16777216 net.core.wmem_default=16777216 net.core.optmem_max=40960 net.ipv4.tcp_rmem="4096 87380 16777216" net.ipv4.tcp_wmem="4096 87380 16777216"
}

make_tuning_changes
