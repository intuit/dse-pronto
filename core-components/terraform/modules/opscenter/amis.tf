data "aws_ami" "opscenter" {
  most_recent = true
  owners      = ["${var.ami_owner_id}"]

  filter {
    name   = "name"
    values = ["${var.ami_prefix}*"]
  }
}
