#!/bin/bash

if ! type jq; then
  sudo yum install -y jq
fi

REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone/ | sed 's/[a-z]$//')
PROFILE=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/)
CREDS=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/${PROFILE})

ACCESS_KEY=$(echo ${CREDS} | jq -r '.AccessKeyId')
SECRET_KEY=$(echo ${CREDS} | jq -r '.SecretAccessKey')
TOKEN=$(echo ${CREDS} | jq -r '.Token')

AWS_DIR="/home/ec2-user/.aws"
mkdir -p ${AWS_DIR}

cat > ${AWS_DIR}/credentials << EOM
[default]
aws_access_key_id=${ACCESS_KEY}
aws_secret_access_key=${SECRET_KEY}
aws_session_token=${TOKEN}
EOM

cat > ${AWS_DIR}/config << EOM
[default]
region=${REGION}
output=json
EOM
