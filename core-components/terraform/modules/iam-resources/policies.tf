###################
# policy granting access to SSM Parameter Store
###################

data "aws_iam_policy_document" "ssm-parameterstore-doc" {
  statement {
    effect  = "Allow"
    actions = [
      "ssm:DescribeParameters"
    ]
    resources = ["*"]
  }
  statement {
    effect  = "Allow"
    actions = [
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = ["arn:aws:ssm:*:${var.account_id}:parameter/dse*"]
  }
}

###################
# policy granting permissions for bootstrap and self-heal
###################

data "aws_iam_policy_document" "ec2-autoscaling-doc" {
  statement {
    effect  = "Allow"
    actions = [
      "autoscaling:AttachInstances",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeTags",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup"
    ]
    resources = ["*"]
  }
  statement {
    effect  = "Allow"
    actions = [
      "ec2:AttachNetworkInterface",
      "ec2:AttachVolume",
      "ec2:CreateVolume",
      "ec2:CreateTags",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DetachVolume"
    ]
    resources = ["*"]
  }
}

###################
# policy granting read access to tfstate bucket
###################

data "aws_iam_policy_document" "read-tfstate-doc" {
  statement {
    effect  = "Allow"
    actions = [
      "s3:Get*",
      "s3:ListObjects*",
      "s3:ListBucket*",
      "s3:HeadObject",
      "s3:PutObject"
    ]
    resources = [
      "arn:aws:s3:::${var.tfstate_bucket}",
      "arn:aws:s3:::${var.tfstate_bucket}/*"
    ]
  }
}
