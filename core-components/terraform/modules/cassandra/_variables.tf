variable "tfstate_bucket" {}
variable "region" {}
variable "account_name" {}
variable "vpc_name" {}
variable "cluster_name" {}

locals {
  cluster_key = "${var.account_name}/${var.vpc_name}/${var.cluster_name}"
}

locals {
  required_ec2_tags = {
    "Account"     = "${var.account_id}",
    "AccountName" = "${var.account_name}",
    "VpcName"     = "${var.vpc_name}",
    "ClusterName" = "${var.cluster_name}",
    "Tfstate"     = "${var.tfstate_bucket}",
    "ManagedBy"   = "terraform",
    "Region"      = "${var.region}"
  }
}

variable "ami_owner_id" {}
variable "ami_prefix" {}
variable "instance_type" {}
variable "account_id" {}
variable "availability_zones" { type = list(string) }
variable "vpc_id" {}
variable "datacenter" {}

variable "sg_ops_nodes_to_cas" {}
variable "sg_bas_nodes_to_all" {}

variable "dse_nodes_per_az" {}

variable "cluster_subnet_cidrs" { type = list(string) }
variable "cluster_subnet_ids" { type = list(string) }

variable "graph_enabled" { default = 0 }
variable "solr_enabled" { default = 0 }
variable "spark_enabled" { default = 0 }
variable "auto_start_dse" {}

# created by account-resources layer
variable "cassandra_profile_arn" { type = string }

# settings for cassandra node root volume
variable "root_volume_type" {}
variable "root_volume_size" {}
variable "root_volume_iops" {}

# tags
variable "ec2_tags"   {}
