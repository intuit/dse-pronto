###################
# role and instance profile for DSE nodes
###################

resource "aws_iam_role" "cassandra-role" {
  name               = "${var.prefix}cassandra-role${var.suffix}"
  assume_role_policy = data.aws_iam_policy_document.ec2-assume-role-trusted-policy.json
}

resource "aws_iam_instance_profile" "cassandra-profile" {
  name = aws_iam_role.cassandra-role.name
  role = aws_iam_role.cassandra-role.name
}

###################
# policy granting DSE node access to SSM Parameter Store
###################

resource "aws_iam_policy" "cassandra-ssm-policy" {
  depends_on  = [aws_iam_role.cassandra-role]
  name        = "${var.prefix}cassandra-ssm-policy${var.suffix}"
  description = "Allow DSE instances access to parameter store"
  policy      = data.aws_iam_policy_document.ssm-parameterstore-doc.json
}

resource "aws_iam_role_policy_attachment" "cassandra-ssm-attach" {
  role        = aws_iam_role.cassandra-role.name
  policy_arn  = aws_iam_policy.cassandra-ssm-policy.arn
}

###################
# policy granting DSE node read access to tfstate bucket
###################

resource "aws_iam_policy" "cassandra-readbucket-policy" {
  depends_on  = [aws_iam_role.opscenter-role]
  name        = "${var.prefix}cassandra-readbucket-policy${var.suffix}"
  description = "Allow DSE instances read access to tfstate"
  policy      = data.aws_iam_policy_document.read-tfstate-doc.json
}

resource "aws_iam_role_policy_attachment" "cassandra-readbucket-attach" {
  role       = aws_iam_role.cassandra-role.name
  policy_arn = aws_iam_policy.cassandra-readbucket-policy.arn
}

###################
# policy granting DSE node scoped write access to tfstate bucket
###################

data "aws_iam_policy_document" "cassandra-bucket-permissions-doc" {
  statement {
    effect  = "Allow"
    actions = [
      "s3:Put*"
    ]
    resources = [
      "arn:aws:s3:::${var.tfstate_bucket}/${var.account_name}/*/files",
      "arn:aws:s3:::${var.tfstate_bucket}/${var.account_name}/*/files/*"
    ]
  }
  statement {
    effect  = "Allow"
    actions = [
      "s3:DeleteObject"
    ]
    resources = [
      "arn:aws:s3:::${var.tfstate_bucket}/${var.account_name}/*/files/lock",
      "arn:aws:s3:::${var.tfstate_bucket}/${var.account_name}/*/files/lock/*"
    ]
  }
}

resource "aws_iam_policy" "cassandra-bucket-permissions-policy" {
  name        = "${var.prefix}cassandra-bucket-policy${var.suffix}"
  description = "Allow DSE instances scoped write access to tfstate bucket"
  policy      = data.aws_iam_policy_document.cassandra-bucket-permissions-doc.json
}

resource "aws_iam_role_policy_attachment" "cassandra-bucket-attach" {
  role       = aws_iam_role.cassandra-role.name
  policy_arn = aws_iam_policy.cassandra-bucket-permissions-policy.arn
}

###################
# policy granting DSE node permissions for bootstrap and self-heal
###################

resource "aws_iam_policy" "cassandra-bootstrap-policy" {
  name        = "${var.prefix}cassandra-bootstrap-policy${var.suffix}"
  description = "Allow DSE instances to bootstrap"
  policy      = data.aws_iam_policy_document.ec2-autoscaling-doc.json
}

resource "aws_iam_role_policy_attachment" "cassandra-bootstrap-attach" {
  role       = aws_iam_role.cassandra-role.name
  policy_arn = aws_iam_policy.cassandra-bootstrap-policy.arn
}
