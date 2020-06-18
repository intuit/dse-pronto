#!/bin/bash
set -x
source ./register_cluster_func.sh

region=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')

bucket=$1
cluster_to_register=$2
vpc_name=$3
account_name=$4

if [[ ! -z "$cluster_to_register" ]] && [[ ! -z "$bucket" ]] && [[ ! -z "$account_name" ]] && [[ ! -z "$vpc_name" ]]; then
  register_with_opscenter ${bucket} ${cluster_to_register} ${vpc_name} ${account_name}
else
  echo "cluster info not provided"
fi

