locals {
  opscenter_eni_tags = {
    "Name"      = "opscenter-primary"
  }
}

data "template_file" "opscenter-init" {
  template = file("${path.module}/scripts/opscenter-init.tpl")

  vars             = {
    bucket         = var.tfstate_bucket
    account        = var.account_id
    region         = var.region
    studio_enabled = var.studio_enabled
    account_name   = var.account_name
    vpc_name       = var.vpc_name

    # opscenter alert configuration
    alert_email_enabled   = var.alert_email_enabled
    alert_levels          = var.alert_levels
    alert_clusters        = var.alert_clusters
    alert_email_smtp_host = var.alert_email_smtp_host
    alert_email_smtp_user = var.alert_email_smtp_user
    alert_email_smtp_pass = var.alert_email_smtp_pass
    alert_email_from_addr = var.alert_email_from_addr
    alert_email_to_addr   = var.alert_email_to_addr
    alert_email_env       = var.alert_email_env
  }
}

data "template_cloudinit_config" "opscenter" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content      = file("${path.module}/../../../../configurations/${var.account_name}/${var.vpc_name}/opscenter-resources/user-keys.yaml")
  }

  part {
    filename     = "opscenter-init.sh"
    content_type = "text/x-shellscript"
    content      = data.template_file.opscenter-init.rendered
  }
}

resource "aws_network_interface" "opscenter-eni" {
  subnet_id = var.subnet_id

  security_groups = [
    aws_security_group.opscenter-bastion-access.id, # SSH
    aws_security_group.ops_elb_to_nodes.id,
    var.sg_ops_nodes_to_cas,
    aws_security_group.ops_addl_inbound.id
  ]

  tags = merge(var.ec2_tags, local.required_ec2_tags, local.opscenter_eni_tags)
}

data "aws_subnet" "selected" {
  id = "${var.subnet_id}"
}

resource "aws_launch_configuration" "opscenter-config" {
  name_prefix                 = "opscenter-"
  placement_tenancy           = "default"
  associate_public_ip_address = false
  image_id                    = data.aws_ami.opscenter.id
  instance_type               = var.instance_type

  security_groups = [
    aws_security_group.opscenter-bastion-access.id, # SSH
    aws_security_group.ops_elb_to_nodes.id,
    var.sg_ops_nodes_to_cas,
  ]

  ebs_optimized        = true
  iam_instance_profile = var.opscenter_profile_arn
  user_data            = data.template_cloudinit_config.opscenter.rendered

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "opscenter-asg" {
  depends_on                = [aws_launch_configuration.opscenter-config]
  name                      = "asg-opscenter"
  max_size                  = 2
  min_size                  = 1
  health_check_grace_period = 600
  health_check_type         = "EC2"
  desired_capacity          = "1"
  launch_configuration      = aws_launch_configuration.opscenter-config.name
  vpc_zone_identifier       = [var.subnet_id]
  target_group_arns         = [aws_lb_target_group.opscenter-targets.id, aws_lb_target_group.studio-targets.id]

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "opscenter-primary"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmiName"
    value               = data.aws_ami.opscenter.name
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = merge(local.required_ec2_tags, var.ec2_tags)

    content {
      key = tag.key
      value = tag.value
      propagate_at_launch = true
    }
  }
}
