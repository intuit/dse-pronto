output "bastion_profile_arn" {
  value = module.iam-resources.bastion_profile_arn
}

output "cassandra_profile_arn" {
  value = module.iam-resources.cassandra_profile_arn
}

output "opscenter_profile_arn" {
  value = module.iam-resources.opscenter_profile_arn
}
