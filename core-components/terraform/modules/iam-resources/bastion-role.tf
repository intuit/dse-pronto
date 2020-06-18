###################
# role and instance profile for bastion
###################

resource "aws_iam_role" "bastion-role" {
  name               = "${var.prefix}bastion-role${var.suffix}"
  assume_role_policy = data.aws_iam_policy_document.ec2-assume-role-trusted-policy.json
}

resource "aws_iam_instance_profile" "bastion-profile" {
  name = aws_iam_role.bastion-role.name
  role = aws_iam_role.bastion-role.name
}

###################
# policy granting bastion access to SSM Parameter Store
###################

resource "aws_iam_policy" "bastion-ssm-policy" {
  depends_on  = [aws_iam_role.bastion-role]
  name        = "${var.prefix}bastion-ssm-policy${var.suffix}"
  description = "Allow bastion instances access to parameter store"
  policy      = data.aws_iam_policy_document.ssm-parameterstore-doc.json
}

resource "aws_iam_role_policy_attachment" "bastion-ssm-attach" {
  role        = aws_iam_role.bastion-role.name
  policy_arn  = aws_iam_policy.bastion-ssm-policy.arn
}

###################
# policy granting bastion read access to tfstate bucket
###################

resource "aws_iam_policy" "bastion-readbucket-policy" {
  depends_on  = [aws_iam_role.bastion-role]
  name        = "${var.prefix}bastion-readbucket-policy${var.suffix}"
  description = "Allow bastion instances read access to tfstate"
  policy      = data.aws_iam_policy_document.read-tfstate-doc.json
}

resource "aws_iam_role_policy_attachment" "bastion-readbucket-attach" {
  role       = aws_iam_role.bastion-role.name
  policy_arn = aws_iam_policy.bastion-readbucket-policy.arn
}

###################
# policy granting bastion permissions for bootstrap
###################

data "aws_iam_policy_document" "bastion-bootstrap-doc" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:AssociateAddress"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "bastion-bootstrap-policy" {
  depends_on  = [aws_iam_role.bastion-role]
  name        = "${var.prefix}bastion-bootstrap-policy${var.suffix}"
  policy      = data.aws_iam_policy_document.bastion-bootstrap-doc.json
}

resource "aws_iam_role_policy_attachment" "bastion-bootstrap-attach" {
  role        = aws_iam_role.bastion-role.name
  policy_arn  = aws_iam_policy.bastion-bootstrap-policy.arn
}
