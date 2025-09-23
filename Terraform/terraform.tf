terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# 1) Source S3 bucket
resource "aws_s3_bucket" "source" {
  bucket        = var.source_bucket_name
  force_destroy = false
}

# 4) Target S3 bucket
resource "aws_s3_bucket" "target" {
  bucket        = var.target_bucket_name
  force_destroy = false
}

# 2) SQS queue for S3 notifications
resource "aws_sqs_queue" "notify_queue" {
  name                       = var.sqs_queue_name
  visibility_timeout_seconds = 30
}

# Allow S3 to send messages to the SQS queue
data "aws_iam_policy_document" "sqs_allow_s3" {
  statement {
    sid = "AllowS3SendMessage"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.notify_queue.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.source.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sqs_queue_policy" "queue_policy" {
  queue_url = aws_sqs_queue.notify_queue.id
  policy    = data.aws_iam_policy_document.sqs_allow_s3.json
}

# 3) S3 → SQS notifications, filtered for *.tar objects
resource "aws_s3_bucket_notification" "source_to_sqs" {
  bucket = aws_s3_bucket.source.id

  queue {
    queue_arn = aws_sqs_queue.notify_queue.arn
    events    = ["s3:ObjectCreated:*"]
    filter_suffix = ".tar"
  }

  depends_on = [aws_sqs_queue_policy.queue_policy]
}

# ---------------------------------------------------------------------------
# 6) IAM user for the external NiFi process
resource "aws_iam_user" "nifi_user" {
  name = var.external_user_name
}

# Policy granting the minimal required permissions
data "aws_iam_policy_document" "nifi_user_policy" {
  statement {
    sid     = "SQSAccess"
    effect  = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ChangeMessageVisibility"
    ]
    resources = [aws_sqs_queue.notify_queue.arn]
  }

  statement {
    sid     = "ReadSourceBucket"
    effect  = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.source.arn,
      "${aws_s3_bucket.source.arn}/*"
    ]
  }

  statement {
    sid     = "WriteTargetBucket"
    effect  = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject"
    ]
    resources = [
      "${aws_s3_bucket.target.arn}/*"
    ]
  }

  statement {
    sid     = "UploadToSourceBucket"
    effect  = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
    resources = [
      "${aws_s3_bucket.source.arn}/*"
    ]
  }
}

resource "aws_iam_user_policy" "nifi_user_policy" {
  name   = "${var.external_user_name}-policy"
  user   = aws_iam_user.nifi_user.name
  policy = data.aws_iam_policy_document.nifi_user_policy.json
}

# 7) Access key for the external user (long-lived, rotate regularly!)
resource "aws_iam_access_key" "nifi_key" {
  user = aws_iam_user.nifi_user.name
}

# ---------------------------------------------------------------------------
# Outputs
output "source_bucket_name" {
  value = aws_s3_bucket.source.bucket
}

output "target_bucket_name" {
  value = aws_s3_bucket.target.bucket
}

output "sqs_queue_url" {
  value = aws_sqs_queue.notify_queue.id
}

output "nifi_user_access_key_id" {
  value = aws_iam_access_key.nifi_key.id
}

# Secret is marked sensitive; Terraform will hide it by default
output "nifi_user_secret_access_key" {
  value     = aws_iam_access_key.nifi_key.secret
  sensitive = true
}

