data "terraform_remote_state" "account-resources" {
  backend = "s3"
  config = {
    role_arn = var.role_arn
    bucket   = var.tfstate_bucket
    key      = "${var.account_name}/account-resources/account.tfstate"
    region   = var.tfstate_region
  }
}

data "terraform_remote_state" "vpc-resources" {
  backend = "s3"
  config = {
    role_arn = var.role_arn
    bucket   = var.tfstate_bucket
    key      = "${var.account_name}/${var.vpc_name}/vpc-resources/vpc.tfstate"
    region   = var.tfstate_region
  }
}

module "opscenter" {
  source = "../../modules/opscenter"

  account_id            = var.account_id
  account_name          = var.account_name
  vpc_id                = data.terraform_remote_state.vpc-resources.outputs.vpc_id
  vpc_name              = var.vpc_name
  region                = var.region
  tfstate_bucket        = var.tfstate_bucket
  availability_zones    = var.availability_zones

  ssl_certificate_id    = var.ssl_certificate_id

  subnet_id             = element(data.terraform_remote_state.vpc-resources.outputs.data_subnet_ids,0)
  public_subnet_ids     = data.terraform_remote_state.vpc-resources.outputs.ingress_subnet_ids
  ami_owner_id          = var.ami_owner_id
  ami_prefix            = var.ami_opscenter_prefix
  instance_type         = var.instance_type
  opscenter_profile_arn = data.terraform_remote_state.account-resources.outputs.opscenter_profile_arn
  studio_enabled        = var.studio_enabled

  # security groups
  sg_ops_nodes_to_cas     = data.terraform_remote_state.vpc-resources.outputs.sg_ops_nodes_to_cas
  sg_bas_nodes_to_all     = data.terraform_remote_state.vpc-resources.outputs.bastion_sg_id
  ops_additional_sg_ids   = var.ops_additional_sg_ids
  opscenter_ingress_cidrs = var.ingress_cidrs

  # opscenter alert configuration
  alert_email_enabled   = var.alert_email_enabled
  alert_levels          = var.alert_levels
  alert_clusters        = var.alert_clusters
  alert_email_smtp_host = var.alert_email_smtp_host
  alert_email_smtp_user = var.alert_email_smtp_user
  alert_email_smtp_pass = var.alert_email_smtp_pass
  alert_email_from_addr = var.alert_email_from_addr
  alert_email_to_addr   = var.alert_email_to_addr
  alert_email_env       = var.alert_email_env
  
  # this order is important: duplicate tags will be overwritten in argument order
  ec2_tags             = merge(var.account_tags, var.vpc_tags, var.opscenter_tags)

  hosted_zone_name      = var.hosted_zone_name
  private_hosted_zone   = var.private_hosted_zone
  hosted_zone_record_prefix = var.hosted_zone_record_prefix
}

###################
# vars required outside terraform -> Parameter Store
###################

module "parameter-store" {
  source = "../../modules/parameter-store"

  account_name = var.account_name
  vpc_name     = var.vpc_name
  cluster_name = var.cluster_name

  # remember to update this when adding/removing parameters from the list below!
  # dynamic list sizes can screw with terraform (it's a known bug) and result in the error:
  #   aws_ssm_parameter.parameter: value of 'count' cannot be computed
  parameter_count=2

  # list of objects (key, value, and optional 'tier' to set a param as Advanced if it's > 4096 bytes)
  parameters = [
    {
      key   = "opscenter_primary_private_ip",
      value = module.opscenter.opscenter_primary_private_ip
    },
    {
      key   = "opscenter_storage_cluster",
      value = var.opscenter_storage_cluster
    }
  ]
}
