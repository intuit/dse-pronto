output "opscenter_elb" {
  value = aws_lb.opscenter.dns_name
}

output "opscenter_primary_private_ip" {
  value = aws_network_interface.opscenter-eni.private_ip
}
