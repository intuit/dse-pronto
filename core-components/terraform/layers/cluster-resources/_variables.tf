variable "tfstate_bucket" {}
variable "tfstate_region" {}
variable "profile" {}
variable "region" {}
variable "role_arn" {}

variable "account_name" {}
variable "vpc_name" {}
variable "cluster_name" {}

variable "ami_owner_id" {}
variable "ami_prefix" { default = "dse-cassandra" }
variable "instance_type" { default = "m5.2xlarge" }

variable "account_id" {}
variable "availability_zones" { type = list(string) }

variable "dse_nodes_per_az" { default = 1 }
variable "auto_start_dse" { default = 1 }
variable "graph_enabled" { default = 0 }
variable "solr_enabled" { default = 0 }
variable "spark_enabled" { default = 0 }

# settings for cassandra node root volume
variable "root_volume_type" { default = "gp2" }
variable "root_volume_size" { default = "100" }
variable "root_volume_iops" { default = "300" }

# tags
variable "account_tags" { default = {} }
variable "vpc_tags" { default = {} }
variable "cluster_tags" { default = {} }

# the following vars are passed directly through to parameter-store, and are not required by the
# module implementation otherwise.
variable "keyspace" {}
variable "volume_type" {}
variable "iops" {}
variable "data_volume_size" {}
variable "commitlog_size" {}
variable "commitlog_volume_type" { default = "gp2" }
variable "commitlog_iops" { default = "null" }
variable "number_of_stripes" { default = "1" }
variable "raid_level" { default = "-1" }
variable "raid_block_size" { default = "128" }
variable "max_heap_size" { default = "8" }
variable "num_tokens" { default = "256" }
variable "aio_enabled" { default = "true" }
variable "max_queued_native_transport_requests" { default = "-1" }
variable "native_transport_max_threads" { default = "-1" }
