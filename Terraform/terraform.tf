provider "aws" {
  region = "us-east-1"
}

# SQS Queue
resource "aws_sqs_queue" "s3_event_queue" {
  name = "s3-event-tar-files"
}

# S3 Bucket
resource "aws_s3_bucket" "example_bucket" {
  bucket = "example-tar-upload-bucket"
}

# S3 Bucket Notification Configuration to trigger on .tar files
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.example_bucket.id

  queue {
    queue_arn     = aws_sqs_queue.s3_event_queue.arn
    events        = ["s3:ObjectCreated:*"]

    filter_suffix = ".tar"
  }

  depends_on = [aws_sqs_queue_policy.s3_allow]
}

# SQS Queue Policy to allow S3 to send notifications
data "aws_iam_policy_document" "s3_to_sqs" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sqs:SendMessage"]

    resources = [aws_sqs_queue.s3_event_queue.arn]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.example_bucket.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "s3_allow" {
  queue_url = aws_sqs_queue.s3_event_queue.id
  policy    = data.aws_iam_policy_document.s3_to_sqs.json
}

# IAM User and Policy for external user to read SQS messages
resource "aws_iam_user" "external_user" {
  name = "external-sqs-reader"
}

data "aws_iam_policy_document" "sqs_read_access" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [
      aws_sqs_queue.s3_event_queue.arn
    ]
  }
}

resource "aws_iam_user_policy" "sqs_reader_policy" {
  name   = "sqs-reader"
  user   = aws_iam_user.external_user.name
  policy = data.aws_iam_policy_document.sqs_read_access.json
}

resource "aws_iam_access_key" "external_user_keys" {
  user = aws_iam_user.external_user.name
}

# Output IAM Access Key and Secret (sensitive data)
output "external_user_access_key" {
  value     = aws_iam_access_key.external_user_keys.id
  sensitive = true
}

output "external_user_secret_key" {
  value     = aws_iam_access_key.external_user_keys.secret
  sensitive = true
}

