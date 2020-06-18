# opscenter variables
instance_type             = "m5.xlarge"
availability_zones        = ["a", "b", "c"]
opscenter_storage_cluster = "<<< YOUR_STORAGE_CLUSTER_NAME_HERE >>>"
ssl_certificate_id        = "<<< YOUR_SSL_CERT_ARN_HERE >>>"
studio_enabled            = "0"

# any security group IDs in this list will be given access to the opscenter master node on ports 8443 and 9091
ops_additional_sg_ids     = []

# optional hosted zone parameter; if specified, opscenter will be given a record in Route 53
hosted_zone_name          = ""
private_hosted_zone       = "true"
