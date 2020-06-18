#!/bin/bash
source ./register_cluster_func.sh

bucket=$1
vpc_name=$2
account_name=$3

region=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')

storage_cluster=$(aws ssm get-parameters --names "/dse/${account_name}/${vpc_name}/opscenter-resources/opscenter_storage_cluster" \
                  --query Parameters[0].Value --output text \
                  --region ${region})

function sync_configs_from_s3() {
  s3_file_path="${account_name}/${vpc_name}/opscenter-resources/files"
  aws s3 ls s3://${bucket}/${s3_file_path}/etc/opscenterd.conf
  file_exists=$?

  if [[ ${file_exists} -eq 0 ]]; then
    echo "opscenterd.conf exists in s3"
  else
    echo "opscenterd.conf does not exists in s3"
    if test -f "/etc/opscenter/opscenterd.conf"; then
      # enable authentication
      sed -i -r "s/enabled = False/enabled = True/g" /etc/opscenter/opscenterd.conf
      # write the modified opscenterd.conf to s3
      aws s3 cp /etc/opscenter/opscenterd.conf s3://${bucket}/${s3_file_path}/etc/opscenterd.conf
    fi
  fi

  echo ${storage_cluster}
  register_with_opscenter ${bucket} ${storage_cluster} ${vpc_name} ${account_name}

  # sync /etc/opscenter from s3
  aws s3 sync "s3://${bucket}/${s3_file_path}/etc/" /etc/opscenter/ --region ${region}

  # sync varlib from s3
  aws s3 sync "s3://${bucket}/${s3_file_path}/varlib/" /var/lib/opscenter/ --region ${region}
  chown -R opscenter:opscenter /etc/opscenter
}

function update_limits() {
  echo "opscenter        hard    nofile          500000" >> /etc/security/limits.conf
  echo "opscenter        soft    nofile          500000" >> /etc/security/limits.conf
}

function attach_network()
{
  echo "FUNC: attach_network"
  echo "USER: `whoami`"
  echo "CWD: $PWD"
  PRIVATE_IP=$(curl -L 169.254.169.254/latest/meta-data/local-ipv4)
  REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')
  ./ops_eni_mgr.py -r ${REGION}  -o attach -n ${PRIVATE_IP}
  sudo ./enable_eth1.sh
  PRIVATE_IP=$(ifconfig eth1 | grep -w "inet" | awk '{print $2}')
  echo "New ip: ${PRIVATE_IP}"
}

attach_network
sync_configs_from_s3
update_limits
sudo service opscenterd restart