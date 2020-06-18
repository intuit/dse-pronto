#!/bin/bash

#./ssl-keys/gen_ca_cert_from_config.sh
set -e
set -x

BUCKET=$1
KEY=$2
ACCOUNT_NAME=$3
VPC_NAME=$4
CLUSTER_NAME=$5
REGION=$6

region=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')

# Download secrets file
ssm_secrets_path="/dse/${ACCOUNT_NAME}/${VPC_NAME}/${CLUSTER_NAME}/secrets"

keystore_pass=$(aws --region ${REGION} ssm get-parameter --with-decryption --name "${ssm_secrets_path}/keystore_pass" | jq -r '.[].Value' | base64 -d)
truststore_pass=$(aws --region ${REGION} ssm get-parameter --with-decryption --name "${ssm_secrets_path}/truststore_pass" | jq -r '.[].Value' | base64 -d)
cert_output_pwd=$(aws --region ${REGION} ssm get-parameter --with-decryption --name "${ssm_secrets_path}/keystore_pass" | jq -r '.[].Value' | base64 -d)
set +e
host_key_pwd=$(aws --region ${REGION} ssm get-parameter --with-decryption --name "${ssm_secrets_path}/host_key_pwd" | jq -r '.[].Value' | base64 -d)
set -e

if [[ "${host_key_pwd}" = "" ]]; then
  host_key_pwd=${cert_output_pwd}
fi



# Download ca-cert and ca-key from S3 if exists
mkdir -p ./{certs,keystores}
mkdir -p /etc/dse/cassandra/{keystores,keys}
rm -fr ./certs/*
rm -fr ./keystores/*
rm -fr /etc/dse/cassandra/keystores/*
rm -fr /etc/dse/cassandra/certs/*

host=`ifconfig eth1 | grep -w "inet" | awk '{print $2}'`

######################
# use lock file on s3 to coordinate key generation between nodes
######################

# TODO: move this to EFS? or try s3 file lock if appropriate?

# check if any node in the cluster has obtained a lock
wait_marker="lock.txt"
while [[ "$(aws s3 ls s3://${BUCKET}/${KEY}/ --recursive --region ${region} | grep -c ${wait_marker})" -gt 0 ]]; do
  echo "Found a lock file in s3://${BUCKET}/${KEY} -- sleeping 5 seconds..."
  sleep 5
done

while true; do
  # look for ca-key
  key_count=$(aws s3 ls s3://${BUCKET}/${KEY}/certs/ca-key --region ${region} | wc -l)

  # if no key found, obtain a lock before generating one
  if [[ ${key_count} -eq 0 ]]; then
    echo "No ca-key found at s3://${BUCKET}/${KEY}/certs/ca-key -- attempting to write a lock..."

    touch empty
    aws s3 cp empty s3://${BUCKET}/${KEY}/lock/${host}-${wait_marker} --region ${region}
    rm -f empty

    # check if we have an exclusive lock
    if [[ "$(aws s3 ls s3://${BUCKET}/${KEY}/ --recursive --region ${region} | grep -c ${wait_marker})" -ne 1 ]]; then
      # should be exactly 1 lock, delete and try again after random sleep
      echo "Lock failed, starting over..."
      aws s3 rm s3://${BUCKET}/${KEY}/lock/${host}-${wait_marker} --region ${region}
      set -x
      sleep $(($RANDOM%60))
      set +x
    else
      # lock is ours
      echo "Lock obtained, generating common key materials now!"
      break
    fi
  else
    # there's already a ca-key on s3
    break
  fi
done

######################
# generate or obtain shared ca-key, ca-cert, server-truststore
######################

if [[ ${key_count} -gt 0 ]]; then
  # ca-key, ca-cert, server truststore already exist in s3, copy to disk
  aws s3 cp s3://${BUCKET}/${KEY}/certs/ca-key ./certs/ca-key --region ${region}
  aws s3 cp s3://${BUCKET}/${KEY}/certs/ca-cert ./certs/ca-cert --region ${region}
  aws s3 cp s3://${BUCKET}/${KEY}/keystores/server-truststore.jks ./keystores/server-truststore.jks  --region ${region}
else
  # generate new ca-cert and ca-key
  cp ./gen_ca_cert.conf ./gen_ca_cert.conf.bk
  sed -i -r "s/##CERT_OUPUT_PWD##/${cert_output_pwd}/g" ./gen_ca_cert.conf.bk

  # generate new server truststore
  openssl req -config ./gen_ca_cert.conf.bk -new -x509 -keyout ./certs/ca-key -out ./certs/ca-cert -days 1095
  keytool -keystore ./keystores/server-truststore.jks -alias CARoot -importcert -file ./certs/ca-cert -keypass ${cert_output_pwd} -storepass ${truststore_pass} -noprompt

  # upload the ca-cert, ca-key
  aws s3 cp ./certs/ca-key s3://${BUCKET}/${KEY}/certs/ca-key --region ${region}
  aws s3 cp ./certs/ca-cert s3://${BUCKET}/${KEY}/certs/ca-cert --region ${region}

  # upload the server-truststore
  aws s3 cp ./keystores/server-truststore.jks s3://${BUCKET}/${KEY}/keystores/server-truststore.jks  --region ${region}
fi

# remove lock file, if exists
aws s3 rm s3://${BUCKET}/${KEY}/lock/${host}-${wait_marker} --region ${region}

######################
# server-keystore
######################

host_key_count=$(aws s3 ls s3://${BUCKET}/${KEY}/keystores/${host}-server-keystore.jks --region ${region} | wc -l)

if [[ ${host_key_count} -gt 0 ]]; then
  # server-keystore (for this node) already exists in s3, copy to disk
  aws s3 cp s3://${BUCKET}/${KEY}/keystores/${host}-server-keystore.jks ./keystores/ --region ${region}
  aws s3 cp s3://${BUCKET}/${KEY}/certs/${host}_cert_sr ./certs/ --region ${region}
  aws s3 cp s3://${BUCKET}/${KEY}/certs/${host}_cert_signed ./certs/ --region ${region}
else
  # generate new server-keystore
  keytool -genkeypair -keyalg RSA -alias ${host} -keystore keystores/${host}-server-keystore.jks -storepass ${keystore_pass} -keypass ${keystore_pass} -validity 1095 -keysize 2048 -dname "CN=${host}, OU=QDC, O=TLP, C=US"
  keytool -keystore keystores/${host}-server-keystore.jks -alias ${host} -certreq -file certs/"${host}"_cert_sr -keypass ${keystore_pass} -storepass ${keystore_pass}
  openssl x509 -req -CA certs/ca-cert -CAkey certs/ca-key -in certs/"${host}"_cert_sr -out certs/"${host}"_cert_signed -days 1095 -CAcreateserial -passin pass:${host_key_pwd}
  keytool -keystore keystores/${host}-server-keystore.jks -alias CARoot -import -file certs/ca-cert -noprompt -keypass ${keystore_pass} -storepass ${keystore_pass}
  keytool -keystore keystores/${host}-server-keystore.jks -alias ${host} -import -file certs/"${host}"_cert_signed -keypass ${keystore_pass} -storepass ${keystore_pass}

  # upload to s3
  aws s3 cp ./keystores/${host}-server-keystore.jks s3://${BUCKET}/${KEY}/keystores/${host}-server-keystore.jks --region ${region}
  aws s3 cp ./certs/${host}_cert_sr s3://${BUCKET}/${KEY}/certs/${host}_cert_sr --region ${region}
  aws s3 cp ./certs/${host}_cert_signed s3://${BUCKET}/${KEY}/certs/${host}_cert_signed --region ${region}
fi

# copy the files
sudo cp ./keystores/${host}-server-keystore.jks /etc/dse/cassandra/keystores/server-keystore.jks
sudo cp ./keystores/server-truststore.jks /etc/dse/cassandra/keystores/server-truststore.jks

# prepare keystores
sudo chown cassandra:cassandra -R /etc/dse/cassandra/keystores/
sudo cp ./certs/* /etc/dse/cassandra/keys/
sudo chown -R cassandra:cassandra  /etc/dse/cassandra/keys
sudo chmod -R a+rx /etc/dse/cassandra/keys
sudo chmod -R a+rx /etc/dse/cassandra/keystores

# update the cassandra_cqlshrc file
mkdir -p /home/ansible/.cassandra
cp ./cassandra_cqlshrc /home/ansible/.cassandra/cqlshrc
PRIVATE_IP=`ifconfig eth1 | grep -w "inet" | awk '{print $2}'`
sed -i -r "s/##PRIVATE_IP##/${PRIVATE_IP}/g" /home/ansible/.cassandra/cqlshrc
sed -i -r "s/##CERT##/${host}_cert_signed/g" /home/ansible/.cassandra/cqlshrc
chown -R ansible:ansible /home/ansible/.cassandra
mkdir -p /root/.cassandra
mkdir -p /home/ec2-user/.cassandra
cp /home/ansible/.cassandra/cqlshrc /root/.cassandra/cqlshrc
cp /home/ansible/.cassandra/cqlshrc /home/ec2-user/.cassandra/cqlshrc

chown -R root:root /root/.cassandra/
chown -R ec2-user:ec2-user /home/ec2-user/.cassandra/
