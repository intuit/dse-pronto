variable "region" { type = string }
variable "tfstate_bucket" { type = string }
variable "account_id" { type = string }
variable "account_name" { type = string }
variable "vpc_name" { type = string }
variable "cluster_name" { type = string }

# salt for iam resource naming; default to empty string
variable "iam_resource_prefix" { default = "" }
variable "iam_resource_suffix" { default = "" }

variable "profile" {}
variable "ami_owner_id" {}
variable "tfstate_region" {}
variable "role_arn" {}

variable "account_tags" { default = {} }