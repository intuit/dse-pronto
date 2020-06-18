#!/bin/bash

ROOT=$(git rev-parse --show-toplevel)
CORE="$ROOT/core-components"
CONFIGS="$ROOT/configurations"

parse() {
  grep ^$1 ${INPUT_VAR_FILE} | awk {'print $NF'} | tr -d '"'
}

get_tfvar() {
  grep "^${1}" ${terraform_var_file} | tr -d '" ' | awk -F'=' {'print $NF'}
}

terraform() {
  CMD="./terraform.sh -a ${account_name} -v ${vpc_name} -c ${cluster_name} -l ${1}-resources -t ${ACTION} -i ${TARGET_ACCOUNT} -r ${ROLE} -d ${CREDS} -b ${TFSTATE} -o ${AMI_OWNER} ${KEEP}"
  echo "${CMD}"
  eval "${CMD}"
  if [[ $? -ne 0 ]]; then exit 1; fi
}

usage() {
  echo "Usage:"
  echo "  deploy.sh"
  echo "    -a : [Required] account name"
  echo "    -v : [Required] vpc name"
  echo "    -c : [Required] cluster name (optional unless deploying cluster layer, then required)"
  echo "    -m : [Required] command -> apply | plan | show | destroy"
  echo "    -l : layer -> account | vpc | cluster | opscenter (default: all)"
  echo "    -k : Keep build dir after terraform runs."
  echo "    -h : Display this help message."
}

while getopts ":l:a:v:c:m:k" opt; do
  case "${opt}" in
    a)
      account_name=${OPTARG};;
    v)
      vpc_name=${OPTARG};;
    c)
      cluster_name=${OPTARG};;
    l)
      LAYER=${OPTARG};;
    m)
      ACTION=${OPTARG};;
    k)
      KEEP="-k";;
    *)
      usage; exit 1;;
  esac
done
shift $((OPTIND -1))

if [[ -z "${ACTION// }" ]]; then ACTION="apply"; fi
if [[ -z "${account_name// }" ]]; then usage; exit 1; fi
if [[ -z "${vpc_name// }" ]]; then usage; exit 1; fi

INPUT_VAR_FILE=${CONFIGS}/${account_name}/variables.yaml

# "cluster_name" for cross-cluster resources is set to something common
case "${LAYER}" in
  "vpc")
    cluster_name="vpc-resources"
    CONFIG_PATH="${account_name}/${vpc_name}/vpc-resources"
    ;;
  "account")
    cluster_name="account-resources"
    CONFIG_PATH="${account_name}/account-resources"
    ;;
  "opscenter")
    cluster_name="opscenter-resources"
    CONFIG_PATH="${account_name}/${vpc_name}/opscenter-resources"
    ;;
  "cluster")
    # cluster_name only required when deploying cluster layer
    if [[ -z "${cluster_name// }" ]]; then usage; exit 1; fi
    CONFIG_PATH="${account_name}/${vpc_name}/${cluster_name}"
    ;;
  *)
    usage; exit 1;;
esac

if ! command -v terraform > /dev/null; then
  echo "Terraform is required."
  exit 1
fi

if [[ ! -e ${INPUT_VAR_FILE} ]]; then
  echo "No variable file found at: ${INPUT_VAR_FILE}"
  exit 1
fi

# for awscli
terraform_var_file="${CONFIGS}/${account_name}/${vpc_name}/vpc-resources/vpc.tfvars"
REGION="$(get_tfvar region)"
TFSTATE_REGION="$(parse TERRAFORM_STATE_REGION)"
if [[ -z "$REGION" ]]; then REGION="$TFSTATE_REGION"; fi

PROFILE="$(parse TERRAFORM_AWS_PROFILE)"
AWS_CMD="aws --profile ${PROFILE} --region ${REGION}"

# pass to terraform.sh
CREDS="$(parse TERRAFORM_AWS_CRED_PATH)"
TFSTATE="$(parse TERRAFORM_STATE_BUCKET)"
AMI_OWNER="$(parse PACKER_ACCOUNT_ID)"
TARGET_ACCOUNT="$(parse TERRAFORM_ACCOUNT_ID)"

# role terraform will assume (check with awscli, then pass to terraform.sh)
ROLE="$(parse TERRAFORM_ASSUME_ROLE)"

################################
# Verify AssumeRole access
################################

set -e
ARN=$(${AWS_CMD} sts get-caller-identity --query 'Arn' --output text)
set +e

if [[ ! "${ARN}" == *"${ROLE}"* ]]; then
  echo "Local AWS credentials are not valid: expected profile '${PROFILE}' to assume role '${ROLE}' in account ${TARGET_ACCOUNT}"
  exit 1
fi

################################
# Verify ssh keys exist
################################

ANSIBLE_KEY="$(parse TERRAFORM_ANSIBLE_KEY_PATH)"
SSH_KEY="$(parse TERRAFORM_SSH_KEY_PATH)"

pushd ${CORE}/scripts/ssh > /dev/null
./init-ansible-key.sh -a ${account_name} -v ${vpc_name} -c ${cluster_name} -n ${ANSIBLE_KEY} -u ${SSH_KEY}
popd > /dev/null

################################
# Verify state bucket exists
################################

AWS_BUCKET_CMD="aws --profile ${PROFILE} --region ${TFSTATE_REGION}"
${AWS_BUCKET_CMD} s3 ls s3://${TFSTATE} > /dev/null
if [[ $? -ne 0 ]]; then
  echo "Creating tfstate bucket at s3://${TFSTATE}"
  ${AWS_BUCKET_CMD} s3 mb s3://${TFSTATE}
  if [[ $? -ne 0 ]]; then exit 1; fi
fi

################################
# Output other vars
################################

echo ""
echo "DSE cluster:       ${cluster_name}"
echo "Input var file:    $(realpath --relative-to=. ${INPUT_VAR_FILE})"
echo "State bucket:      ${TFSTATE}"
if [[ "${LAYER}" != "" ]]; then
  echo "Deploying layer:   ${LAYER}"
fi
echo ""

################################
# Deploy the requested layer, or if none specified, deploy all layers in order
################################

pushd ${CORE}/terraform > /dev/null

if [[ "${LAYER}" == "" ]] || [[ "${LAYER}" == "account" ]]; then
  terraform "account"
fi

if [[ "${LAYER}" == "" ]] || [[ "${LAYER}" == "vpc" ]]; then
  terraform "vpc"
fi

if [[ "${LAYER}" == "" ]] || [[ "${LAYER}" == "cluster" ]]; then
  # Verify existence of cassandra secrets
  pushd ${CORE}/scripts/secrets > /dev/null
  ./init-secrets.sh -a ${account_name} -v ${vpc_name} -c ${cluster_name} -x
  if [[ $? -ne 0 ]]; then exit 1; fi
  popd > /dev/null

  terraform "cluster"
fi

if [[ "${LAYER}" == "" ]] || [[ "${LAYER}" == "opscenter" ]]; then
  terraform "opscenter"
fi

popd > /dev/null
