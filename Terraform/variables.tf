variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "prefix" {
  description = "Prefix for resource names to avoid clashes"
  type        = string
  default     = "nifi-test-resource"
}

variable "s3_event_suffix" {
  description = "Suffix for S3 event notifications (e.g. .json, .csv). Leave empty for all."
  type        = string
  default     = ".json"
}

variable "s3_event_prefix" {
  description = "Prefix for S3 event notifications (e.g. incoming/, data/). Leave empty for all."
  type        = string
  default     = ""
}
