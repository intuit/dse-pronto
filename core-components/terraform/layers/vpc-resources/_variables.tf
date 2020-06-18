###################
# these are common vars; vpc-info.tf and vpc-create.tf contain their own var definitions
###################

variable "region" {}
variable "tfstate_region" {}
variable "role_arn" {}
variable "profile" {}
variable "ami_owner_id" {}

# for vpc-info/vpc-create module (either)
variable "ingress_subnet_tag_prefix" { default = "Ingress" }
variable "data_subnet_tag_prefix" { default = "Data" }

# for parameter-store module
variable "cluster_name" { type = string }
variable "vpc_name" { type = string }
variable "account_name" { type = string }

# for bastion module
variable "account_id" { type = string }
variable "tfstate_bucket" { type = string }
variable "bastion_ami_prefix" { default = "amzn2-ami-hvm-2.0" }
variable "ingress_cidrs" { type = list }
variable "existing_bastion_sg_id" { default = "" }
variable "vpc_tags" { default = {} }
variable "account_tags" { default = {} }
