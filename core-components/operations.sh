#!/bin/bash
set -e

ROOT=$(git rev-parse --show-toplevel)
CORE="$ROOT/core-components"
CONFIGS="$ROOT/configurations"

usage() {
  echo "Usage:"
  echo "  operations.sh"
  echo "    -a : [Required] account name"
  echo "    -v : [Required] vpc name"
  echo "    -c : [Required] cluster name"
  echo "    -o : [Required] operation -> init | restart | restack | etc."
  echo "    -h : host ip (default: all)"
}

parse() {
  grep ^$1 ${variables_path} | awk {'print $NF'} | tr -d '"'
}

get_tfvar() {
  grep "^${1}" ${terraform_var_file} | tr -d '" ' | awk -F'=' {'print $NF'}
}

while getopts ":o:h:a:v:c:" opt; do
  case "${opt}" in
    a)
      account_name=${OPTARG};;
    v)
      vpc_name=${OPTARG};;
    c)
      cluster_name=${OPTARG};;
    o)
      OPERATION=${OPTARG} ;;
    h)
      HOST_IP=${OPTARG} ;;
    *)
      usage; exit 1 ;;
  esac
done
shift "$((OPTIND-1))"

if [[ -z "${OPERATION// }" ]]; then usage; exit 1; fi
if [[ -z "${account_name// }" ]]; then usage; exit 1; fi
if [[ -z "${vpc_name// }" ]]; then usage; exit 1; fi
if [[ -z "${cluster_name// }" ]]; then usage; exit 1; fi

variables_path=${CONFIGS}/${account_name}/variables.yaml

if ! command -v ansible > /dev/null; then
  echo "Ansible is required."
  exit 1
fi

terraform_var_file="${CONFIGS}/${account_name}/${vpc_name}/vpc-resources/vpc.tfvars"
REGION="$(get_tfvar region)"
if [[ -z ${REGION} ]]; then
  REGION="$(parse TERRAFORM_AWS_REGION)"
fi
PROFILE="$(parse TERRAFORM_AWS_PROFILE)"
BUCKET="$(parse TERRAFORM_STATE_BUCKET)"
BUCKET_REGION="$(parse TERRAFORM_STATE_REGION)"
ROLE_NAME="$(parse TERRAFORM_ASSUME_ROLE)"
ACCOUNT="$(aws --profile ${PROFILE} sts get-caller-identity --query 'Account' --output text)"

if [[ "${OPERATION}" != "" ]]; then
  echo "Running OPERATION:  ${OPERATION}"
else
  echo "Must specify a OPERATION to run."
  echo "  - Options are: mount, unmount, start, stop, restart"
  echo "    (see ansible.sh and 'playbooks' dir)"
  exit 1
fi

# Output ssh_config for Ansible
${CORE}/scripts/ssh/build-ssh-config.sh -a ${account_name} -v ${vpc_name} -c ${cluster_name}

pushd ${CORE}/ansible > /dev/null

HOST_ARG="-h ${HOST_IP}"
if [[ -z "${HOST_IP}" ]]; then
  HOST_ARG=""
fi

./ansible.sh -o ${OPERATION} -p ${PROFILE} -r ${REGION} -b ${BUCKET} -a ${account_name} -v ${vpc_name} -c ${cluster_name} -i ${ACCOUNT} -n ${ROLE_NAME} ${HOST_ARG}

popd > /dev/null
