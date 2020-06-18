#!/bin/bash
#set -x
secrets_ssm_location="${1}"
region="${2}"

cassandra_pass=$(aws --region ${region} ssm get-parameter --with-decryption --name "${secrets_ssm_location}/cassandra_pass" | jq -r '.[].Value' | base64 -d)

# Attempt to login with default cassandra password
cqlsh --ssl -u cassandra -p cassandra -e exit
if [[ $? -eq 0 ]]; then
  UPDATE_STMT="ALTER USER cassandra  WITH PASSWORD '${cassandra_pass}';"
  cqlsh --ssl -u cassandra -p cassandra -e "${UPDATE_STMT}"
  echo "Password for cassandra user updated"
else
  cqlsh --ssl -u cassandra -p ${cassandra_pass} -e exit
  if [[ $? -eq 0 ]]; then
    echo "Password for cassandra user already updated"
  else
    echo "ERROR: Unable to access cqlsh via ssl with either the default or provided password (from ${secrets_s3_location})."
    echo " - This may indicate a problem with the password, or an issue with ssl certs, or it may indicate DSE isn't running."
    return 1
  fi
fi
