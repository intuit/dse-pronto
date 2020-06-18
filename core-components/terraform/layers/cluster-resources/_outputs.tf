output "sg_cas_internode" {
  value = module.cassandra.sg_cas_internode
}

output "sg_cas_client_access" {
  value = module.cassandra.sg_cas_client_access
}

output "cluster_name" {
  value = var.cluster_name
}
