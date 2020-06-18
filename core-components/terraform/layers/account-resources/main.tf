module "iam-resources" {
  source = "../../modules/iam-resources"

  region         = var.region
  tfstate_bucket = var.tfstate_bucket
  account_id     = var.account_id
  account_name   = var.account_name
  vpc_name       = var.vpc_name
  cluster_name   = var.cluster_name

  prefix         = var.iam_resource_prefix
  suffix         = var.iam_resource_suffix
}