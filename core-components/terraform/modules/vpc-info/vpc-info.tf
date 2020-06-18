data "aws_vpc" "vpc" {
  id = var.vpc_id
}

#############
# The data sources in this module will be gathered if terraform_managed_vpc is
# set to false, and an existing vpc_id is provided.
#############

data "aws_subnet_ids" "ingress_subnet_ids" {
  vpc_id = var.vpc_id
  tags   = {
    Name = "${var.ingress_subnet_tag_prefix}*"
  }
}

data "aws_subnet_ids" "data_subnet_ids" {
  vpc_id = var.vpc_id
  tags   = {
    Name = "${var.data_subnet_tag_prefix}*"
  }
}

#########
# data subnets
#########

data "aws_subnet" "data" {
  count = length(data.aws_subnet_ids.data_subnet_ids.ids)
  id    = tolist(data.aws_subnet_ids.data_subnet_ids.ids)[count.index]
}

#########
# ingress subnets
#########

data "aws_subnet" "ingress" {
  count = length(data.aws_subnet_ids.ingress_subnet_ids.ids)
  id    = tolist(data.aws_subnet_ids.ingress_subnet_ids.ids)[count.index]
}
