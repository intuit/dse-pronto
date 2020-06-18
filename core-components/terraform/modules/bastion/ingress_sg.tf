#############################################
# OIP ingress-sg pattern
#############################################

resource "aws_security_group" "bastion-ssh-ingress" {
  count                  = length(var.existing_bastion_sg_id) == 0 ? 1 : 0
  name_prefix            = "${var.ingress_sg_prefix}-${var.ingress_sg_protocol}-${var.ingress_sg_port}-"
  description            = "Allows ingress from configured CIDR blocks"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  ingress {
    from_port = var.ingress_sg_port
    to_port   = var.ingress_sg_port
    protocol  = var.ingress_sg_protocol
    cidr_blocks = concat(var.bastion_ingress_cidrs, tolist([var.vpc_cidr]))
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(map("Name", "${var.ingress_sg_prefix}-${var.ingress_sg_protocol}-${var.ingress_sg_port}"), var.ec2_tags, local.required_ec2_tags)
}

#############################################
# Reference group for bastion nodes
#############################################

resource "aws_security_group" "bastion-sg" {
  count                  = length(var.existing_bastion_sg_id) == 0 ? 1 : 0
  name_prefix            = "bastion-elb-nodes-"
  description            = "Ref group for use in inbound rules, to allow ssh from bastion nodes"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(map("Name", "bastion-elb-nodes"), var.ec2_tags, local.required_ec2_tags)
}

