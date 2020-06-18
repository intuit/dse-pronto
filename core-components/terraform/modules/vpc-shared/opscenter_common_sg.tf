# a single copy of this SG should be created for the vpc and shared across all clusters
resource "aws_security_group" "ops_to_cas" {
  name           = "sg_ops-nodes-to-cas-${var.account_id}"
  description    = "Allows inbound opscenter management access for Cassandra nodes"
  vpc_id         = var.vpc_id

  ingress {
    # JMX Monitoring port on node
    from_port    = 7199
    to_port      = 7199
    protocol     = "tcp"
    self         = true
  }
  ingress {
    # The native transport port for the cluster configured in native_transport_port in cassandra.yaml.
    from_port    = 9042
    to_port      = 9042
    protocol     = "tcp"
    self         = true
  }
  ingress {
    from_port    = 9142
    to_port      = 9142
    protocol     = "tcp"
    self         = true
  }
  ingress {
    from_port    = 61620
    to_port      = 61621
    protocol     = "tcp"
    self         = true
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

  tags           = {
    Name         = "sg-ops-nodes-to-cas"
    managedBy    = "Terraform"
    account      = var.account_id
    region       = var.region
    pool         = "opscenter"
  }
}
