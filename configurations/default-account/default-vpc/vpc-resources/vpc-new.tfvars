
# if TERRAFORM_MANAGED_VPC in variables.yaml is set to "true", this file will be used.
#
# false = no vpc will be created, and the following vars must be set in order to locate the existing vpc:
#    - vpc_id
#    - ingress_subnet_tag_prefix (default "Ingress", used for bastion)
#    - data_subnet_tag_prefix (default "Data", used for C* nodes)
#
# true = vpc will be created from scratch, and the following vars must be set:
#    - vpc_cidr (full vpc CIDR)
#    - vpc_prefix (name prefix for all vpc resources)
#    - azs (list of availability zones)
#    - ingress_subnets (list of CIDRs for ingress subnets, used for bastion)
#    - data_subnets (list of CIDRs for data subnets, used for C* nodes)

# settings for NEW vpc
vpc_cidr                  = "172.0.0.0/16"
azs                       = ["a", "b", "c"]
ingress_subnets           = ["172.0.10.0/24", "172.0.11.0/24", "172.0.12.0/24"]
data_subnets              = ["172.0.20.0/24", "172.0.21.0/24", "172.0.22.0/24"]
