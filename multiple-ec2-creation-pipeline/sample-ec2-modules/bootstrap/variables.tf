variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket to create for OpenTofu state storage. Must be globally unique."
}

variable "region" {
  type        = string
  default     = "ap-southeast-1"
  description = "AWS region for the state bucket."
}
