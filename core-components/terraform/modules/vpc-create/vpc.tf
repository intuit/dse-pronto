#############
# The data sources in this module will be gathered if terraform_managed_vpc is
# set to true, and required vpc/cidr variables are provided.
#############

resource "aws_vpc" "dse-vpc" {
  cidr_block       = var.vpc_cidr
  instance_tenancy = "default"
  tags             = {
    Name = var.vpc_name
  }
}

resource "aws_internet_gateway" "dse-vpc" {
  vpc_id = aws_vpc.dse-vpc.id
  tags   = {
    Name = "${var.vpc_name}-igw"
  }
}

#############
# subnets (should be 3 ingress, 3 data)
#############

resource "aws_subnet" "dse-vpc-ingress" {
  count             = length(var.ingress_subnets)
  vpc_id            = aws_vpc.dse-vpc.id
  cidr_block        = var.ingress_subnets[count.index]
  availability_zone = "${var.region}${var.azs[count.index]}"
  tags              = {
    Name = "${var.ingress_subnet_tag_prefix}-subnet-${count.index}"
  }
}

resource "aws_subnet" "dse-vpc-data" {
  count             = length(var.data_subnets)
  vpc_id            = aws_vpc.dse-vpc.id
  cidr_block        = var.data_subnets[count.index]
  availability_zone = "${var.region}${var.azs[count.index]}"
  tags              = {
    Name = "${var.data_subnet_tag_prefix}-subnet-${count.index}"
  }
}

#############
# nat gateway (1 in each ingress subnet)
#############

resource "aws_eip" "dse-vpc" {
  count             = length(var.ingress_subnets)
  vpc               = true
  tags              = {
    Name = "${var.vpc_name}-natgw-eip-${count.index}"
  }
}

resource "aws_nat_gateway" "dse-vpc" {
  count             = length(var.ingress_subnets)
  allocation_id     = aws_eip.dse-vpc.*.id[count.index]
  subnet_id         = aws_subnet.dse-vpc-ingress.*.id[count.index]
  tags              = {
    Name = "${var.vpc_name}-natgw-${count.index}"
  }
}

#############
# route tables for ingress subnets
#############

resource "aws_route_table" "ingress-rtb" {
  count             = length(var.ingress_subnets)
  vpc_id            = aws_vpc.dse-vpc.id
  tags              = {
    Name = "${var.ingress_subnet_tag_prefix}-rtb-${count.index}"
  }
}

# route to IGW for each ingress subnet
resource "aws_route" "ingress-igw" {
  count             = length(var.ingress_subnets)
  route_table_id    = aws_route_table.ingress-rtb.*.id[count.index]
  destination_cidr_block = "0.0.0.0/0"
  gateway_id        = aws_internet_gateway.dse-vpc.id
  timeouts {
    create = "5m"
  }
}

resource "aws_route_table_association" "ingress-rtb-assoc" {
  count          = length(var.ingress_subnets)
  subnet_id      = aws_subnet.dse-vpc-ingress.*.id[count.index]
  route_table_id = aws_route_table.ingress-rtb.*.id[count.index]
}

#############
# route tables for data subnets
#############

resource "aws_route_table" "data-rtb" {
  count             = length(var.data_subnets)
  vpc_id            = aws_vpc.dse-vpc.id
  tags              = {
    Name = "${var.data_subnet_tag_prefix}-rtb-${count.index}"
  }
}

# route to NATGW for each data subnet
resource "aws_route" "data-natgw" {
  count             = length(var.data_subnets)
  route_table_id    = aws_route_table.data-rtb.*.id[count.index]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id    = aws_nat_gateway.dse-vpc.*.id[count.index]
  timeouts {
    create = "5m"
  }
}

resource "aws_route_table_association" "data-rtb-assoc" {
  count          = length(var.data_subnets)
  subnet_id      = aws_subnet.dse-vpc-data.*.id[count.index]
  route_table_id = aws_route_table.data-rtb.*.id[count.index]
}
