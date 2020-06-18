variable "region" { type = string }
variable "account_id" { type = string }
variable "tfstate_bucket" { type = string }

variable "account_name" { type = string }
variable "vpc_name" { type = string }
variable "cluster_name" { type = string }

# salt for iam resource naming
variable "prefix" { type = string }
variable "suffix" { type = string }
