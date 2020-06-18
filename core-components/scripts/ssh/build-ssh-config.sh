#!/bin/bash

ROOT=$(git rev-parse --show-toplevel)
CORE="$ROOT/core-components"
CONFIGS="$ROOT/configurations"

usage() {
  echo "Usage:"
  echo "  build-ssh-config.sh"
  echo "    -a : [Required] account name"
  echo "    -v : [Required] vpc name"
  echo "    -c : [Required] cluster name"
}

parse() {
  grep ^$1 ${variables_path} | awk {'print $NF'} | tr -d '"'
}

get_tfvar() {
  grep "^${1}" ${terraform_var_file} | tr -d '" ' | awk -F'=' {'print $NF'}
}

while getopts ":a:v:c:" opt; do
  case "${opt}" in
    a)
      account_name=${OPTARG};;
    v)
      vpc_name=${OPTARG};;
    c)
      cluster_name=${OPTARG};;
    *)
      usage; exit 1;;
  esac
done
shift "$((OPTIND-1))"

if [[ -z "${account_name// }" ]]; then usage; exit 1; fi
if [[ -z "${vpc_name// }" ]]; then usage; exit 1; fi
if [[ -z "${cluster_name// }" ]]; then usage; exit 1; fi

variables_path=${CONFIGS}/${account_name}/variables.yaml

terraform_var_file="${CONFIGS}/${account_name}/${vpc_name}/vpc-resources/vpc.tfvars"
PROFILE="$(parse TERRAFORM_AWS_PROFILE)"
REGION="$(get_tfvar region)"
if [ -z ${REGION} ]; then 
  REGION="$(parse TERRAFORM_AWS_REGION)"
fi
AWS_CMD="aws --profile ${PROFILE} --region ${REGION}"

TARGET_ACCOUNT="$(parse TERRAFORM_ACCOUNT_ID)"
ANSIBLE_KEY_PATH="$(parse TERRAFORM_ANSIBLE_KEY_PATH)"

if [[ -z "${ANSIBLE_KEY_PATH// }" ]]; then
  echo "ANSIBLE_KEY_PATH must be specified in variables.yaml in order to run this script!"
  exit 1
fi

eval ANSIBLE_KEY_PATH=${ANSIBLE_KEY_PATH}

echo "-------------------"
echo "Ansible public key:"
cat ${ANSIBLE_KEY_PATH}
echo "-------------------"

# Check credentials before starting
${AWS_CMD} sts get-caller-identity > /dev/null
if [[ $? -ne 0 ]]; then
  echo "Local AWS credentials are not valid (profile: ${PROFILE})"
  exit 1
fi

echo "Generating ssh_config for cluster '${cluster_name}'..."

# get the VPC ID for the cluster from Parameter Store
VPC_ID=$(${AWS_CMD} ssm get-parameters \
  --names "/dse/${account_name}/${vpc_name}/vpc-resources/vpc_id" \
  --query "Parameters[0].Value" --output text)

echo "   - VPC:       ${VPC_ID}"

# get the ENI IP for each seed node
SEED_IP=$(${AWS_CMD} ec2 describe-network-interfaces \
  --filters "Name=tag:Name,Values=${cluster_name}-seed*" \
  --query 'NetworkInterfaces[].PrivateIpAddress' \
  --output text | awk '$1=$1')

echo "   - Seeds:     ${SEED_IP}"

# get the ENI IP for each non-seed node
NON_SEED_IP=$(${AWS_CMD} ec2 describe-network-interfaces \
  --filters "Name=tag:Name,Values=${cluster_name}-non-seed*" \
  --query 'NetworkInterfaces[].PrivateIpAddress' \
  --output text | awk '$1=$1')

echo "   - Non-seeds: ${NON_SEED_IP}"

if [[ "${SEED_IP}" == "" ]]; then
  if [[ ${cluster_name} != "opscenter-resources" ]]; then
    # opscenter won't have a seed IP; otherwise, require it
    echo "No seed node IPs found, exiting."
    exit 1
  fi
fi

sc=$(echo ${SEED_IP} | wc -w | tr -d ' ')
nsc=$(echo ${NON_SEED_IP} | wc -w | tr -d ' ')
tc=$(echo ${SEED_IP} ${NON_SEED_IP} | wc -w | tr -d ' ')
echo " - Found ${sc} seed nodes, ${nsc} non-seed nodes (${tc} total)"

# get bastion LB dns name
BASTION_DNS=$(${AWS_CMD} elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='${VPC_ID}' && starts_with(LoadBalancerName, 'bast-')]|[0].DNSName" \
  --output text)

if [[ "${BASTION_DNS}" == "" ]]; then
  echo "No bastion LB found, exiting."
  exit 1
fi

echo " - Found bastion LB at: ${BASTION_DNS}"

# output ansible ssh_config
CFG_PATH=${CORE}/ansible/ssh_config

sed -e "s?##SSH_KEY_PATH##?${ANSIBLE_KEY_PATH//.pub/}?g" \
    -e "s?##BASTION_DNS##?${BASTION_DNS}?g" \
    -e "s?##SEED_IP##?10.* ${SEED_IP} ${NON_SEED_IP}?g" \
    -e "s?##USER##?ansible?g" \
  ${CORE}/scripts/ssh/ssh_config.tpl > ${CFG_PATH}

echo " - Ansible SSH config output at: $(realpath --relative-to=. ${CFG_PATH})"

# output local user's ssh_config
USER_KEY_PATH="$(parse TERRAFORM_SSH_KEY_PATH)"
CFG_PATH=${ROOT}/ssh_config

sed -e "s?##SSH_KEY_PATH##?${USER_KEY_PATH//.pub/}?g" \
    -e "s?##BASTION_DNS##?${BASTION_DNS}?g" \
    -e "s?##SEED_IP##?10.* ${SEED_IP} ${NON_SEED_IP}?g" \
    -e "s?##USER##?ec2-user?g" \
  ${CORE}/scripts/ssh/ssh_config.tpl > ${CFG_PATH}

echo " - Personal (your key) SSH config output at: $(realpath --relative-to=. ${CFG_PATH})"
