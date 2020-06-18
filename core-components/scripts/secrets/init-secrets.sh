#!/bin/bash
set -e

ROOT=$(git rev-parse --show-toplevel)
CORE="$ROOT/core-components"
CONFIGS="$ROOT/configurations"

usage() {
  echo "Usage:"
  echo "  init-secrets.sh"
  echo "    -a : [Required] account name"
  echo "    -v : [Required] vpc name"
  echo "    -c : [Required] cluster name"
  echo "    -x : [Optional] verify existence of passwords in SSM, then exit"
  echo "    -d : [Optional] delete a secret value (valid arguments: cassandra OR truststore OR keystore OR all)"
  echo "    -o : [Optional] write a single value (valid arguments: cassandra OR truststore OR keystore)"
}

parse() {
  grep ^$1 ${variables_path} | awk {'print $NF'} | tr -d '"'
}

get_password() {
  pwd_name=$1
  pwd_exist=$2
  overwrite_item=$3
  parameter_path=$4

  password=temp
  if [[ ${pwd_exist} -ne 0 ]] || [[ "${overwrite_item}" == "${pwd_name}" ]] || [[ ${overwrite_item} = "all" ]]; then
    while [[ ${#password} -lt 6 ]]; do
      read -s -p "Enter ${pwd_name} password: " password
      echo
      if [[ ${#password} -lt 6 ]]; then
        echo "Password must be longer than 6 characters"
      fi
    done
    password=$(echo ${password} | base64)

    ${AWS_CMD} ssm put-parameter \
      --name "${parameter_path}/${pwd_name}_pass" \
      --type "SecureString" \
      --value $password \
      --overwrite > /dev/null
    if [[ ${overwrite_item} == "${pwd_name}" ]]; then
      exit 0
    fi
  else
    echo "Password already exists (${pwd_name})"
  fi
}

verify=false
overwrite_item='None'
delete_item=''

while getopts ":a:v:c:d:xo:" opt; do
  case "${opt}" in
    a)
      account_name=${OPTARG};;
    v)
      vpc_name=${OPTARG};;
    c)
      cluster_name=${OPTARG};;
    d)
      delete_item=${OPTARG};;
    x)
      verify=true;;
    o)
      overwrite_item=${OPTARG};;
    *)
      usage; exit 1;;
  esac
done
shift "$((OPTIND-1))"

if [[ -z "${account_name// }" ]]; then usage; exit 1; fi
if [[ -z "${vpc_name// }" ]]; then usage; exit 1; fi
if [[ -z "${cluster_name// }" ]]; then usage; exit 1; fi

variables_path=${CONFIGS}/${account_name}/variables.yaml
parameter_path="/dse/${account_name}/${vpc_name}/${cluster_name}/secrets"

################################
# check credentials
################################

terraform_var_file="${CONFIGS}/${account_name}/${vpc_name}/vpc-resources/vpc.tfvars"
PROFILE="$(parse TERRAFORM_AWS_PROFILE)"
REGION="$(parse TERRAFORM_AWS_REGION)"
AWS_CMD="aws --profile ${PROFILE} --region ${REGION}"

${AWS_CMD} sts get-caller-identity > /dev/null
if [[ $? -ne 0 ]]; then
  echo "Local AWS credentials are not valid (profile: ${PROFILE})"
  exit 1
fi

################################
# check if parameters exist
################################

set +e
${AWS_CMD} ssm get-parameter --name "${parameter_path}/cassandra_pass" > /dev/null 2>&1
cassandra_pwd_exist=$?
${AWS_CMD} ssm get-parameter --name "${parameter_path}/keystore_pass" > /dev/null 2>&1
keystore_pwd_exist=$?
${AWS_CMD} ssm get-parameter --name "${parameter_path}/truststore_pass" > /dev/null 2>&1
truststore_pwd_exist=$?
set -e

if [[ ${verify} = true ]]; then
  echo "Checking for existing secrets in SSM..."
  if [[ ${cassandra_pwd_exist} -ne 0 ]]; then
    echo "Cassandra secret not found!"
  else
    echo "Cassandra secret exists."
  fi

  if [[ ${keystore_pwd_exist} -ne 0 ]]; then
    echo "Keystore secret not found!"
  else
    echo "Keystore secret exists."
  fi

  if [[ ${truststore_pwd_exist} -ne 0 ]]; then
    echo "Truststore secret not found!"
  else
    echo "Truststore secret exists."
  fi

  if [[ ${cassandra_pwd_exist} -ne 0 || ${keystore_pwd_exist} -ne 0 || ${truststore_pwd_exist} -ne 0 ]]; then
    echo "Please run the script 'core-components/scripts/secrets/init-secrets.sh' manually to perform initial setup."
    exit 1
  fi
  exit 0
fi

################################
# delete operation
################################

ssm_delete_op="${AWS_CMD} ssm delete-parameters --names"
if [[ ${cassandra_pwd_exist} -ne 0 ]] && [[ ${keystore_pwd_exist} -ne 0 ]] && [[ ${truststore_pwd_exist} -ne 0 ]] && [[ ${delete} = true ]]; then
  echo "Secrets do not exist. Deleting nothing."
  exit 1
elif [[ ${cassandra_pwd_exist} -eq 0 ]] && [[ "${delete_item}" == "cassandra" ]]; then
  echo "Deleting cassandra password..."
  ${ssm_delete_op} "${parameter_path}/cassandra_pass"
  exit 0
elif [[ ${keystore_pwd_exist} -eq 0 ]] && [[ "${delete_item}" == "keystore" ]]; then
  echo "Deleting keystore password..."
  ${ssm_delete_op} "${parameter_path}/keystore_pass"
  exit 0
elif [[ ${truststore_pwd_exist} -eq 0 ]] && [[ "${delete_item}" == "truststore" ]]; then
  echo "Deleting truststore password..."
  ${ssm_delete_op} "${parameter_path}/truststore_pass"
  exit 0
fi

if [[ ${delete_item} == "all" ]]; then
  echo "Deleting ALL existing secrets from parameter store!"
  ${AWS_CMD} ssm delete-parameters --names "${parameter_path}/cassandra_pass" "${parameter_path}/truststore_pass" "${parameter_path}/keystore_pass"
  exit 0
fi

################################
# read passwords from user
################################

echo "----------- NOTE: -----------"
echo "This script is one-time setup for a new cluster.  You must specify passwords for the keystore,"
echo "truststore, and cassandra DB user.  These passwords will be stored in parameter store for your"
echo "cluster to access, and they must exist in order for the cluster to start properly."
echo "DO NOT RUN THIS FROM JENKINS."
echo "-----------------------------"

get_password "keystore" ${keystore_pwd_exist} ${overwrite_item} ${parameter_path}
get_password "truststore" ${truststore_pwd_exist} ${overwrite_item} ${parameter_path}
get_password "cassandra" ${cassandra_pwd_exist} ${overwrite_item} ${parameter_path}
