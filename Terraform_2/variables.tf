variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "source_bucket_name" {
  description = "Globally-unique name of the S3 bucket external user uploads into"
  type        = string
}

variable "target_bucket_name" {
  description = "Globally-unique name of the S3 bucket NiFi writes into"
  type        = string
}

variable "sqs_queue_name" {
  description = "Name of the SQS queue receiving S3 notifications"
  type        = string
  default     = "s3-notify-queue"
}

variable "external_user_name" {
  description = "IAM username for the external NiFi user"
  type        = string
  default     = "nifi-external-user"
}

