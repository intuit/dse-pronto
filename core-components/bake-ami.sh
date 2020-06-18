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

noconfig() {
  echo "ERROR: No '${1}' found in:  ${INPUT_VAR_FILE}"
  echo "  -> This is required when baking ${ami_type} AMIs!"
  usage; exit 1;
}

usage() {
  echo "Usage:"
  echo "  bake-ami.sh"
  echo "    -a : [Required] account name"
  echo "    -v : [Required] vpc name"
  echo "    -t : [Required] ami type -> cassandra | opscenter"
  echo "    -i : base ami_id"
}

while getopts ":i:t:a:v:" opt; do
  case "${opt}" in
    i)
      BASE_AMI_ID=${OPTARG};;
    a)
      account_name=${OPTARG};;
    v)
      vpc_name=${OPTARG};;
    t)
      ami_type=${OPTARG};;
    *)
      usage; exit 1;;
  esac
done

if [[ -z "${ami_type// }" ]]; then usage; exit 1; fi
if [[ -z "${account_name// }" ]]; then usage; exit 1; fi
if [[ -z "${vpc_name// }" ]]; then usage; exit 1; fi

INPUT_VAR_FILE=${CONFIGS}/${account_name}/variables.yaml

if ! command -v packer > /dev/null; then
  echo "Packer is required."
  exit 1
fi

MY_IP=$(curl -4 -s ifconfig.co)
count=0
while [[ ! ${MY_IP} =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; do
  if [[ ${count} -lt 20 ]]; then
    echo "Error fetching external IP address; trying again."
    sleep 1
    MY_IP=$(curl -4 -s ifconfig.co)
    ((count++))
  else
    echo "Error fetching external IP address"
    exit 1
  fi
done

################################
# Gather and verify input parameters
################################

# cluster specific vars
terraform_var_file="${CONFIGS}/${account_name}/${vpc_name}/vpc-resources/vpc.tfvars"
PROFILE="$(parse PACKER_AWS_PROFILE)"
REGION="$(parse PACKER_AWS_REGION)"
VPC_REGION="$(get_tfvar region)"
if [[ -z ${VPC_REGION} ]]; then
  VPC_REGION=${REGION}
fi
AWS_CMD="aws --profile ${PROFILE} --region ${REGION}"

VPC_ID="$(parse PACKER_VPC_ID)"
SUBNET_ID="$(parse PACKER_SUBNET_ID)"
BU="$(parse PACKER_BU)"
ENV="$(parse PACKER_ENVIRONMENT)"

# configured artifact versions
DSE_VER="$(parse PACKER_DSE_FULL_VER)"
DSAGENT_VER="$(parse PACKER_DS_AGENT_VER)"
STUDIO_VER="$(parse PACKER_DS_STUDIO_VER)"
OPS_VER="$(parse PACKER_OPSCENTER_FULL_VER)"

# make sure pkg versions are specified as needed
if [[ "${ami_type}" == "cassandra" ]]; then
  if [[ -z "${DSE_VER// }" ]]; then noconfig "PACKER_DSE_FULL_VER"; fi
  if [[ -z "${DSAGENT_VER// }" ]]; then noconfig "PACKER_DSE_AGENT_VER"; fi

  # make sure packer-resources are filled in
  if grep -rq "<<<.*>>>" ${CONFIGS}/${account_name}/packer-resources/cassandra; then
    echo "Please fill out the variables in your packer-resources dir:"
    echo "  grep -r \"<<<.*>>>\" $(realpath --relative-to=. ${CONFIGS})/${account_name}/packer-resources/cassandra"
    exit 1
  fi
fi
if [[ "${ami_type}" == "opscenter" ]]; then
  if [[ -z "${OPS_VER// }" ]]; then noconfig "PACKER_OPSCENTER_FULL_VER"; fi
  if [[ -z "${DSAGENT_VER// }" ]]; then noconfig "PACKER_DS_AGENT_VER"; fi
  if [[ -z "${STUDIO_VER// }" ]]; then noconfig "PACKER_DS_STUDIO_VER"; fi
fi

################################
# Verify cassandra configs are present
################################

config_path="packer-resources/cassandra/configs/${DSE_VER}"
dse_configs_location="${CONFIGS}/${account_name}/${config_path}"
if [[ ! -e ${dse_configs_location} ]] || [[ $(ls ${dse_configs_location}/*.{yaml,sh} | wc -w) -eq 0 ]]; then
  echo "WARNING:  No config files (.yaml, .sh) were found at the following location:"
  echo "  DIR: $(realpath --relative-to=${ROOT} ${dse_configs_location})"
  echo "Copying from the default config profile!  You should copy your own set of these files for modification."
  echo "  DIR: $(realpath --relative-to=${ROOT} ${CONFIGS}/default-account/${config_path})"
  if [[ ! -e ${CONFIGS}/default-account/${config_path} ]]; then
    echo "ERROR:  No config files found in the default profile for DSE version: ${DSE_VER}"
    echo "  - Looked in:  ${CONFIGS}/default-account/${config_path}"
    exit 1
  fi
  mkdir -p ${dse_configs_location}
  cp ${CONFIGS}/default-account/${config_path}/* ${dse_configs_location}/
fi

# make sure we can find a base AMI to start with
if [[ -z "$BASE_AMI_ID" ]]; then
  echo "Base AMI option (-i) not provided, parsing from $(realpath --relative-to=. ${INPUT_VAR_FILE})..."
  BASE_AMI_ID="$(parse PACKER_BASE_AMI_ID)"
fi

if [[ -z "$BASE_AMI_ID" ]]; then
  echo "Base AMI not configured, looking up an appropriate Amazon Linux base AMI..."
  BASE_AMI_ID=$(${AWS_CMD} ec2 describe-images \
                  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text \
                  --filters "Name=owner-alias,Values=amazon" "Name=is-public,Values=true" "Name=state,Values=available" \
                            "Name=name,Values=amzn2-ami-hvm-2.0*x86_64-gp2")
fi

if [[ -z "$BASE_AMI_ID" ]]; then
  echo "No base AMI ID found!"
  exit 1
fi

# get the ami_name from specified ami_id
BASE_AMI_NAME=$(${AWS_CMD} ec2 describe-images --image-ids ${BASE_AMI_ID} --query 'Images[0].Name' --output text)

echo ""
echo "AWS profile:       ${PROFILE}"
echo "Local IP address:  ${MY_IP}"
echo "VPC ID:            ${VPC_ID}"
echo "DSE version:       ${DSE_VER}"
echo "Base AMI:          ${BASE_AMI_NAME}"
echo "Base AMI ID:       ${BASE_AMI_ID}"
echo ""

################################
# Check credentials before starting
################################

${AWS_CMD} sts get-caller-identity > /dev/null
if [[ $? -ne 0 ]]; then
  echo "Local AWS credentials are not valid (profile: ${PROFILE})"
  exit 1
fi

pushd ${CORE}/packer > /dev/null

################################
# Create a security group allowing Packer into the provisioned instance from this IP
################################

PACKER_SG_NAME="packer-ssh-ingress"

GROUP_ID=$(${AWS_CMD} ec2 describe-security-groups \
  --filters Name=group-name,Values=${PACKER_SG_NAME} Name=vpc-id,Values=${VPC_ID} \
  --query 'SecurityGroups[0].GroupId' --output text)

if [[ "${GROUP_ID}" == "None" ]]; then
  echo "Creating new SecurityGroup"
  GROUP_ID=$(${AWS_CMD} ec2 create-security-group \
    --description "Allows SSH ingress for Packer" --group-name ${PACKER_SG_NAME} --vpc-id ${VPC_ID} \
    --query 'GroupId' --output text)
fi

IP_EXIST=$(${AWS_CMD} ec2 describe-security-groups \
  --group-ids ${GROUP_ID} --query 'SecurityGroups[].IpPermissions[].IpRanges[]' \
  --output text | grep "${MY_IP}/32" | wc -l | tr -d "[:space:]")

if [[ ${IP_EXIST} == 0 ]]; then
  ${AWS_CMD} ec2 authorize-security-group-ingress \
    --group-id ${GROUP_ID} --protocol tcp --port 22 --cidr "${MY_IP}/32"
fi

################################
# Create an IAM role for the Packer builder node
################################

PACKER_ROLE_NAME="packer-builder-role"
set +e
${AWS_CMD} iam get-role --role-name ${PACKER_ROLE_NAME} > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "Creating IAM role for Packer builder..."
  ./init-packer-instance-profile.sh -p ${PROFILE} -r ${REGION} -n ${PACKER_ROLE_NAME}
fi
set -e

################################
# Determine AMI type
################################

pushd ${ami_type} > /dev/null

echo "Building AMI: ${ami_type}"

case "${ami_type}" in
  "cassandra")
    PACKER_FILE="dse-cassandra-ami.json" ;;
  "opscenter")
    PACKER_FILE="dse-opscenter-ami.json" ;;
  *)
    usage; exit 1;;
esac

################################
# Invoke Packer
################################

AWS_REGION="${REGION}" \
  AWS_PROFILE="${PROFILE}" \
  VPC_REGION="${VPC_REGION}" \
  PACKER_VPC_ID="${VPC_ID}" \
  PACKER_SUBNET_ID="${SUBNET_ID}" \
  PACKER_SG_ID="${GROUP_ID}" \
  PACKER_DSE_VER="${DSE_VER}" \
  PACKER_DSAGENT_VER="${DSAGENT_VER}" \
  PACKER_STUDIO_VER="${STUDIO_VER}" \
  PACKER_OPS_VER="${OPS_VER}" \
  PACKER_ROLE="${PACKER_ROLE_NAME}" \
  BASE_AMI_ID="${BASE_AMI_ID}" \
  BASE_AMI_NAME="${BASE_AMI_NAME}" \
  PACKER_ENVIRONMENT="${ENV}" \
  PACKER_BU="${BU}" \
  PACKER_CONFIG_PATH="${CONFIGS}/${account_name}/packer-resources" \
    packer build ${PACKER_FILE}

popd > /dev/null
popd > /dev/null
