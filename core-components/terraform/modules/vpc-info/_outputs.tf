output "vpc_id" {
  value = var.vpc_id
}

output "vpc_cidr" {
  value = data.aws_vpc.vpc.cidr_block
}

output "data_subnet_ids" {
  value = data.aws_subnet.data.*.id
}

output "data_subnet_cidr_blocks" {
  value = data.aws_subnet.data.*.cidr_block
}

output "ingress_subnet_ids" {
  value = data.aws_subnet.ingress.*.id
}

output "ingress_subnet_cidr_blocks" {
  value = data.aws_subnet.ingress.*.cidr_block
}
