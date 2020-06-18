#!/bin/bash
set -xe

AUTO_START_DSE=${1}
PRIVATE_IP=$(curl -L 169.254.169.254/latest/meta-data/local-ipv4)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')

function parse_ssm_param()
{
  echo "${1}" | jq -r '."'${2}'"'
}

function get_inputs()
{
  account=$(./cas_get_tag_values.py -r ${REGION} -n ${PRIVATE_IP} -t Account)
  tfstate=$(./cas_get_tag_values.py -r ${REGION} -n ${PRIVATE_IP} -t Tfstate)
  cluster=$(./cas_get_tag_values.py -r ${REGION} -n ${PRIVATE_IP} -t ClusterName)
  vpc_name=$(./cas_get_tag_values.py -r ${REGION} -n ${PRIVATE_IP} -t VpcName)
  account_name=$(./cas_get_tag_values.py -r ${REGION} -n ${PRIVATE_IP} -t AccountName)
  node_name=$(./cas_get_tag_values.py -r ${REGION} -n ${PRIVATE_IP} -t Name)

  # variables to fetch from ssm parameter store (max 10)
  param_key_prefix="/dse/${account_name}/${vpc_name}/${cluster}"
  declare -a param_keys=(
      "${param_key_prefix}/commitlog_size"
      "${param_key_prefix}/commitlog_volume_type"
      "${param_key_prefix}/commitlog_iops"
      "${param_key_prefix}/iops"
      "${param_key_prefix}/data_volume_size"
      "${param_key_prefix}/volume_type"
      "${param_key_prefix}/number_of_stripes"
      "${param_key_prefix}/raid_level"
      "${param_key_prefix}/raid_block_size"
      "${param_key_prefix}/cassandra_seed_node_ips"
      "${param_key_prefix}/max_heap_size"
      "${param_key_prefix}/num_tokens"
      "${param_key_prefix}/aio_enabled"
      "${param_key_prefix}/max_queued_native_transport_requests"
      "${param_key_prefix}/native_transport_max_threads"
  )

  # get them all at once, convert to key:value map
  param_values=$(aws ssm get-parameters-by-path --path "${param_key_prefix}/" --recursive --output json --region ${REGION} | jq '.Parameters|map({(.Name):.Value})|add')

  # parse results
  set +x
  commitlog_size=$(                       parse_ssm_param "${param_values}" "${param_key_prefix}/commitlog_size")
  commitlog_volume_type=$(                parse_ssm_param "${param_values}" "${param_key_prefix}/commitlog_volume_type")
  commitlog_iops=$(                       parse_ssm_param "${param_values}" "${param_key_prefix}/commitlog_iops")
  iops=$(                                 parse_ssm_param "${param_values}" "${param_key_prefix}/iops")
  data_volume_size=$(                     parse_ssm_param "${param_values}" "${param_key_prefix}/data_volume_size")
  volume_type=$(                          parse_ssm_param "${param_values}" "${param_key_prefix}/volume_type")
  number_of_stripes=$(                    parse_ssm_param "${param_values}" "${param_key_prefix}/number_of_stripes")
  raid_level=$(                           parse_ssm_param "${param_values}" "${param_key_prefix}/raid_level")
  raid_block_size=$(                      parse_ssm_param "${param_values}" "${param_key_prefix}/raid_block_size")
  seeds=$(                                parse_ssm_param "${param_values}" "${param_key_prefix}/cassandra_seed_node_ips")
  max_heap_size=$(                        parse_ssm_param "${param_values}" "${param_key_prefix}/max_heap_size")
  num_tokens=$(                           parse_ssm_param "${param_values}" "${param_key_prefix}/num_tokens")
  aio_enabled=$(                          parse_ssm_param "${param_values}" "${param_key_prefix}/aio_enabled")
  max_queued_native_transport_requests=$( parse_ssm_param "${param_values}" "${param_key_prefix}/max_queued_native_transport_requests")
  native_transport_max_threads=$(         parse_ssm_param "${param_values}" "${param_key_prefix}/native_transport_max_threads")
  set -x

  # set default value if not set
  if [[ ${commitlog_iops} == "null" ]]; then
    commitlog_iops=${iops}
  fi

  # secrets are stored in parameter store
  artifact_path="${account_name}/${vpc_name}/${cluster}/files"
  secrets_path="/dse/${account_name}/${vpc_name}/${cluster}/secrets"
  keystore_pass=$(aws --region ${REGION} ssm get-parameter --with-decryption --name "${secrets_path}/keystore_pass" | jq -r '.[].Value' | base64 -d)
  truststore_pass=$(aws --region ${REGION} ssm get-parameter --with-decryption --name "${secrets_path}/truststore_pass" | jq -r '.[].Value' | base64 -d)
}

function attach_network()
{
  echo "FUNC: attach_network"
  echo "USER: `whoami`"
  echo "CWD: $PWD"

  ./cas_eni_mgr.py -r ${REGION} -a ${account} -c ${cluster} -o attach -n ${PRIVATE_IP}
  sudo ./enable_eth1.sh
  PRIVATE_IP=`ifconfig eth1 | grep -w "inet" | awk '{print $2}'`
}

function attach_storage()
{
  echo "FUNC: attach_storage"
  echo "USER: `whoami`"
  echo "CWD: $PWD"
  # Note: if attach_network is called first, "eth1" should be the active_interface (-f option) for cas_ebs_mgr

  # attach block_devices for secondary-data (commit_logs, saved_caches)
  ./cas_ebs_mgr.py -r ${REGION} -a ${account} -c ${cluster} -o attach -l ${PRIVATE_IP} \
      -n 1 -t ${commitlog_volume_type} -s ${commitlog_size} -x "data_type:secondary-data" -i ${commitlog_iops} -f eth1

  # attach block_devices for primary-data
  ./cas_ebs_mgr.py -r ${REGION} -a ${account} -c ${cluster} -o attach -l ${PRIVATE_IP} \
      -n ${number_of_stripes} -t ${volume_type} -s ${data_volume_size} -x "data_type:primary-data" -i ${iops} -f eth1

  echo "mount storage"
  capacity=$(expr ${data_volume_size} \* ${number_of_stripes})
  capacity=$(expr ${capacity} \* 95 / 100)
  sudo ./create_volume.sh ${capacity} ${number_of_stripes} ${raid_block_size} ${raid_level}
}

function setup_keys()
{
  echo "FUNC: setup_keys"
  echo "USER: `whoami`"
  echo "CWD: $PWD"
  if [[ ${AUTO_START_DSE} = 1 ]]; then
    sudo ./gen_server_keystores.sh ${tfstate} ${artifact_path} ${account_name} ${vpc_name} ${cluster} ${REGION} 
  fi
}

function update_cassandra_config()
{
  echo "FUNC: update_cassandra_config"
  echo "USER: `whoami`"
  echo "CWD: $PWD"

  ############################
  # opscenter related configs
  ############################

  set +e
  opscenter_ip=$(aws ssm get-parameters --region ${REGION} --names "/dse/${account_name}/${vpc_name}/opscenter-resources/opscenter_primary_private_ip" \
                --query Parameters[0].Value --output text)
  if [[ ${opscenter_ip} ]]; then
    sudo sed -i "s/[# ]*stomp_interface:.*/stomp_interface: ${opscenter_ip}/" /var/lib/datastax-agent/conf/address.yaml
  fi

  aws s3 ls s3://${tfstate}/${account_name}/${vpc_name}/opscenter-resources/files/etc/keystores/storage-server-keystore.jks >/dev/null
  if [[ $? -eq 0 ]]; then
    aws s3 cp s3://${tfstate}/${account_name}/${vpc_name}/opscenter-resources/files/etc/keystores/storage-server-keystore.jks /etc/dse/cassandra/keystores/storage-server-keystore.jks
    chmod 755 /etc/dse/cassandra/keystores/storage-server-keystore.jks
    chown cassandra:cassandra /etc/dse/cassandra/keystores/storage-server-keystore.jks
  fi
  set -e

  sudo sed -i "s/# use_ssl: .*/use_ssl: 0/" /var/lib/datastax-agent/conf/address.yaml

  ############################
  # cassandra configs
  # NOTE: will sed the entire line regardless of expected ##TOKEN## - in case
  # someone brings in a clean config file with no tokens present.
  ############################

  file="/etc/dse/cassandra/cassandra.yaml"

  sudo sed -i -r "s/seeds:.*/seeds: \"${seeds}\"/g" ${file}
  sudo sed -i -r "s/cluster_name:.*/cluster_name: \"${cluster}\"/g" ${file}

  sudo sed -i -r "s/^listen_address:.*/listen_address: ${PRIVATE_IP}/g" ${file}
  sudo sed -i -r "s/^native_transport_address:.*/native_transport_address: ${PRIVATE_IP}/g" ${file}
  sudo sed -i -r "s/^rpc_address:.*/rpc_address: ${PRIVATE_IP}/g" ${file}
  sudo sed -i -r "s/^broadcast_rpc_address:.*/broadcast_rpc_address: ${PRIVATE_IP}/g" ${file}

  # replace keystore_password & truststore_password in "server_encryption_options" section (section must end with empty line)
  sudo sed -i -r "/server_encryption_options/,/^$/ s/keystore_password:.*/keystore_password: ${keystore_pass}/" ${file}
  sudo sed -i -r "/server_encryption_options/,/^$/ s/truststore_password:.*/truststore_password: ${truststore_pass}/" ${file}

  # replace keystore_password & truststore_password in "client_encryption_options" section (section must end with empty line)
  sudo sed -i -r "/client_encryption_options/,/^$/ s/keystore_password:.*/keystore_password: ${keystore_pass}/" ${file}
  sudo sed -i -r "/client_encryption_options/,/^$/ s/truststore_password:.*/truststore_password: ${truststore_pass}/" ${file}

  if [[ ! -z "${num_tokens// }" ]]; then
    sed -i -e "s/^num_tokens:.*/num_tokens: ${num_tokens}/" ${file}
  fi

  file="/etc/dse/cassandra/cassandra-env.sh"

  sudo sed -i -r "s/java.rmi.server.hostname=.*\"/java.rmi.server.hostname=${PRIVATE_IP}\"/g" ${file}
  sudo sed -i -r "s/javax.net.ssl.keyStorePassword=.*\"/javax.net.ssl.keyStorePassword=${keystore_pass}\"/g" ${file}
  sudo sed -i -r "s/javax.net.ssl.trustStorePassword=.*\"/javax.net.ssl.trustStorePassword=${truststore_pass}\"/g" ${file}

  sudo chown cassandra:cassandra /etc/dse/cassandra/cassandra*
  sudo chmod a+r /etc/dse/cassandra/cassandra*

  if [[ -z ${max_heap_size} ]]; then
    sed -i -r "s/MAX_HEAP_SIZE=.*/MAX_HEAP_SIZE=\"14G\"/g" ${file}
  else
    sed -i -r "s/MAX_HEAP_SIZE=.*/MAX_HEAP_SIZE=\"${max_heap_size}G\"/g" ${file}
  fi

  #############
  # Gremlin Console Settings
  #############

  sudo sed -i "s/##PRIVATE_IP##/${PRIVATE_IP}/" /etc/dse/graph/gremlin-console/conf/*.yaml

  #############
  ## reasonable block device settings for SSD (post-mount)
  #############

  for dev in $(ls /sys/block); do
    echo 4 > /sys/block/${dev}/queue/read_ahead_kb
    echo 1 > /sys/block/${dev}/queue/nomerges
    #echo deadline > /sys/block/${dev}/queue/scheduler
  done
}

function gc_changes()
{
  cd /etc/dse/cassandra
  echo "FUNC: gc_changes"
  echo "USER: `whoami`"
  echo "CWD: $PWD"

  jvm_opts_location="/tmp/jvm.options"
  aws s3 cp s3://${tfstate}/${account_name}/${vpc_name}/${cluster}/files/cluster-configs/jvm.options ${jvm_opts_location}
  echo "" >>  ${jvm_opts_location}

  egrep -q "(^|\s)-Ddse.io.aio.enabled" ${jvm_opts_location}
  aio_enabled_op=$?
  egrep -q "(^|\s)-Ddse.read_ahead_size_kb" ${jvm_opts_location}
  read_ahead_op=$?
  if [[ "${aio_enabled}" = "false" ]]; then	
    if [[ "${aio_enabled_op}" -ne 0 ]]; then
      echo "-Ddse.io.aio.enabled=false" >> ./jvm.options
    fi
    if [[ "${read_ahead_op}" -ne 0 ]]; then
      echo "-Ddse.read_ahead_size_kb=0" >> ./jvm.options
    fi
  fi

  if [[ "${native_transport_max_threads}" -gt 0 ]]; then
    echo "-Dcassandra.native_transport_max_threads=${native_transport_max_threads}" >> ./jvm.options
  fi

  egrep -q "(^|\s)-Xmx" ${jvm_opts_location}
  max_heap_size_op="-Xmx"
  egrep -q "(^|\s)-Xms" ${jvm_opts_location}
  initial_heap_size_op="-Xms"
  if [[ "${max_heap_size_op}" -ne 0 ]]; then
    echo "-Xmx${max_heap_size}G" >> ${jvm_opts_location}
  fi
  if [[ "${initial_heap_size_op}" -ne 0 ]]; then
    echo "-Xms${max_heap_size}G" >> ${jvm_opts_location}
  fi

  cp ${jvm_opts_location} /etc/dse/cassandra/jvm.options
  chmod 755 /etc/dse/cassandra/jvm.options
}

function start_services()
{
  echo "FUNC: start_services"
  echo "USER: `whoami`"
  echo "CWD: $PWD"

  sudo echo 'JVM_OPTS="$JVM_OPTS -Xmx2096M"' > /etc/datastax-agent/datastax-agent-env.sh
  sudo service datastax-agent start
  cas_vols_mounted=$(df -h | grep -i /mnt/cassandra | wc -l)
  if [[ ${cas_vols_mounted} = 2 ]]; then
    if [[ ${AUTO_START_DSE} = 1 ]]; then
      sudo service dse start
    fi

    # Wait for 10 min for DSE to start
    i=0
    while true; do
      # 7001 = ssl_storage_port in cassandra.yaml
      if lsof -Pi :7001 -sTCP:LISTEN -t >/dev/null; then
        echo "running"
        break
      else
        sleep 10
        i=$((i+1))
        echo "not running ($i)"
        if [[ (( ${i} -gt 60 )) ]]; then
          echo "ERROR: Unable to start DSE"
          break
        fi
      fi
    done
  else
    echo "ERROR: Unable to mount data and commitlog volumes"
  fi
}

function exec_external_scripts()
{
  # NOTE: additional .sh files can be placed in your configuration profile, under the "post-deploy-scripts" dir
  mkdir -p /tmp/cas-scripts/

  aws s3 cp s3://${tfstate}/${artifact_path}/post-deploy-scripts /tmp/cas-scripts/ --recursive --exclude "*" --include "*.sh" || true
  chmod +x /tmp/cas-scripts/*.sh
  cd /tmp/cas-scripts/

  for entry in /tmp/cas-scripts/*.sh; do
    echo "Executing $entry"
    bash ${entry} || true
  done
}

cd $(dirname "${BASH_SOURCE[0]}")
get_inputs
attach_network
attach_storage
setup_keys
update_cassandra_config
exec_external_scripts

set +e
gc_changes
start_services
