data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "AllowAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = var.trusted_principals.type
      identifiers = var.trusted_principals.identifiers
    }
  }
}

resource "aws_iam_role" "team" {
  name               = "${var.team_name}-s3"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(var.tags, {
    Team      = var.team_name
    ManagedBy = "terraform"
  })
}

data "aws_iam_policy_document" "s3" {
  statement {
    sid       = "ListOwnBuckets"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = var.bucket_arns
  }

  statement {
    sid    = "ObjectAccessOwnBuckets"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = [for arn in var.bucket_arns : "${arn}/*"]
  }
}

resource "aws_iam_role_policy" "s3" {
  name   = "${var.team_name}-s3-access"
  role   = aws_iam_role.team.id
  policy = data.aws_iam_policy_document.s3.json
}
