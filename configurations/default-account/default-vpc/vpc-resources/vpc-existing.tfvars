
# if TERRAFORM_MANAGED_VPC in variables.yaml is set to "false", this file will be used.
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

# settings for EXISTING vpc
vpc_id                    = "<<< YOUR_VPC_ID_HERE >>>"
ingress_subnet_tag_prefix = "Ingress"
data_subnet_tag_prefix    = "Data"
