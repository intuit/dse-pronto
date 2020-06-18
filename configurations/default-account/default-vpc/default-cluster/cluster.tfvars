# deployment info
availability_zones        = ["a", "b", "c"]

# cassandra configuration
keyspace                  = "<<< YOUR_KEYSPACE_NAME_HERE >>>"
instance_type             = "m5.4xlarge"

# data volume configuration
volume_type               = "gp2"
commitlog_size            = "30"     # gigabytes
data_volume_size          = "1024"   # gigabytes
iops                      = "1000"
number_of_stripes         = "1"
raid_level                = "-1"     # RAID -1 signifies no disk striping; 1 volume = 1 mount point
raid_block_size           = "128"

# settings for cassandra.yaml, cassandra-env.sh
num_tokens                = "256"
max_heap_size             = "8"      # gigabytes
