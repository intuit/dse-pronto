#!/bin/bash

usage() {
  echo "Usage:"
  echo "  init-packer-instance-profile.sh -p <profile> -r <region> -n <role_name>"
}

while getopts ":p:r:n:" opt; do
  case "${opt}" in
    p)
      PROFILE=${OPTARG} ;;
    r)
      REGION=${OPTARG} ;;
    n)
      PACKER_ROLE_NAME=${OPTARG} ;;
    *)
      usage; exit 1 ;;
  esac
done
shift $((OPTIND -1))

if [[ -z "${PROFILE// }" ]]; then usage; exit 1; fi
if [[ -z "${REGION// }" ]]; then usage; exit 1; fi
if [[ -z "${PACKER_ROLE_NAME// }" ]]; then usage; exit 1; fi

ASSUME_ROLE_DOC=/tmp/assume-role.json
cat > ${ASSUME_ROLE_DOC} << EOM
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOM

aws iam get-role --role-name ${PACKER_ROLE_NAME} > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "Creating role: ${PACKER_ROLE_NAME}"
  aws iam create-role --profile ${PROFILE} --region ${REGION} \
    --role-name ${PACKER_ROLE_NAME} --assume-role-policy-document file://${ASSUME_ROLE_DOC} > /dev/null
fi

echo "Waiting for role..."
aws iam wait role-exists --role-name ${PACKER_ROLE_NAME} --profile ${PROFILE} --region ${REGION}

read -r -d '' PACKER_POLICY << EOM
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect":"Allow",
        "Action":"iam:PassRole",
        "Resource": [
            "*"
        ]
      }
    ]
}
EOM

echo "Attaching policy..."

aws iam put-role-policy --profile ${PROFILE} --region ${REGION} \
  --role-name ${PACKER_ROLE_NAME} \
  --policy-name ${PACKER_ROLE_NAME} \
  --policy-document "${PACKER_POLICY//[$'\t\r\n ']}"

aws iam wait instance-profile-exists --profile ${PROFILE} --region ${REGION} \
  --instance-profile-name ${PACKER_ROLE_NAME} > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "Creating instance profile: ${PACKER_ROLE_NAME}"
  aws iam create-instance-profile --profile ${PROFILE} --region ${REGION} \
    --instance-profile-name ${PACKER_ROLE_NAME} > /dev/null
fi

echo "Waiting for instance profile..."
aws iam wait instance-profile-exists --profile ${PROFILE} --region ${REGION} \
  --instance-profile-name ${PACKER_ROLE_NAME}

INSTANCE_PROFILES=$(aws iam list-instance-profiles-for-role --role-name ${PACKER_ROLE_NAME} \
  --query 'InstanceProfiles[*].InstanceProfileName' --profile ${PROFILE} --region ${REGION} --output text)
if [[ ! "${INSTANCE_PROFILES}" =~ "${PACKER_ROLE_NAME}" ]]; then
  echo "Adding instance profile to role..."
  aws iam add-role-to-instance-profile --profile ${PROFILE} --region ${REGION} \
    --instance-profile-name ${PACKER_ROLE_NAME} --role-name ${PACKER_ROLE_NAME}
fi

# no convenient "iam wait" command for this (yet)
echo "Waiting for role-profile attachment..."
sleep 5
while ! [[ $(aws iam list-instance-profiles-for-role \
               --role-name ${PACKER_ROLE_NAME} --query 'InstanceProfiles[] | length(@)' \
               --profile ${PROFILE} --region ${REGION}) -ge 1 ]];
do echo "Still waiting..."; sleep 5; done
