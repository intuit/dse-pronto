# for vpc-create module (new vpc)
variable "vpc_cidr" {}
variable "data_subnets" { type = list(string) }
variable "ingress_subnets" { type = list(string) }
variable "azs" { type = list(string) }

module "vpc" {
  source = "../../modules/vpc-create"

  vpc_cidr         = var.vpc_cidr
  vpc_name         = var.vpc_name
  region           = var.region
  azs              = var.azs
  ingress_subnets  = var.ingress_subnets
  data_subnets     = var.data_subnets

  ingress_subnet_tag_prefix = var.ingress_subnet_tag_prefix
  data_subnet_tag_prefix    = var.data_subnet_tag_prefix
}
