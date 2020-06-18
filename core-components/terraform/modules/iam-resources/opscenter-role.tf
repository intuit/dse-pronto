###################
# role and instance profile for DSE nodes
###################

resource "aws_iam_role" "opscenter-role" {
  name               = "${var.prefix}opscenter-role${var.suffix}"
  assume_role_policy = data.aws_iam_policy_document.ec2-assume-role-trusted-policy.json
}

resource "aws_iam_instance_profile" "opscenter-profile" {
  name = aws_iam_role.opscenter-role.name
  role = aws_iam_role.opscenter-role.name
}

###################
# policy granting DSE node access to SSM Parameter Store
###################

resource "aws_iam_policy" "opscenter-ssm-policy" {
  depends_on  = [aws_iam_role.opscenter-role]
  name        = "${var.prefix}opscenter-ssm-policy${var.suffix}"
  description = "Allow OpsCenter instances access to parameter store"
  policy      = data.aws_iam_policy_document.ssm-parameterstore-doc.json
}

resource "aws_iam_role_policy_attachment" "opscenter-ssm-attach" {
  role        = aws_iam_role.opscenter-role.name
  policy_arn  = aws_iam_policy.opscenter-ssm-policy.arn
}

###################
# policy granting OpsCenter node read access to tfstate bucket
###################

resource "aws_iam_policy" "opscenter-readbucket-policy" {
  depends_on  = [aws_iam_role.opscenter-role]
  name        = "${var.prefix}opscenter-readbucket-policy${var.suffix}"
  description = "Allow OpsCenter instances read access to tfstate"
  policy      = data.aws_iam_policy_document.read-tfstate-doc.json
}

resource "aws_iam_role_policy_attachment" "opscenter-readbucket-attach" {
  role       = aws_iam_role.opscenter-role.name
  policy_arn = aws_iam_policy.opscenter-readbucket-policy.arn
}

###################
# policy granting OpsCenter node scoped write access to tfstate bucket
###################

data "aws_iam_policy_document" "opscenter-bucket-doc" {
  statement {
    effect  = "Allow"
    actions = [
      "s3:Put*"
    ]
    resources = [
      "arn:aws:s3:::${var.tfstate_bucket}/${var.account_name}/*/opscenter-resources/*"
    ]
  }
}

resource "aws_iam_policy" "opscenter-bucket-policy" {
  name        = "${var.prefix}opscenter-bucket-policy${var.suffix}"
  description = "Allow OpsCenter instances scoped write access to tfstate bucket"
  policy      = data.aws_iam_policy_document.opscenter-bucket-doc.json
}

resource "aws_iam_role_policy_attachment" "opscenter-bucket-attach" {
  role       = aws_iam_role.opscenter-role.name
  policy_arn = aws_iam_policy.opscenter-bucket-policy.arn
}

###################
# policy granting DSE node permissions for bootstrap and self-heal
###################

resource "aws_iam_policy" "opscenter-bootstrap-policy" {
  name        = "${var.prefix}opscenter-bootstrap-policy${var.suffix}"
  description = "Allow OpsCenter instances to bootstrap"
  policy      = data.aws_iam_policy_document.ec2-autoscaling-doc.json
}

resource "aws_iam_role_policy_attachment" "opscenter-bootstrap-attach" {
  role       = aws_iam_role.opscenter-role.name
  policy_arn = aws_iam_policy.opscenter-bootstrap-policy.arn
}
