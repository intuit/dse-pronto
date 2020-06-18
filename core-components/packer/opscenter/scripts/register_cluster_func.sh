#!/bin/bash
set -x

function register_with_opscenter()
{
  bucket=${1}
  cluster=${2}
  vpc_name=${3}
  account_name=${4}

  account_vpc="${account_name}/${vpc_name}"

  ops_cluster_name=$(echo ${cluster} | sed "s/-/_/g" | sed "s/\./_/g")
  mkdir -p /etc/opscenter/keystores/${ops_cluster_name}/
  mkdir -p /etc/opscenter/clusters

  # check whether this cluster is already registered (cluster file in s3)
  aws s3 ls s3://${bucket}/${account_vpc}/opscenter-resources/files/etc/clusters/${ops_cluster_name}.conf
  if [[ $? -eq 0 ]]; then
    echo "cluster '${cluster}' is already registered with opscenter"
    sudo chmod 644 /etc/opscenter/keystores/${ops_cluster_name}/*
    return 0
  else
    echo "registering cluster '${cluster}' with opscenter"
    rm -fr /tmp/*.jks
    rm -fr /tmp/target-*
    rm -fr /tmp/storage-*

    # determine storage cluster (fetch from parameter store)
    storage_cluster=$(aws ssm get-parameters --names "/dse/${account_vpc}/opscenter-resources/opscenter_storage_cluster" \
                  --query Parameters[0].Value --output text \
                  --region ${region})

    echo "storage_cluster is ${storage_cluster}"

    target_cluster_seeds=$(aws ssm get-parameters --names "/dse/${account_vpc}/${cluster}/cassandra_seed_node_ips" \
                  --query Parameters[0].Value --output text \
                  --region ${region})

    first_target_seed=$(echo ${target_cluster_seeds} | cut -d, -f 1)

    # path to cluster files on s3
    artifact_path="${account_vpc}/${cluster}/files"

    # get target cassandra password
    ssm_secrets_path="/dse/${account_vpc}/${cluster}/secrets"
    target_cassandra_pass=$(aws ssm get-parameter --region ${region} --name "${ssm_secrets_path}/cassandra_pass" --with-decryption | jq -r '.[].Value' | base64 -d)
    target_cassandra_key_pass=$(aws ssm get-parameter --region ${region} --name "${ssm_secrets_path}/keystore_pass" --with-decryption | jq -r '.[].Value' | base64 -d)
    target_cassandra_trust_pass=$(aws ssm get-parameter --region ${region} --name "${ssm_secrets_path}/truststore_pass" --with-decryption | jq -r '.[].Value' | base64 -d)

    # get truststore, keystore
    aws s3 cp "s3://${bucket}/${artifact_path}/keystores/server-truststore.jks" /tmp/target-server-truststore.jks --region ${region}
    aws s3 cp "s3://${bucket}/${artifact_path}/keystores/${first_target_seed}-server-keystore.jks" /tmp/target-server-keystore.jks --region ${region}

    # cleanup
    rm -f /tmp/target-cassandra.secrets

    # fetch storage cluster vars from parameter store
    storage_cluster_seeds=$(aws ssm get-parameters --names "/dse/${account_vpc}/${storage_cluster}/cassandra_seed_node_ips" \
                  --query Parameters[0].Value --output text \
                  --region ${region})

    first_storage_seed=$(echo ${storage_cluster_seeds} | cut -d, -f 1)

    # path to storage_cluster files on s3
    artifact_path="${account_vpc}/${storage_cluster}/files"

    # get secrets from s3
    storage_cassandra_secrets_path="/dse/${account_vpc}/${cluster}/secrets"
    storage_cassandra_pass=$(aws ssm get-parameter --region ${region} --name "${storage_cassandra_secrets_path}/cassandra_pass" --with-decryption | jq -r '.[].Value' | base64 -d)
    storage_key_pass=$(aws ssm get-parameter --region ${region} --name "${storage_cassandra_secrets_path}/keystore_pass" --with-decryption | jq -r '.[].Value' | base64 -d)
    storage_trust_pass=$(aws ssm get-parameter --region ${region} --name "${storage_cassandra_secrets_path}/truststore_pass" --with-decryption | jq -r '.[].Value' | base64 -d)
    aws s3 cp "s3://${bucket}/${artifact_path}/keystores/server-truststore.jks" /tmp/storage-server-truststore.jks --region ${region}
    aws s3 cp "s3://${bucket}/${artifact_path}/keystores/${first_storage_seed}-server-keystore.jks" /tmp/storage-server-keystore.jks --region ${region}
    rm -f /tmp/storage-cassandra.secrets
    mv /tmp/storage*.jks /etc/opscenter/keystores/

    # build config (from template) for dse cluster
    cluster_conf="/tmp/${ops_cluster_name}.conf"
    cp /etc/opscenter/scripts/cluster_conf.templ ${cluster_conf}
    sed -i -r "s/##CLUSTER##/${ops_cluster_name}/g" ${cluster_conf}
    sed -i -r "s/##STORAGE_SEEDS##/${storage_cluster_seeds}/g" ${cluster_conf}
    sed -i -r "s/##STORAGE_PASS##/${storage_cassandra_pass}/g" ${cluster_conf}
    sed -i -r "s/##STORAGE_KEYPASS##/${storage_key_pass}/g" ${cluster_conf}
    sed -i -r "s/##STORAGE_TRUSTPASS##/${storage_trust_pass}/g" ${cluster_conf}
    sed -i -r "s:##STORAGE_KEYSTORE##:/etc/opscenter/keystores/storage-server-keystore.jks:g" ${cluster_conf}
    sed -i -r "s:##STORAGE_TRUSTSTORE##:/etc/opscenter/keystores/storage-server-truststore.jks:g" ${cluster_conf}

    sed -i -r "s/##CAS_CLUSTER_SEEDS##/${target_cluster_seeds}/g" ${cluster_conf}
    sed -i -r "s/##CAS_CLUSTER_PASS##/${target_cassandra_pass}/g" ${cluster_conf}
    sed -i -r "s/##CAS_CLUSTER_KEYPASS##/${target_cassandra_key_pass}/g" ${cluster_conf}
    sed -i -r "s/##CAS_CLUSTER_TRUSTPASS##/${target_cassandra_trust_pass}/g" ${cluster_conf}
    sed -i -r "s:##CAS_CLUSTER_KEYSTORE##:/etc/opscenter/keystores/${ops_cluster_name}/target-server-keystore.jks:g" ${cluster_conf}
    sed -i -r "s:##CAS_CLUSTER_TRUSTSTORE##:/etc/opscenter/keystores/${ops_cluster_name}/target-server-truststore.jks:g" ${cluster_conf}

    mv /tmp/*.jks /etc/opscenter/keystores/${ops_cluster_name}/
    sudo chown -R opscenter:opscenter /etc/opscenter/keystores/
    sudo chmod 644 /etc/opscenter/keystores/${ops_cluster_name}/*
    
    cp ${cluster_conf} /etc/opscenter/clusters

    # upload the config to S3 so that we can download it during the init
    aws s3 cp ${cluster_conf} "s3://${bucket}/${account_vpc}/opscenter-resources/files/etc/clusters/${ops_cluster_name}.conf" --region ${region}
    aws s3 sync /etc/opscenter/keystores/ s3://${bucket}/${account_vpc}/opscenter-resources/files/etc/keystores/ --region ${region}
    sudo chown -R opscenter:opscenter /etc/opscenter/clusters
    sudo chmod 644 /etc/opscenter/keystores/${ops_cluster_name}/*

    # restart opscenterd
    sudo service opscenterd restart
  fi
}
