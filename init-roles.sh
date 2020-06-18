#!/bin/bash

ROOT=$(git rev-parse --show-toplevel)
CORE="$ROOT/core-components"
CONFIGS="$ROOT/configurations"

usage() {
  echo "Usage:"
  echo "  init-roles.sh"
  echo "    -p : [Required] AWS profile with Admin access to IAM in the target account"
  echo "    -a : [Required] account name"
}

parse() {
  grep ^$1 ${variables_path} | awk {'print $NF'} | tr -d '"'
}

while getopts ":p:a:" opt; do
  case "${opt}" in
    p)
      PROFILE=${OPTARG};;
    a)
      account_name=${OPTARG};;
    *)
      usage; exit 1;;
  esac
done
shift "$((OPTIND-1))"

if [[ -z "${PROFILE// }" ]]; then usage; exit 1; fi
if [[ -z "${account_name// }" ]]; then usage; exit 1; fi

AWS_CMD="aws --profile ${PROFILE}"

################################
# Check credentials before starting
################################

${AWS_CMD} sts get-caller-identity > /dev/null
if [[ $? -ne 0 ]]; then
  echo "Provided AWS credentials are not valid (profile: '${PROFILE}')"
  exit 1
fi

################################
# Collect vars
################################

variables_path=${CONFIGS}/${account_name}/variables.yaml

packer_profile=$(parse PACKER_AWS_PROFILE)
terraform_profile=$(parse TERRAFORM_AWS_PROFILE)

ACCOUNT_ID=$(${AWS_CMD} sts get-caller-identity --query "Account" --output text)
IAM_PROFILE_ARN=$(${AWS_CMD} sts get-caller-identity --query "Arn" --output text)

# check if current ARN is an assumed role
if [[ "${IAM_PROFILE_ARN}" == *":assumed-role/"* ]]; then
  # get the base role ARN
  BASE_ROLE_NAME=$(echo ${IAM_PROFILE_ARN} | awk -F'/' {'print $2'})
  IAM_PROFILE_ARN=$(${AWS_CMD} iam get-role --role-name ${BASE_ROLE_NAME} --query Role.Arn --output text)
fi

echo "Current IAM role: ${IAM_PROFILE_ARN}"

PACKER_ROLE_NAME="packer-role"
TERRAFORM_ROLE_NAME="terraform-role"

################################
# Assemble role templates
################################

TERRAFORM_JSON="${CORE}/roles/terraform.json"
PACKER_JSON="${CORE}/roles/packer.json"

# AssumeRole policy needs an IAM ARN to set as Principal
ASSUME_ROLE_JSON="${CORE}/roles/assume-role.json"
sed -e "s?##IAM_PROFILE_ARN##?${IAM_PROFILE_ARN}?g" \
  ${ASSUME_ROLE_JSON}.tpl > ${ASSUME_ROLE_JSON}

echo "---------------"
echo "AssumeRole policy:"
cat ${ASSUME_ROLE_JSON}
echo "---------------"

################################
# Get to work
################################

${AWS_CMD} iam get-role --role-name ${PACKER_ROLE_NAME} > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "Creating role: ${PACKER_ROLE_NAME}"
  ${AWS_CMD} iam create-role --role-name ${PACKER_ROLE_NAME} --assume-role-policy-document file://${ASSUME_ROLE_JSON}
else
  echo "Updating trust policy on role: ${PACKER_ROLE_NAME}"
  ${AWS_CMD} iam update-assume-role-policy --role-name ${PACKER_ROLE_NAME} --policy-document file://${ASSUME_ROLE_JSON}
fi

${AWS_CMD} iam get-role --role-name ${TERRAFORM_ROLE_NAME} > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "Creating role: ${TERRAFORM_ROLE_NAME}"
  ${AWS_CMD} iam create-role --role-name ${TERRAFORM_ROLE_NAME} --assume-role-policy-document file://${ASSUME_ROLE_JSON}
else
  echo "Updating trust policy on role: ${TERRAFORM_ROLE_NAME}"
  ${AWS_CMD} iam update-assume-role-policy --role-name ${TERRAFORM_ROLE_NAME} --policy-document file://${ASSUME_ROLE_JSON}
fi

echo "Waiting for roles..."
${AWS_CMD} iam wait role-exists --role-name ${PACKER_ROLE_NAME}
${AWS_CMD} iam wait role-exists --role-name ${TERRAFORM_ROLE_NAME}

echo "Attaching policies to Packer role..."
${AWS_CMD} iam put-role-policy \
  --role-name ${PACKER_ROLE_NAME} \
  --policy-name ${PACKER_ROLE_NAME}-policy \
  --policy-document file://${PACKER_JSON}

echo "Adding managed policies to Terraform role..."

declare -a arr=(
  "AmazonEC2FullAccess"
  "AWSCertificateManagerReadOnly"
  "AmazonVPCReadOnlyAccess"
  "AWSCloudTrailReadOnlyAccess"
  "CloudWatchReadOnlyAccess"
)

for POLICY in "${arr[@]}"; do
  echo "  - $POLICY"
  ${AWS_CMD} iam attach-role-policy \
    --role-name ${TERRAFORM_ROLE_NAME} --policy-arn "arn:aws:iam::aws:policy/${POLICY}"
  if [[ $? -ne 0 ]]; then exit 1; fi
done

echo "Adding inline policies to Terraform role..."

${AWS_CMD} iam put-role-policy \
  --role-name ${TERRAFORM_ROLE_NAME} \
  --policy-name ${TERRAFORM_ROLE_NAME}-policy \
  --policy-document file://${TERRAFORM_JSON}

echo "---------------"
echo "Add the following profiles to your ~/.aws/credentials file:"
echo ""
cat <<EOF
[${packer_profile}]
source_profile=${PROFILE}
role_arn=arn:aws:iam::${ACCOUNT_ID}:role/${PACKER_ROLE_NAME}

[${terraform_profile}]
source_profile=${PROFILE}
role_arn=arn:aws:iam::${ACCOUNT_ID}:role/${TERRAFORM_ROLE_NAME}
EOF
echo "---------------"
echo "Done!"
