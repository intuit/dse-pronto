#!/bin/bash

ROOT=$(git rev-parse --show-toplevel)
CONFIGS="$ROOT/configurations"

usage() {
  echo "Usage:"
  echo "  init-ansible-key.sh"
  echo "    -a : [Required] account name"
  echo "    -v : [Required] vpc name"
  echo "    -c : [Required] cluster name"
  echo "    -u : [Optional] path to existing user public key (.pub)"
  echo "    -n : [Optional] path to existing ansible public key (.pub)"
  echo "    -f : [Optional] force re-creation of user-keys file"
}

parse() {
  grep ^$1 ${variables_path} | awk {'print $NF'} | tr -d '"'
}

FORCE=false

while getopts ":a:v:c:u:n:f" opt; do
  case "${opt}" in
    a)
      ACCOUNT_NAME=${OPTARG};;
    v)
      VPC_NAME=${OPTARG};;
    c)
      CLUSTER_NAME=${OPTARG};;
    u)
      USER_KEY=${OPTARG};;
    n)
      ANSIBLE_KEY=${OPTARG};;
    f)
      FORCE=true;;
    *)
      usage; exit 1 ;;
  esac
done
shift $((OPTIND -1))

if [[ -z "${ACCOUNT_NAME// }" ]]; then usage; exit 1; fi
if [[ -z "${VPC_NAME// }" ]]; then usage; exit 1; fi
if [[ -z "${CLUSTER_NAME// }" ]]; then usage; exit 1; fi

case "${CLUSTER_NAME}" in
  "account-resources")
    config_path="${ACCOUNT_NAME}/account-resources"
    exit 0;;
  "vpc-resources")
    config_path="${ACCOUNT_NAME}/${VPC_NAME}/vpc-resources";;
  "opscenter-resources")
    config_path="${ACCOUNT_NAME}/${VPC_NAME}/opscenter-resources";;
  *)
    config_path="${ACCOUNT_NAME}/${VPC_NAME}/${CLUSTER_NAME}";;
esac

KEYFILE_TPL=${CONFIGS}/${ACCOUNT_NAME}/user-keys.yaml.tpl
KEYFILE=${CONFIGS}/${config_path}/user-keys.yaml

if [[ ${FORCE} = true ]]; then
  \rm -f ${KEYFILE}
fi

if [[ -f ${KEYFILE} ]]; then
  echo "SSH key file already present at: $(realpath --relative-to=${ROOT} ${KEYFILE})"
  exit 0
fi

variables_path=${CONFIGS}/${ACCOUNT_NAME}/variables.yaml

if [[ -z "${USER_KEY// }" ]]; then
  USER_KEY=$(parse TERRAFORM_SSH_KEY_PATH)
fi

if [[ -z "${ANSIBLE_KEY// }" ]]; then
  ANSIBLE_KEY=$(parse TERRAFORM_ANSIBLE_KEY_PATH)
fi

eval ANSIBLE_KEY=${ANSIBLE_KEY}
eval USER_KEY=${USER_KEY}

mkdir -p $(dirname ${ANSIBLE_KEY})
mkdir -p $(dirname ${USER_KEY})

# verify ansible key exists, or create one
if [[ -f "${ANSIBLE_KEY//.pub/}" ]]; then
  echo "Ansible SSH key exists at: ${ANSIBLE_KEY}"
  if [[ ! -f "${ANSIBLE_KEY}" ]] || ! ssh-keygen -l -f ${ANSIBLE_KEY} > /dev/null; then
    echo "No public key file found; generating one at ${ANSIBLE_KEY}"
    ssh-keygen -y -f ${ANSIBLE_KEY//.pub/} > ${ANSIBLE_KEY}
  fi
else
  PK="${ANSIBLE_KEY//.pub/}"
  echo "Creating ansible SSH key at: ${PK}"
  ssh-keygen -t rsa -b 2048 -N "" -V "always:forever" -C ansible -f ${PK}
fi

# if user key exists, proceed with both user & ansible keys; otherwise, require the user to create a personal ssh key
if [[ -f ${USER_KEY} ]] && ssh-keygen -l -f ${USER_KEY} > /dev/null; then
  echo "User SSH key exists at: ${USER_KEY}"

  # write out both keys
  sed -e "s?##ANSIBLE_PUB_KEY##?$(cat ${ANSIBLE_KEY})?g" \
      -e "s?##PERSONAL_PUB_KEY##?$(cat ${USER_KEY})?g" \
    ${KEYFILE_TPL} > ${KEYFILE}

  echo "New key file written at: $(realpath --relative-to=${ROOT} ${KEYFILE})"
else
  echo "User SSH key does not exist at: ${USER_KEY}"
  echo "Please generate an SSH key and configure the 'TERRAFORM_SSH_KEY_PATH' param in your variables.yaml file!"
  exit 1
fi
