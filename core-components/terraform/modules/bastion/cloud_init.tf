#############################################
# User data (cloud-init) from template
#############################################

data "template_file" "bastion-tpl" {
  count    = length(var.existing_bastion_sg_id) == 0 ? 1 : 0
  template = file("${path.module}/data/bastion-init.tpl")
  vars = {
    account_id = var.account_id
    region     = var.region
    ssh_bucket = var.tfstate_bucket
    ssh_prefix = "${var.account_name}/${var.vpc_name}/vpc-resources/files/ssh/ec2-user/user-keys.yaml"
  }
}

data "template_cloudinit_config" "bastion-init" {
  count         = length(var.existing_bastion_sg_id) == 0 ? 1 : 0
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content = file(
      "${path.module}/../../../../configurations/${var.account_name}/${var.vpc_name}/vpc-resources/user-keys.yaml",
    )
  }
  part {
    filename     = "bastion-init.sh"
    content_type = "text/x-shellscript"
    content      = data.template_file.bastion-tpl[0].rendered
  }
}

