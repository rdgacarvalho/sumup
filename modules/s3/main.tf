locals {
  bucket_names = {
    for key, cfg in var.buckets :
    key => "${var.name_prefix}-${var.team_name}-${key}"
  }
}

resource "aws_s3_bucket" "this" {
  for_each = var.buckets

  bucket        = local.bucket_names[each.key]
  force_destroy = false

  tags = merge(var.tags, {
    Name       = local.bucket_names[each.key]
    Team       = var.team_name
    Visibility = each.value.visibility
    ManagedBy  = "terraform"
  })
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = var.buckets[each.key].visibility == "private"
  restrict_public_buckets = var.buckets[each.key].visibility == "private"
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "public_read" {
  for_each = {
    for key, cfg in var.buckets : key => cfg if cfg.visibility == "public"
  }

  statement {
    sid    = "PublicReadGetObject"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this[each.key].arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "public_read" {
  for_each = data.aws_iam_policy_document.public_read

  bucket = aws_s3_bucket.this[each.key].id
  policy = each.value.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
