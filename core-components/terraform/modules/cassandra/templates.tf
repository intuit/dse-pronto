data "template_file" "dse-init" {
  template = file("${path.module}/files/dse-init.tpl")

  vars = {
    dc_name        = var.datacenter
    auto_start_dse = var.auto_start_dse
    region         = var.region
    ssh_bucket     = var.tfstate_bucket
    ssh_prefix     = "${local.cluster_key}/files/ssh/ec2-user/user-keys.yaml"
    graph_enabled  = var.graph_enabled
    solr_enabled   = var.solr_enabled
    spark_enabled  = var.spark_enabled
    ec2_tag_map    = jsonencode(merge(var.ec2_tags, local.required_ec2_tags))
  }
}

data "template_cloudinit_config" "cassandra" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content = file(
      "${path.module}/../../../../configurations/${local.cluster_key}/user-keys.yaml",
    )
  }

  part {
    filename     = "dse-init.sh"
    content_type = "text/x-shellscript"
    content      = data.template_file.dse-init.rendered
  }
}

