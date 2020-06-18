resource "aws_ssm_parameter" "parameter" {
  count = var.parameter_count
  type  = "String"
  name  = format("/dse/%s/%s/%s/%s", var.account_name, var.vpc_name, var.cluster_name, lookup(var.parameters[count.index], "key"))
  value = lookup(var.parameters[count.index], "value")
  tier  = lookup(var.parameters[count.index], "tier", "Standard")
  overwrite = "true"
}
