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

module "cassandra" {
  source = "../../modules/cassandra"

  vpc_id                = data.terraform_remote_state.vpc-resources.outputs.vpc_id
  vpc_name              = var.vpc_name
  account_id            = var.account_id
  account_name          = var.account_name
  region                = var.region
  tfstate_bucket        = var.tfstate_bucket

  # cassandra cluster variables
  ami_prefix            = var.ami_prefix
  ami_owner_id          = var.ami_owner_id
  instance_type         = var.instance_type
  cassandra_profile_arn = data.terraform_remote_state.account-resources.outputs.cassandra_profile_arn
  cluster_name          = var.cluster_name
  datacenter            = var.region
  availability_zones    = var.availability_zones
  dse_nodes_per_az      = var.dse_nodes_per_az
  auto_start_dse        = var.auto_start_dse
  graph_enabled         = var.graph_enabled
  solr_enabled          = var.solr_enabled
  spark_enabled         = var.spark_enabled
  sg_ops_nodes_to_cas   = data.terraform_remote_state.vpc-resources.outputs.sg_ops_nodes_to_cas
  sg_bas_nodes_to_all   = data.terraform_remote_state.vpc-resources.outputs.bastion_sg_id
  cluster_subnet_cidrs  = data.terraform_remote_state.vpc-resources.outputs.data_subnet_cidr_blocks
  cluster_subnet_ids    = data.terraform_remote_state.vpc-resources.outputs.data_subnet_ids

  # settings for cassandra node root volume
  root_volume_type     = var.root_volume_type
  root_volume_size     = var.root_volume_size
  root_volume_iops     = var.root_volume_iops

  # this order is important: duplicate tags will be overwritten in argument order
  ec2_tags             = merge(var.account_tags, var.vpc_tags, var.cluster_tags)
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
  parameter_count=21

  # list of objects (key, value, and optional 'tier' to set a param as Advanced if it's > 4096 bytes)
  parameters = [
    {
      key   = "dc_name",
      value = var.region
    },
    {
      key   = "keyspace",
      value = var.keyspace
    },
    {
      key   = "volume_type",
      value = var.volume_type
    },
    {
      key   = "iops",
      value = var.iops
    },
    {
      key   = "data_volume_size",
      value = var.data_volume_size
    },
    {
      key   = "commitlog_size",
      value = var.commitlog_size
    },
    {
      key   = "commitlog_volume_type",
      value = var.commitlog_volume_type
    },
    {
      key   = "commitlog_iops",
      value = var.commitlog_iops
    },
    {
      key   = "number_of_stripes",
      value = var.number_of_stripes
    },
    {
      key   = "raid_level",
      value = var.raid_level
    },
    {
      key   = "raid_block_size",
      value = var.raid_block_size
    },
    {
      key   = "max_heap_size",
      value = var.max_heap_size
    },
    {
      key   = "num_tokens",
      value = var.num_tokens
    },
    {
      key   = "vpc_cassandra_subnet_cidr_blocks",
      value = join(",", data.terraform_remote_state.vpc-resources.outputs.data_subnet_cidr_blocks)
    },
    {
      key   = "vpc_cassandra_subnet_ids",
      value = join(",", data.terraform_remote_state.vpc-resources.outputs.data_subnet_ids)
    },
    {
      key   = "cassandra_seed_node_ips",
      value = join(",", module.cassandra.cassandra_seed_node_ips)
    },
    {
      # parameter store does not accept empty values, and we may not have any non-seeds
      key   = "cassandra_non_seed_node_ips",
      value = length(module.cassandra.cassandra_non_seed_node_ips) == 0 ? "null" : join(",", module.cassandra.cassandra_non_seed_node_ips)
    },
    {
      key   = "availability_zones",
      value = join(",", var.availability_zones)
    },
    {
      key   = "aio_enabled",
      value = var.aio_enabled
    },
    {
      key   = "max_queued_native_transport_requests",
      value = var.max_queued_native_transport_requests
    },
    {
      key   = "native_transport_max_threads",
      value = var.native_transport_max_threads
    }
  ]
}

###################
# additional artifacts required by bootstrap process
###################

locals {
  cluster_key = "${var.account_name}/${var.vpc_name}/${var.cluster_name}"
}

module "cassandra-tuning-changes" {
  source      = "../../modules/bucket-object"
  bucket_name = var.tfstate_bucket
  key_prefix  = "${local.cluster_key}/files/post-deploy-scripts/tuning_changes.sh"
  file_source = "${path.module}/../../modules/cassandra/files/tuning_changes.sh"

  # use specific provider for tfstate bucket, as it may not be the same as the deployment region
  providers = {
    aws = aws.tfstate
  }
}

module "bastion-ssh-keys" {
  source      = "../../modules/bucket-object"
  bucket_name = var.tfstate_bucket
  key_prefix  = "${local.cluster_key}/files/ssh/ec2-user/user-keys.yaml"
  file_source = "${path.module}/../../../../configurations/${local.cluster_key}/user-keys.yaml"

  # use specific provider for tfstate bucket, as it may not be the same as the deployment region
  providers = {
    aws = aws.tfstate
  }
}

module "jvm-options" {
  source      = "../../modules/bucket-object"
  bucket_name = var.tfstate_bucket
  key_prefix  = "${local.cluster_key}/files/cluster-configs/jvm.options"
  file_source = "${path.module}/../../../../configurations/${local.cluster_key}/cluster-configs/jvm.options"

  # use specific provider for tfstate bucket, as it may not be the same as the deployment region
  providers = {
    aws = aws.tfstate
  }
}
