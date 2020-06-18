#!/bin/bash
set -e

ROOT=$(git rev-parse --show-toplevel)
CORE="$ROOT/core-components"
CONFIGS="$ROOT/configurations"

keep_build=false

parse() {
  grep ^$1 ${CONFIGS}/${account_name}/variables.yaml | awk {'print $NF'} | tr -d '"'
}

parse_creds() {
  CREDSFILE=$1
  PROFILE=$2
  KEY=$3
  # grab one profile by name: http://www.grymoire.com/Unix/Sed.html#uh-29
  sed -En "/\[${PROFILE}\]/,/\[.*\]/p" ${CREDSFILE} | grep ^${KEY} | cut -d '=' -f 2-
}

echoerr() {
  echo $1 >&2
}

get_tfvar() {
  grep "^${1}" ${terraform_var_file} | tr -d '" ' | awk -F'=' {'print $NF'}
}

function exit_cleanup()
{
  if [[ "$keep_build" = true ]] ; then
    echo "Keeping build directory: ${build_dir}"
  else
    \rm -rf ${build_dir}
    echo "Deleted build directory!"
  fi
}

usage() {
  echo "Usage:"
  echo "  terraform.sh"
  echo "    -a : account name"
  echo "    -v : vpc name"
  echo "    -c : cluster name"
  echo "    -l : layer -> vpc, account, cluster, opscenter"
  echo "    -t : action -> plan, apply, show"
  echo "    -d : credentials file"
  echo "    -r : name of assumed_role"
  echo "    -i : account id"
  echo "    -b : tfstate bucket name"
  echo "    -o : ami owner acct id"
  echo "    -k : keep build dir after terraform runs"
  echo "    [-x <extra args>]"
  echo "  Note: extra args will be appended directly to the end of the terraform command"
}

while getopts ":r:d:a:v:c:l:t:i:b:o:x:hk" opt; do
  case "${opt}" in
    r)
      assumed_role=${OPTARG};;
    d)
      credentials=${OPTARG};;
    a)
      account_name=${OPTARG};;
    v)
      vpc_name=${OPTARG};;
    c)
      cluster_name=${OPTARG};;
    l)
      layer=${OPTARG};;
    t)
      action=${OPTARG};;
    i)
      account_id=${OPTARG};;
    b)
      bucket=${OPTARG};;
    o)
      ami_owner_account=${OPTARG};;
    k)
      keep_build=true;;
    h)
      usage; exit 0;;
    x)
      extra_args=${OPTARG};;
    *)
      usage; exit 1;;
  esac
done
shift "$((OPTIND-1))"

# make sure we have the credentials terraform needs
if [[ -z "${assumed_role// }" ]]; then usage; exit 1; fi
if [[ -z "${account_id// }" ]]; then usage; exit 1; fi
if [[ -z "${credentials// }" ]]; then usage; exit 1; fi

# require cluster vars too
if [[ -z "${account_name// }" ]]; then usage; exit 1; fi
if [[ -z "${vpc_name// }" ]]; then usage; exit 1; fi
if [[ -z "${cluster_name// }" ]]; then usage; exit 1; fi
if [[ -z "${layer// }" ]]; then usage; exit 1; fi
if [[ -z "${action// }" ]]; then usage; exit 1; fi
if [[ -z "${bucket// }" ]]; then usage; exit 1; fi
if [[ -z "${ami_owner_account// }" ]]; then usage; exit 1; fi

################################
# build path to TFVARS and TFSTATE before anything else
################################

case "${layer}" in
  "account-resources")
    path="${account_name}/account-resources/account";;
  "vpc-resources")
    path="${account_name}/${vpc_name}/vpc-resources/vpc";;
  "cluster-resources")
    path="${account_name}/${vpc_name}/${cluster_name}/cluster";;
  "opscenter-resources")
    path="${account_name}/${vpc_name}/opscenter-resources/opscenter";;
  *)
    usage; exit 1;;
esac

terraform_var_file="${CONFIGS}/${path}.tfvars"
tfstate_key="${path}.tfstate"

if [[ ! ${terraform_var_file} ]]; then
  echoerr "No tfvars found at ${terraform_var_file}"
  usage; exit 1
fi

if grep -q "<<<.*>>>" ${terraform_var_file}; then
  echoerr "Please fill out your tfvars: ${terraform_var_file}"
  exit 1
fi

# account-specific variables
aws_profile=$(parse "TERRAFORM_AWS_PROFILE")
terraform_var_file="${CONFIGS}/${account_name}/${vpc_name}/vpc-resources/vpc.tfvars"
region=$(get_tfvar region)
if [[ -z ${region} ]]; then
  region="$(parse TERRAFORM_AWS_REGION)"
fi
tfstate_region=$(parse "TERRAFORM_STATE_REGION")
terraform_var_file="${CONFIGS}/${path}.tfvars"
if [[ -z "$region" ]]; then region="$tfstate_region"; fi

################################
# debug info
################################

echo ""
echo "DEPLOYMENT SETTINGS"
echo "  account:    $account_name"
echo "  vpc:        $vpc_name"
echo "  cluster:    $cluster_name"
echo "  region:     $region"
echo "  account_id: $account_id"
echo "  layer:      $layer"
echo ""

################################
# set up build directory
################################

build_dir="$CORE/terraform/build/$cluster_name-$layer-$RANDOM"
modules_dir="$CORE/terraform/modules"
cidr_vars="$CONFIGS/tfvars/cidrs.tfvars"
backend_file="$build_dir/backend.tf"
backend_template="aws_backend.tf"

mkdir -p ${build_dir}
trap exit_cleanup EXIT

# copy contents of layer dir to $build_dir for temporary workspace
cp -a ${CORE}/terraform/layers/${layer}/* ${build_dir} || exit 1
cp ${CORE}/terraform/versions.tf ${build_dir} || exit 1

# populate the backend file
sed -e "s?#bucket#?${bucket}?g" \
    -e "s?#key#?${tfstate_key}?g" \
    -e "s?#account#?${account_id}?g" \
    -e "s?#rolename#?${assumed_role}?g" \
    -e "s?#region#?${region}?g" \
    -e "s?#tfstate_region#?${tfstate_region}?g" \
  ${CORE}/terraform/${backend_template} > ${backend_file}

################################
# make sure vpc vars have been specified properly
################################

if [[ "${layer// }" == "vpc-resources" ]]; then
  create_vpc=$(parse "TERRAFORM_MANAGED_VPC")
  if [[ "$create_vpc" == "false" ]]; then
    vpc_id=$(get_tfvar "vpc_id")
    if [[ -z "${vpc_id// }" ]]; then
      echoerr "MISSING VARS IN: $(realpath --relative-to=${ROOT} ${terraform_var_file})"
      echoerr " - TERRAFORM_MANAGED_VPC (in variables.yaml) is FALSE, but no vpc_id specified in tfvars!"
      exit 1
    else
      echo "Proceeding with vpc_id: ${vpc_id}"

      # don't need to create the vpc (remove vpc-create.tf)
      \rm -f ${build_dir}/vpc-create.tf
    fi
  elif [[ "$create_vpc" == "true" ]]; then
    vpc_cidr=$(get_tfvar "vpc_cidr")
    azs=$(get_tfvar "azs")
    data_subnets=$(get_tfvar "data_subnets")
    ingress_subnets=$(get_tfvar "ingress_subnets")
    if [[ -z "${vpc_cidr// }" ]] || [[ -z "${azs// }" ]] || [[ -z "${data_subnets// }" ]] || [[ -z "${ingress_subnets// }" ]]; then
      echoerr "MISSING VARS IN: $(realpath --relative-to=${ROOT} ${terraform_var_file})"
      echoerr " - TERRAFORM_MANAGED_VPC (in variables.yaml) is TRUE, but no cidr/prefix/subnet specified in tfvars!"
      exit 1
    else
      echo "Will create a VPC with cidr '${vpc_cidr}' and name '${vpc_name}'"
      echo "  - Subnets will be created in AZs: ${azs}"
      echo "      with (private) data CIDRs: ${data_subnets}"
      echo "      and (public) ingress CIDRs: ${ingress_subnets}"

      # there is no pre-existing vpc (remove vpc-info.tf)
      \rm -f ${build_dir}/vpc-info.tf
    fi
  else
    echoerr "MISSING VARS IN: $(realpath --relative-to=${ROOT} ${terraform_var_file})"
    echoerr " - TERRAFORM_MANAGED_VPC (in variables.yaml) is not set properly!"
    exit 1
  fi
  echo ""
fi

################################
# find access keys for terraform (must be exported to env variables)
################################

# check terraform aws profile first
eval credentials=${credentials}
if [[ -z "$(parse_creds "${credentials}" "${aws_profile}" "aws_access_key_id")" ]]; then
  # look for a source_profile
  source_profile="$(parse_creds "${credentials}" "${aws_profile}" "source_profile")"
  if [[ -z "${source_profile// }" ]]; then
    echo "No access keys found in credential file at: ${credentials}"
    echo "  - checked in profile '${aws_profile}'"
    echo "  - no keys, and no source_profile found to check"
    exit 1
  fi
  aws_profile="${source_profile}"
fi

# export credentials to env vars for terraform's use
export AWS_ACCESS_KEY_ID="$(parse_creds "${credentials}" "${source_profile}" "aws_access_key_id")"
export AWS_SECRET_ACCESS_KEY="$(parse_creds "${credentials}" "${source_profile}" "aws_secret_access_key")"
export AWS_SESSION_TOKEN="$(parse_creds "${credentials}" "${source_profile}" "aws_session_token")"
export AWS_DEFAULT_REGION="${region}"

# couldn't find any keys
if [[ -z "${AWS_ACCESS_KEY_ID// }" ]]; then
  echo "No access keys found in credential file at: ${credentials}"
  exit 1
fi

################################
# initialize terraform
################################

pushd ${build_dir} > /dev/null

echo "BUILD SETTINGS"
echo "  tfvars path:  $(realpath --relative-to=${ROOT} ${terraform_var_file})"
echo "  backend.tf:   $(realpath --relative-to=${ROOT} ${backend_file})"
echo "  account_id:   ${account_id}"
echo "  assumed_role: ${assumed_role}"
echo "  deploy dir:   $(pwd)"
echo ""

\rm -rf .terraform

echo "TERRAFORM INIT"
echo "  initializing s3 backend at s3://$bucket/$tfstate_key"
echo ""
echo no | terraform init -reconfigure

################################
# run terraform action
################################

role_arn="arn:aws:iam::${account_id}:role/${assumed_role}"

cidr_tfvar_op=""
if [ "${layer}" ==  "vpc-resources" ] || [ "${layer}" ==  "opscenter-resources" ]; then
  cidr_tfvar_op="-var-file=${cidr_vars}"
fi

## include tags
account_tags="$CONFIGS/$account_name/account-resources/tags.tfvars"
vpc_tags="$CONFIGS/$account_name/$vpc_name/vpc-resources/tags.tfvars"
cluster_tags="$CONFIGS/$account_name/$vpc_name/$cluster_name/tags.tfvars"
opscenter_tags="$CONFIGS/$account_name/$vpc_name/opscenter-resources/tags.tfvars"

account_tags_op="-var-file=${account_tags}"
vpc_tags_op="-var-file=${vpc_tags}"
cluster_tags_op="-var-file=${cluster_tags}"
opscenter_tags_op="-var-file=${opscenter_tags}"

tags_op=""
if [ "${layer}" == "account-resources" ]; then
  tags_op="${account_tags_op}"
fi
if [ "${layer}" == "vpc-resources" ]; then
  tags_op="${account_tags_op} ${vpc_tags_op}"
fi
if [ "${layer}" == "cluster-resources" ]; then
  tags_op="${account_tags_op} ${vpc_tags_op} ${cluster_tags_op}"
fi
if [ "${layer}" == "opscenter-resources" ]; then
  tags_op="${account_tags_op} ${vpc_tags_op} ${opscenter_tags_op}"
fi

VARS="-var-file=${terraform_var_file} \
-var profile=${aws_profile} \
-var region=${region} \
-var account_id=${account_id} \
-var account_name=${account_name} \
-var vpc_name=${vpc_name} \
-var cluster_name=${cluster_name} \
-var ami_owner_id=${ami_owner_account} \
-var tfstate_bucket=${bucket} \
-var tfstate_region=${tfstate_region} \
-var role_arn=${role_arn} \
${cidr_tfvar_op} \
${tags_op}"

CMD="terraform ${action} ${VARS}"
if [[ "$action" == "apply" ]]; then
  CMD="${CMD} -auto-approve"
fi
CMD="${CMD} ${extra_args}"

echo ""
echo "TERRAFORM COMMAND"
echo "$CMD"
echo ""
echo "!!! RUNNING TERRAFORM !!!"
echo ""

eval ${CMD}
tf_exit_code=$?
popd > /dev/null

exit ${tf_exit_code}
