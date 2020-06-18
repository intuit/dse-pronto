# new vpc
variable "vpc_cidr" {}
variable "vpc_name" {}
variable "region" {}
variable "azs" { type = list(string) }
variable "ingress_subnets" { type = list(string) }
variable "data_subnets" { type = list(string) }

variable "ingress_subnet_tag_prefix" {}
variable "data_subnet_tag_prefix" {}