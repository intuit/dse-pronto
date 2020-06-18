resource "aws_network_interface" "cas-seed-eni" {
  count     = length(var.availability_zones)
  subnet_id = element(var.cluster_subnet_ids, count.index)
  security_groups = [
    aws_security_group.cas-bastion-access.id,
    aws_security_group.cas-client-access.id,
    aws_security_group.cas-internode.id,
    var.sg_ops_nodes_to_cas,
  ]

  tags = merge(map("Name", "${var.cluster_name}-seed-${count.index}"), var.ec2_tags, local.required_ec2_tags)
}

resource "aws_network_interface" "cas-non-seed-eni" {
  count = (var.dse_nodes_per_az - 1) * length(var.availability_zones)

  # round-robin the non-seeds into the available subnets
  subnet_id = element(
    var.cluster_subnet_ids,
    count.index % length(var.availability_zones),
  )
  security_groups = [
    aws_security_group.cas-bastion-access.id,
    aws_security_group.cas-client-access.id,
    aws_security_group.cas-internode.id,
    var.sg_ops_nodes_to_cas,
  ]

  tags = merge(map("Name", "${var.cluster_name}-non-seed-${count.index}"), var.ec2_tags, local.required_ec2_tags)

}

