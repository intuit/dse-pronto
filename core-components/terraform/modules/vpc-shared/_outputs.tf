output "sg_ops_nodes_to_cas" {
  description = "Security group to be used by cassandra nodes to connect to opscenter"
  value = aws_security_group.ops_to_cas.id
}
