##################
# CIDR lists
##################

# CIDRs for bastion SSH (port 22) and OpsCenter ELB (port 443) ingress
ingress_cidrs = [
  "10.11.12.13/22",
  "192.168.0.1/32"
]
