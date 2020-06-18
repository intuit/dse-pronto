data "terraform_remote_state" "account-resources" {
  backend = "s3"
  config = {
    role_arn = var.role_arn
    bucket   = var.tfstate_bucket
    key      = "${var.account_name}/account-resources/account.tfstate"
    region   = var.tfstate_region
  }
}

###################
# deploy resources shared across vpc
###################

module "vpc-shared" {
  source = "../../modules/vpc-shared"

  vpc_id     = module.vpc.vpc_id
  region     = var.region
  account_id = var.account_id
}

###################
# deploy 1 bastion per vpc
###################

module "bastion" {
  source                = "../../modules/bastion"
  region                = var.region
  tfstate_bucket        = var.tfstate_bucket
  account_id            = var.account_id
  account_name          = var.account_name
  vpc_id                = module.vpc.vpc_id
  vpc_name              = var.vpc_name
  vpc_cidr              = module.vpc.vpc_cidr

  ingress_sg_prefix     = "bastion-ingress"
  ingress_sg_port       = 22
  ingress_sg_protocol   = "tcp"
  ami_prefix            = var.bastion_ami_prefix
  bastion_role_arn      = data.terraform_remote_state.account-resources.outputs.bastion_profile_arn
  ingress_subnet_ids    = module.vpc.ingress_subnet_ids
  data_subnet_ids       = module.vpc.data_subnet_ids

  # cidr list for SSH ingress
  bastion_ingress_cidrs = var.ingress_cidrs

  # if this is provided, do no work; output this variable to tfstate and exit
  existing_bastion_sg_id = var.existing_bastion_sg_id

  # this order is important: duplicate tags will be overwritten in argument order
  ec2_tags             = merge(var.account_tags, var.vpc_tags)
}

###################
# upload ssh keys to tfstate bucket
###################

locals {
  bastion_key = "${var.account_name}/${var.vpc_name}/vpc-resources"
}

module "bastion-ssh-keys" {
  source      = "../../modules/bucket-object"
  bucket_name = var.tfstate_bucket
  key_prefix  = "${local.bastion_key}/files/ssh/ec2-user/user-keys.yaml"
  file_source = "${path.module}/../../../../configurations/${local.bastion_key}/user-keys.yaml"

  # use specific provider for tfstate bucket, as it may not be the same as the deployment region
  providers = {
    aws = aws.tfstate
  }
}

###################
# vars required outside terraform -> Parameter Store
###################

module "parameter-store" {
  source = "../../modules/parameter-store"

  cluster_name = var.cluster_name
  vpc_name     = var.vpc_name
  account_name = var.account_name

  # remember to update this when adding/removing parameters from the list below!
  # dynamic list sizes can screw with terraform (it's a known bug) and result in the error:
  #   aws_ssm_parameter.parameter: value of 'count' cannot be computed
  parameter_count=1

  parameters = [
    {
      # storing vpc_id in Parameter Store, in order to access it from
      # non-terraform scripts (without having to examine tfstate)
      key   = "vpc_id",
      value = module.vpc.vpc_id
    }
  ]
}
