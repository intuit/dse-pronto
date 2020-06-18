output "vpc_id" {
  value = module.vpc.vpc_id
}

output "data_subnet_ids" {
  value = module.vpc.data_subnet_ids
}

output "data_subnet_cidr_blocks" {
  value = module.vpc.data_subnet_cidr_blocks
}

output "ingress_subnet_ids" {
  value = module.vpc.ingress_subnet_ids
}

output "ingress_subnet_cidr_blocks" {
  value = module.vpc.ingress_subnet_cidr_blocks
}

output "bastion_lb_dns" {
  value = module.bastion.bastion_lb_dns
}

output "bastion_sg_id" {
  value = module.bastion.bastion_sg_id
}

output "sg_ops_nodes_to_cas" {
  value = module.vpc-shared.sg_ops_nodes_to_cas
}
