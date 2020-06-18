output "bastion_lb_dns" {
  # grotesque hack to get around the fact that the HCL interpolation handler can't short-circuit a nonexistent resource
  value = length(var.existing_bastion_sg_id) == 0 ? join("", aws_lb.bastion-nlb.*.dns_name) : ""
}

output "bastion_sg_id" {
  # grotesque hack to get around the fact that the HCL interpolation handler can't short-circuit a nonexistent resource
  value = length(var.existing_bastion_sg_id) == 0 ? join("", aws_security_group.bastion-sg.*.id) : var.existing_bastion_sg_id
}

