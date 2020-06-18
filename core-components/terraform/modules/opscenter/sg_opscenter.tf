locals {
  opscenter_bastion_access_tags = {
    "Name"        = "opscenter-bastion-access"
  }

  ops_elb_443_tags = {
    "Name"         = "sg-ops-https-to-elb"
  }

  ops_elb_9091_tags = {
    "Name"         = "sg-ops-studio-to-elb"
  }

  ops_elb_to_nodes_tags = {
    "Name"         = "sg-ops-elb-to-nodes"
  }

  ops_addl_inbound_tags = {
    "Name"         = "sg-ops-additional"
  }
}

resource "aws_security_group" "opscenter-bastion-access" {
  name_prefix    = "opscenter-bastion-access-"
  description    = "Allows SSH access via bastion"
  vpc_id         = var.vpc_id
  revoke_rules_on_delete = true

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.sg_bas_nodes_to_all]
  }

  egress {
    from_port    = 0
    to_port      = 0
    protocol     = "-1"
    cidr_blocks  = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.ec2_tags, local.required_ec2_tags, local.opscenter_bastion_access_tags)
}

resource "aws_security_group" "ops_elb_443" {
  name        = "sg_ops-https-to-elb-${var.account_id}"
  description = "Allow inbound access from configured CIDRs on HTTPS port"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks  = var.opscenter_ingress_cidrs
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

  tags = merge(var.ec2_tags, local.required_ec2_tags, local.ops_elb_443_tags)
}

resource "aws_security_group" "ops_elb_9091" {
  name        = "sg_ops-studio-to-elb-${var.account_id}"
  description = "Allow inbound access from configured CIDRs on DataStax Studio port"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 9091
    to_port     = 9091
    protocol    = "tcp"
    cidr_blocks  = var.opscenter_ingress_cidrs
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

  tags = merge(var.ec2_tags, local.required_ec2_tags, local.ops_elb_9091_tags)
}


resource "aws_security_group" "ops_elb_to_nodes" {
  name        = "sg_ops-elb-to-nodes-${var.account_id}"
  description = "Allows inbound HTTPS access from opscenter elb"
  vpc_id      = var.vpc_id

  # TODO tighten
  ingress {
    from_port       = 8443
    to_port         = 8443
    protocol        = "tcp"
    security_groups = [aws_security_group.ops_elb_443.id]
  }
  ingress {
    from_port       = 9091
    to_port         = 9091
    protocol        = "tcp"
    security_groups = [aws_security_group.ops_elb_9091.id]
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

  tags = merge(var.ec2_tags, local.required_ec2_tags, local.ops_elb_9091_tags)

}

############################
# separate security group to allow any extra ingress from a list of other SGs
############################

resource "aws_security_group" "ops_addl_inbound" {
  name        = "sg_ops-additional-${var.account_id}"
  description = "Allows inbound HTTPS access from provided SGs"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.ec2_tags, local.required_ec2_tags, local.ops_addl_inbound_tags)
}

# rule for port 8443
resource "aws_security_group_rule" "ops_addl_8443" {
  count                    = length(var.ops_additional_sg_ids)
  security_group_id        = aws_security_group.ops_addl_inbound.id
  source_security_group_id = element(var.ops_additional_sg_ids, count.index)

  type      = "ingress"
  from_port = 8443
  to_port   = 8443
  protocol  = "tcp"
}

# rule for port 9091
resource "aws_security_group_rule" "ops_addl_9091" {
  count                    = length(var.ops_additional_sg_ids)
  security_group_id        = aws_security_group.ops_addl_inbound.id
  source_security_group_id = element(var.ops_additional_sg_ids, count.index)

  type      = "ingress"
  from_port = 9091
  to_port   = 9091
  protocol  = "tcp"
}
