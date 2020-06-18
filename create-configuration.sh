#!/bin/bash

ROOT=$(git rev-parse --show-toplevel)
CORE="$ROOT/core-components"
CONFIGS="$ROOT/configurations"

usage() {
  echo "Usage:"
  echo "  create-configuration.sh"
  echo "    -a : [Required] account name (e.g. 'my-dse-account')"
  echo "    -v : [Required] vpc name (e.g. 'primary-vpc' or 'west-vpc')"
  echo "    -c : [Required] cluster name (e.g. 'dse-cluster' or 'storage-cluster')"
  echo "    -x : if specified, allow terraform to manage my vpc (default: false)"
}

TF_MANAGED_VPC=false

while getopts ":a:c:v:x" opt; do
  case "${opt}" in
    a)
      ACCOUNT_NAME=${OPTARG};;
    c) 
      CLUSTER_NAME=${OPTARG};;
    v)
      VPC_NAME=${OPTARG};;
    x)
      TF_MANAGED_VPC=true;;
    *)
      usage; exit 1;;
  esac
done
shift $((OPTIND -1))

if [[ -z "${ACCOUNT_NAME// }" ]]; then usage; exit 1; fi
if [[ -z "${VPC_NAME// }" ]]; then usage; exit 1; fi
if [[ -z "${CLUSTER_NAME// }" ]]; then usage; exit 1; fi

# validate name formats
if [[ ! "${ACCOUNT_NAME}${VPC_NAME}${CLUSTER_NAME}" =~ ^[a-zA-Z]{1}[a-zA-Z0-9\-]+$ ]]; then
  echo "ERROR: Account name (-a), VPC name (-v), and Cluster name (-c) must start with a letter, and contain only alphanumeric characters (and dashes)."
  exit 1
fi

# default dir paths
DEFAULT_ACCOUNT_DIR=${CONFIGS}/default-account
DEFAULT_VPC_DIR=${DEFAULT_ACCOUNT_DIR}/default-vpc
DEFAULT_CLUSTER_DIR=${DEFAULT_VPC_DIR}/default-cluster

# new dir paths
NEW_ACCOUNT_DIR=${CONFIGS}/${ACCOUNT_NAME}
NEW_VPC_DIR=${NEW_ACCOUNT_DIR}/${VPC_NAME}
NEW_CLUSTER_DIR=${NEW_VPC_DIR}/${CLUSTER_NAME}

# first, make sure this doesn't already exist
if ls -d ${NEW_CLUSTER_DIR} 2>/dev/null; then
  echo "ERROR: Cluster config '${ACCOUNT_NAME}/${VPC_NAME}/${CLUSTER_NAME}' already exists."
  exit 1
fi

# create full account dir if needed
if ! ls -d ${NEW_ACCOUNT_DIR} 2>/dev/null; then
  echo "Creating new account configurations..."
  mkdir ${NEW_ACCOUNT_DIR}
  cp -R ${DEFAULT_ACCOUNT_DIR}/ ${NEW_ACCOUNT_DIR}
  \rm -rf ${NEW_ACCOUNT_DIR}/default-vpc
fi

# create vpc dir if needed
if ! ls -d ${NEW_VPC_DIR} 2>/dev/null; then
  echo "Creating new vpc configurations..."
  mkdir ${NEW_VPC_DIR}
  cp -R ${DEFAULT_VPC_DIR}/ ${NEW_VPC_DIR}
  \rm -rf ${NEW_VPC_DIR}/default-cluster

  # copied both "vpc-existing" and "vpc-new" tfvars; get rid of the one we don't need
  if [[ ${TF_MANAGED_VPC} = false ]]; then
    \rm -f ${NEW_VPC_DIR}/vpc-resources/vpc-new.tfvars
    mv ${NEW_VPC_DIR}/vpc-resources/vpc-existing.tfvars ${NEW_VPC_DIR}/vpc-resources/vpc.tfvars
    echo "Including terraform variables suitable for an existing VPC."
    echo "  - Copied from:  $(realpath --relative-to=. ${DEFAULT_VPC_DIR}/vpc-resources/vpc-existing.tfvars)"
    echo "  - Make sure you've run the validate-vpc.sh script on this VPC!"
    echo "  - If this isn't what you wanted, delete the cluster config dir and run this script again without the -x option."
  else
    \rm -f ${NEW_VPC_DIR}/vpc-resources/vpc-existing.tfvars
    mv ${NEW_VPC_DIR}/vpc-resources/vpc-new.tfvars ${NEW_VPC_DIR}/vpc-resources/vpc.tfvars
    echo "Including terraform variables suitable for a new (terraform-managed) VPC."
    echo "  - Copied from:  $(realpath --relative-to=. ${DEFAULT_VPC_DIR}/vpc-resources/vpc-new.tfvars)"
    echo "  - If this isn't what you wanted, delete the cluster config dir and run this script again with the -x option."
  fi
fi

# create cluster dir
echo "Creating new cluster configurations..."
mkdir ${NEW_CLUSTER_DIR}
cp -R ${DEFAULT_CLUSTER_DIR}/ ${NEW_CLUSTER_DIR}

# info log
echo "Created new configuration profile: cluster '${CLUSTER_NAME}' in account '${ACCOUNT_NAME}' and vpc '${VPC_NAME}'"
echo "  - Profile is in dir:  $(realpath --relative-to=. ${NEW_CLUSTER_DIR})"
echo "  - Customize your configs as needed; fill in any variables left blank (look for \"<<< XYZ_HERE >>>\")."
echo "      $ find $(realpath --relative-to=. ${NEW_ACCOUNT_DIR}) -type f | xargs grep \"<<< .* >>>\""
echo "  - Remember to commit to a git branch somewhere!"
