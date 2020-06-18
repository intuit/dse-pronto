output "cassandra_seed_node_ips" {
  value = aws_network_interface.cas-seed-eni.*.private_ip
}

output "cassandra_non_seed_node_ips" {
  value = aws_network_interface.cas-non-seed-eni.*.private_ip
}

output "sg_cas_client_access" {
  value = aws_security_group.cas-client-access.id
}

output "sg_cas_internode" {
  value = aws_security_group.cas-internode.id
}

output "cassandra_asgs" {
  value = [concat(
    aws_autoscaling_group.cassandra-seed-node.*.name,
    aws_autoscaling_group.cassandra-non-seed-node.*.name,
  )]
}

