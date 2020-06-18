#############################################
# NLB for bastion nodes
#############################################

locals {
  bastion_lb_tags = {
    "Region" = "${var.region}"
  }
}
resource "aws_lb" "bastion-nlb" {
  count       = length(var.existing_bastion_sg_id) == 0 ? 1 : 0
  name_prefix = "bast-"

  # ALBs don't support TCP (22), use NLB instead
  load_balancer_type = "network"

  internal = false
  subnets  = var.ingress_subnet_ids

  enable_cross_zone_load_balancing = true

  tags = merge(map("Name", "bastion-lb"), var.ec2_tags, local.required_ec2_tags, local.bastion_lb_tags)
}

resource "aws_lb_target_group" "bastion-targets" {
  count       = length(var.existing_bastion_sg_id) == 0 ? 1 : 0
  name_prefix = "bast-"
  port        = 22
  protocol    = "TCP"
  vpc_id      = var.vpc_id

  # stickiness doesn't work for NLB, but terraform won't let us disable it; therefore, empty list
}

resource "aws_lb_listener" "bastion-listener" {
  count             = length(var.existing_bastion_sg_id) == 0 ? 1 : 0
  load_balancer_arn = aws_lb.bastion-nlb[0].id
  port              = "22"
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.bastion-targets[0].id
    type             = "forward"
  }
}

