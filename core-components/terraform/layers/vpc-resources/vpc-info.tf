variable "vpc_id" {}

module "vpc" {
  source = "../../modules/vpc-info"

  vpc_id = var.vpc_id

  ingress_subnet_tag_prefix = var.ingress_subnet_tag_prefix
  data_subnet_tag_prefix    = var.data_subnet_tag_prefix
}
