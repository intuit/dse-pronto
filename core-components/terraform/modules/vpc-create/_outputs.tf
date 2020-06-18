output "vpc_id" {
  value = aws_vpc.dse-vpc.id
}

output "vpc_cidr" {
  value = aws_vpc.dse-vpc.cidr_block
}

output "data_subnet_ids" {
  value = aws_subnet.dse-vpc-data.*.id
}

output "data_subnet_cidr_blocks" {
  value = aws_subnet.dse-vpc-data.*.cidr_block
}

output "ingress_subnet_ids" {
  value = aws_subnet.dse-vpc-ingress.*.id
}

output "ingress_subnet_cidr_blocks" {
  value = aws_subnet.dse-vpc-ingress.*.cidr_block
}
