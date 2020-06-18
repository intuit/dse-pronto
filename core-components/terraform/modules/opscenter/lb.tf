locals {
  opscenter_lb_tags = {
    "Name"      = "elb-ops-${var.account_id}"
  }
}

resource "aws_lb" "opscenter" {
  name = "lb-ops-${var.account_id}"

  load_balancer_type = "application"
  internal           = false

  security_groups = [
    aws_security_group.ops_elb_443.id,
    aws_security_group.ops_elb_9091.id
  ]

  # TODO limit to two? Third will always be empty.
  subnets = var.public_subnet_ids

  # TODO access logs to S3
  tags = merge(var.ec2_tags, local.required_ec2_tags, local.opscenter_lb_tags)
}

resource "aws_lb_target_group" "opscenter-targets" {
  port        = 8443
  protocol    = "HTTPS"
  vpc_id      = var.vpc_id

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    protocol            = "HTTPS"
    path                = "/opscenter/login.html"
    interval            = 30
  }
}

resource "aws_lb_target_group" "studio-targets" {
  port        = 9091
  protocol    = "HTTP"
  vpc_id      = var.vpc_id

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    path                = "/"
    interval            = 30
  }
}

resource "aws_lb_listener" "opscenter-listener" {
  load_balancer_arn = aws_lb.opscenter.id
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.ssl_certificate_id

  default_action {
    target_group_arn = aws_lb_target_group.opscenter-targets.id
    type             = "forward"
  }
}

resource "aws_lb_listener" "studio-listener" {
  load_balancer_arn = aws_lb.opscenter.id
  port              = "9091"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.studio-targets.id
    type             = "forward"
  }
}
