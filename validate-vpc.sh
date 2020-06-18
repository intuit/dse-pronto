#!/bin/bash

usage() {
  echo "Usage:"
  echo "  validate-vpc.sh"
  echo "    -p : [Required] AWS profile with Admin access to the target VPC"
  echo "    -r : [Required] region of the target VPC"
  echo "    -v : [Required] target VPC ID"
  echo "    -i : name prefix for public subnets in ingress layer (default: 'Ingress')"
  echo "    -d : name prefix for private subnets in DB layer (default: 'Data')"
}

INGRESS_PREFIX="Ingress"
DATA_PREFIX="Data"

while getopts ":p:r:v:i:d:h" opt; do
  case "${opt}" in
    p)
      PROFILE=${OPTARG};;
    r)
      REGION=${OPTARG};;
    v)
      VPC_ID=${OPTARG};;
    i)
      INGRESS_PREFIX=${OPTARG};;
    d)
      DATA_PREFIX=${OPTARG};;
    h)
      usage; exit 0;;
    *)
      usage; exit 1;;
  esac
done
shift "$((OPTIND-1))"

if [[ -z "${PROFILE// }" ]]; then usage; exit 1; fi
if [[ -z "${REGION// }" ]]; then usage; exit 1; fi
if [[ -z "${VPC_ID// }" ]]; then usage; exit 1; fi

AWS_CMD="aws --profile ${PROFILE} --region ${REGION}"

# check credentials before starting

${AWS_CMD} sts get-caller-identity > /dev/null
if [[ $? -ne 0 ]]; then
  echo "Local AWS credentials are not valid (profile: ${PROFILE})"
  exit 1
fi

# check that vpc exists

${AWS_CMD} ec2 describe-vpcs --vpc-ids ${VPC_ID} > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "VPC '${VPC_ID}' not found."
  exit 1
fi

# check if it's a default vpc

RTB_LIST=$(${AWS_CMD} ec2 describe-route-tables \
  --filters Name=vpc-id,Values=${VPC_ID} \
  --query 'RouteTables[*].[RouteTableId,Associations[*].SubnetId|length(@)]' --output text)

if [[ $(echo ${RTB_LIST} | grep -o "rtb-" | wc -l | awk {'print $NF'}) = 1 ]] && [[ $(echo ${RTB_LIST} | awk {'print $NF'}) = 0 ]]; then
  echo "VPC '${VPC_ID}' appears to be a default VPC, containing only one RTB with no explicit subnet associations"
  echo " - This repo requires a specific VPC structure (see docs/1.INITIAL_SETUP.md for details)"
  exit 1
fi

# check ingress subnets

INGRESS_SUBNETS=$(${AWS_CMD} ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${INGRESS_PREFIX}*" \
  --query 'Subnets[*].SubnetId' --output text)

if [[ "${INGRESS_SUBNETS}" == "" ]]; then
  echo "No INGRESS subnets with prefix '${INGRESS_PREFIX}' found in vpc '${VPC_ID}'"
  exit 1
fi

echo "Ingress subnets:"
for SUBNET_ID in ${INGRESS_SUBNETS}; do
  echo "  $SUBNET_ID"
  RTB_ID=$(${AWS_CMD} ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=association.subnet-id,Values=${SUBNET_ID}" \
    --query 'RouteTables[*].RouteTableId' --output text)
  echo "    $RTB_ID"

  # Ingress subnets must have a route to an IGW
  IGW_ID=$(${AWS_CMD} ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=association.subnet-id,Values=${SUBNET_ID}" \
    --query 'RouteTables[*].Routes[?DestinationCidrBlock==`0.0.0.0/0`]|[].GatewayId' --output text)
  if [[ "${IGW_ID}" == "" ]]; then
    echo "Ingress subnets must include a route with DestinationCidrBlock 0.0.0.0/0, targeting an IGW in the VPC"
    exit 1
  fi
  echo "      $IGW_ID"
done

# check data subnets

DATA_SUBNETS=$(${AWS_CMD} ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${DATA_PREFIX}*" \
  --query 'Subnets[*].SubnetId' --output text)

if [[ "${DATA_SUBNETS}" == "" ]]; then
  echo "No DATA subnets with prefix '${DATA_PREFIX}' found in vpc '${VPC_ID}'"
  exit 1
fi

echo "Data subnets:"
for SUBNET_ID in ${DATA_SUBNETS}; do
  echo "  $SUBNET_ID"
  RTB_ID=$(${AWS_CMD} ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=association.subnet-id,Values=${SUBNET_ID}" \
    --query 'RouteTables[*].RouteTableId' --output text)
  echo "    $RTB_ID"

  # Data subnets must have a route to a NATGW
  NATGW_ID=$(${AWS_CMD} ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=association.subnet-id,Values=${SUBNET_ID}" \
    --query 'RouteTables[*].Routes[?DestinationCidrBlock==`0.0.0.0/0`]|[].NatGatewayId' --output text)

  if [[ "${NATGW_ID}" == "" ]]; then
    echo "      Missing NATGW route. Adding route for ${SUBNET_ID}.."

    # Find the first NATGW id, doesn't matter which one
    NATGW_ID=$(${AWS_CMD} ec2 describe-nat-gateways \
      --filter "Name=vpc-id,Values=${VPC_ID}" --query 'NatGateways[0].NatGatewayId' --output text)

    # Add a route from 0.0.0.0/0 to the NATGW
    response=$(${AWS_CMD} ec2 create-route \
      --destination-cidr-block 0.0.0.0/0 \
      --nat-gateway-id ${NATGW_ID} --route-table-id ${RTB_ID})
  fi
  echo "      $NATGW_ID"
done

# ensure AZ commonality across Ingress and Data subnets

INGRESS_ZONES=$(${AWS_CMD} ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${INGRESS_PREFIX}*" \
  --query 'Subnets[*].AvailabilityZone' --output text | tr '[:space:]' '\n')

DATA_ZONES=$(${AWS_CMD} ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${DATA_PREFIX}*" \
  --query 'Subnets[*].AvailabilityZone' --output text | tr '[:space:]' '\n')

UNIQUE_COUNT=$(printf "$INGRESS_ZONES\n$DATA_ZONES" | sort | uniq -c | grep -c " 1 ")

if [[ "${UNIQUE_COUNT}" -ne "0" ]]; then
  echo "Ingress and Data subnets must be in the same availability zones."
  echo "-- INGRESS zones:"
  echo "${INGRESS_ZONES}"
  echo "-- DATA zones:"
  echo "${DATA_ZONES}"
  exit 1
fi
