###################
# additional scripts required by bootstrap process can be defined in
# the cluster-specific configuration profile, and will be copied to the
# node and executed by bootstrap.sh
###################

locals {
  cluster_configs = "${path.module}/../../../../configurations/${local.cluster_key}/cluster-configs"
  key_prefix      = "${local.cluster_key}/files"
}

resource "aws_s3_bucket_object" "post-deploy-scripts" {
  for_each = fileset(local.cluster_configs, "post-deploy-scripts/*.sh")
  bucket   = var.tfstate_bucket
  key      = "${local.key_prefix}/${each.value}"
  source   = "${local.cluster_configs}/${each.value}"
  etag     = filemd5("${local.cluster_configs}/${each.value}")
}
