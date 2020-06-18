#!/bin/bash
set -e

# This script mounts the primary and secondary-data for the cassandra_seed_node_ips

VOL_SIZE=$1
STRIPES=$2
BLOCK_SIZE=$3
RAID_LEVEL=$4

sudo mkdir -p /mnt/{cassandra-data-primary,cassandra-data-secondary}

function check_device_names()
{
  # the "nitro" hypervisor uses the NVMe specification, remaps "xvd" device names to "nvme"
  if ls -l /dev/xvda | grep -q nvme; then
    ROOT_DEVICE="nvme0n1"
    SECONDARY_DEVICE="nvme1n1"
    PRIMARY_DEVICE="nvme2n1"
  else
    ROOT_DEVICE="xvda"
    SECONDARY_DEVICE="xvdb"
    PRIMARY_DEVICE="xvdc"
  fi
}

function mount_secondary()
{
  # Mount the secondary-data
  v=$(df | grep "/mnt/cassandra-data-secondary" | awk '{print $1}')
  if [[ -z ${v//} ]]; then
    disk="/dev/${SECONDARY_DEVICE}"
    fs_type=$(blkid ${disk} | awk '{print $3}' | awk -F '=' '{print $2}')
    if [[ -z ${fs_type//} ]]; then
      sudo mkfs -t ext4 ${disk}
    fi
    sudo mount ${disk} /mnt/cassandra-data-secondary
    sudo mkdir -p /mnt/cassandra-data-secondary/{commitlog,saved_caches,hints,cdc_raw}
    sudo echo "${disk} /mnt/cassandra-data-secondary ext4 rw,auto 0 0" >> /etc/fstab
    sudo chown -R cassandra:cassandra /mnt/cassandra-data-secondary
  fi
}

function mount_primary()
{
  # Mount the primary-data
  v=$(df | grep "/mnt/cassandra-data-primary" | awk '{print $1}')
  if [[ -z ${v//} ]]; then
    if [[ ${RAID_LEVEL} = -1 ]]; then
      # mounting a single volume
      disk="/dev/${PRIMARY_DEVICE}"
      fs_type=$(blkid ${disk} | awk '{print $3}' | awk -F '=' '{print $2}')
      if [[ -z ${fs_type//} ]]; then
        sudo mkfs -t ext4 ${disk}
      fi
      sudo mount ${disk} /mnt/cassandra-data-primary
    else
      # try to do pvimport if there is data in pvscan
      lvm_devices=$(pvscan | grep cas-data-vg | wc -l)

      # There could be 2 or more disks
      if [[ ${lvm_devices} -gt 1 ]]; then
        # re-import volume group to avoid "unable to export cas-data-vg"
        vgchange -an cas-data-vg
        vgexport cas-data-vg
        vgimport cas-data-vg
        vgchange -ay cas-data-vg
      fi

      fs_type=$(blkid /dev/cas-data-vg/cas-data | awk ' { print $3 }' | awk -F '=' '{print $2}')
      if [[ -z ${fs_type//} ]]; then
        lsblk | awk -v rootdev="${ROOT_DEVICE}" '$7 == "" && $6 == "disk" && $1 != rootdev {print "/dev/"$1}' | xargs pvcreate
        lsblk | awk -v rootdev="${ROOT_DEVICE}" '$7 == "" && $6 == "disk" && $1 != rootdev {print "/dev/"$1}' | xargs vgcreate cas-data-vg
        lvcreate --name cas-data --type raid0 -i ${STRIPES} -I ${BLOCK_SIZE} --size ${VOL_SIZE}GB cas-data-vg
        # Make volume group inactive
        vgchange -an cas-data-vg
        # Write the volume group info
        vgexport cas-data-vg
        # Import it back again (redundant but does not hurt)
        vgimport cas-data-vg
        # Make volumegroup active
        vgchange -ay cas-data-vg
        # format filesystem
        mkfs.ext4 /dev/cas-data-vg/cas-data
      fi
      mount /dev/cas-data-vg/cas-data /mnt/cassandra-data-primary
    fi
    sudo chown -R cassandra:cassandra /mnt/cassandra-data-primary
    sudo echo "/dev/cas-data-vg/cas-data /mnt/cassandra-data-primary ext4 rw,auto 0 0" >> /etc/fstab
  fi
}

check_device_names
mount_secondary
mount_primary
