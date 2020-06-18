variable "tfstate_bucket" {}
variable "region" {}

variable "account_id" {}
variable "account_name" {}
variable "vpc_id" {}
variable "vpc_name" {}

variable "availability_zones" { type = list(string) }
variable "subnet_id" {}
variable "public_subnet_ids" { type = list(string)}

variable "ami_prefix" {}
variable "ami_owner_id" {}
variable "instance_type" {}

# cidr list for HTTPS ingress
variable "opscenter_ingress_cidrs" { type = list(string)}

variable "sg_ops_nodes_to_cas" {}
variable "sg_bas_nodes_to_all" {}
variable "ops_additional_sg_ids" {
  type = list(string)
  default = []
}

# created by account-resources layer
variable "opscenter_profile_arn" { type = string }

variable "ssl_certificate_id" {}

variable "studio_enabled" { default = "0" }

# opscenter alert configuration
variable "alert_email_enabled" { default = "0" }
variable "alert_levels" { default = "ERROR,CRITICAL,ALERT" }
variable "alert_clusters" { default = "" }
variable "alert_email_smtp_host" { default = "" }
variable "alert_email_smtp_user" { default = "" }
variable "alert_email_smtp_pass" { default = "" }
variable "alert_email_from_addr" { default = "" }
variable "alert_email_to_addr" { default = "" }
variable "alert_email_env" { default = "" }

# optional hosted zone configuration
variable "hosted_zone_name" { default = "" }
variable "private_hosted_zone" { default = "false" }
variable "hosted_zone_record_prefix" { default = "opscenter" }

locals {
  required_ec2_tags = {
    "Name"                = "opscenter-primary"
    "Account"             = var.account_id
    "AccountName"         = var.account_name
    "VpcName"             = var.vpc_name
    "Tfstate"             = var.tfstate_bucket
    "ManagedBy"           = "terraform"
    "Region"              = var.region
    "pool"                = "opscenter"
  }
}

variable "ec2_tags"   {}
