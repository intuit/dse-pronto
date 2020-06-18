variable "tfstate_bucket" {}
variable "tfstate_region" {}
variable "profile" {}
variable "region" {}

variable "account_name" {}
variable "vpc_name" {}
variable "cluster_name" {}

variable "ami_owner_id" {}
variable "ami_opscenter_prefix" { default = "dse-opscenter" }
variable "instance_type" { default = "m5.xlarge" }

variable "account_id" {}
variable "availability_zones" { type = list(string) }

variable "role_arn" {}

variable "ops_additional_sg_ids" {
  type = list(string)
  default = []
}
variable "ssl_certificate_id" {}
variable "studio_enabled" { default = "0" }

# cidr list for HTTPS ingress
variable "ingress_cidrs" { type = list(string) }

variable "opscenter_storage_cluster" {}

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

# tags
variable "account_tags" { default = {} }
variable "vpc_tags" { default = {} }
variable "opscenter_tags" { default = {} }
