resource "aws_security_group" "cas-internode" {
  name_prefix            = "cas-internode-${var.cluster_name}-"
  description            = "Allows cassandra nodes to talk to one another"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  ingress {
    from_port = 7000
    to_port   = 7001
    protocol  = "tcp"
    self      = true
  }
  ingress {
    from_port = 8609
    to_port   = 8609
    protocol  = "tcp"
    self      = true
  }
  ingress {
    from_port = 7198
    to_port   = 7199
    protocol  = "tcp"
    self      = true
  }
  ingress {
    from_port = 9042
    to_port   = 9042
    protocol  = "tcp"
    self      = true
  }
  ingress {
    from_port = 9142
    to_port   = 9142
    protocol  = "tcp"
    self      = true
  }
  ingress {
    from_port = 9160
    to_port   = 9161
    protocol  = "tcp"
    self      = true
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

  tags = merge(map("Name", "cas-internode-${var.cluster_name}"), var.ec2_tags, local.required_ec2_tags)
}

resource "aws_security_group" "cas-client-access" {
  name_prefix            = "cas-client-access-${var.cluster_name}-"
  description            = "Allows inbound access to cassandra clients"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  # this SG is created when Terraform applies the cassandra module, but it has no ingress rules yet.
  # those can be added later, when the clients are determined.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(map("Name", "cas-client-access-${var.cluster_name}"), var.ec2_tags, local.required_ec2_tags)
}

resource "aws_security_group" "cas-bastion-access" {
  name_prefix            = "cas-bastion-access-${var.cluster_name}-"
  description            = "Allows SSH access via bastion"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.sg_bas_nodes_to_all]
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

  tags = merge(map("Name", "cas-bastion-access-${var.cluster_name}"), var.ec2_tags, local.required_ec2_tags)
}

