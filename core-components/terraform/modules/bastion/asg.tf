#############################################
# LC and ASG for bastion nodes
#############################################

data "aws_ami" "bastion-ami" {
  count       = length(var.existing_bastion_sg_id) == 0 ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["${var.ami_prefix}*"]
  }
}

resource "aws_launch_configuration" "bastion-lc" {
  count                       = length(var.existing_bastion_sg_id) == 0 ? 1 : 0
  name_prefix                 = "bastion-lc-"
  image_id                    = data.aws_ami.bastion-ami[0].id
  instance_type               = var.instance_type
  placement_tenancy           = "default"
  associate_public_ip_address = true

  security_groups = [
    aws_security_group.bastion-sg[0].id,
    aws_security_group.bastion-ssh-ingress[0].id,
  ]

  user_data            = data.template_cloudinit_config.bastion-init[0].rendered
  iam_instance_profile = var.bastion_role_arn

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "bastion-asg" {
  count                     = length(var.existing_bastion_sg_id) == 0 ? 1 : 0
  depends_on                = [aws_launch_configuration.bastion-lc]
  name_prefix               = "bastion-asg-"
  max_size                  = 1
  min_size                  = 1
  health_check_grace_period = 600
  health_check_type         = "EC2"
  desired_capacity          = 1
  launch_configuration      = aws_launch_configuration.bastion-lc[0].name
  vpc_zone_identifier       = var.ingress_subnet_ids
  target_group_arns         = [aws_lb_target_group.bastion-targets[0].id]

  lifecycle {
    create_before_destroy = true
  }


  tag {
    key                 = "Name"
    value               = "bastion"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = merge(var.ec2_tags, local.required_ec2_tags)

    content {
      key = tag.key
      value = tag.value
      propagate_at_launch = true
    }
  }
}

