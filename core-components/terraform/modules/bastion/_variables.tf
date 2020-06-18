variable "region" {}
variable "tfstate_bucket" {}
variable "account_id" {}
variable "account_name" {}

variable "vpc_id" { type = string }
variable "vpc_name" {}
variable "vpc_cidr" {}

variable "ami_prefix" {
  description = "Baseline AMI to use."
}
variable "instance_type" {
  description = "The instance type for bastion nodes."
  default     = "t3.micro"
}

variable "data_subnet_ids" { type = list(string) }
variable "ingress_subnet_ids" { type = list(string) }
variable "ingress_sg_port" { default = 22 }
variable "ingress_sg_protocol" { default = "tcp"}
variable "ingress_sg_prefix" { default = "bastion-ssh-ingress" }

# created by account-resources layer
variable "bastion_role_arn" { type = string }

# cidr list for SSH ingress
variable "bastion_ingress_cidrs" { type = list(string) }

# if this is provided, do no work; output this variable to tfstate and exit
variable "existing_bastion_sg_id" { default = "" }

# tags
variable "ec2_tags" {}

locals {
  required_ec2_tags = {
    "Role" = "bastion"
  }
}

