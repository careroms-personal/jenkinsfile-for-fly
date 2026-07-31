variable "customer_name" {
  type        = string
  description = "Customer identifier used for naming, tags, and the S3 state key at the caller level."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.customer_name))
    error_message = "customer_name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for this customer's UAT instance, e.g. t3.micro. No default — varies per customer's setup process."
}

variable "subnet_id" {
  type        = string
  default     = "subnet-05de5976e810ae03a"
  description = "Existing private subnet the instance launches into (VPC vpc-09aa10f3b94994be4). Hardcoded PoC default, reused across all customers for now."
}

variable "vpc_security_group_ids" {
  type        = list(string)
  default     = ["sg-02b05989e0e617e14"]
  description = "Existing security group(s) attached to the instance. Hardcoded PoC default, reused across all customers for now."
}

variable "ami_id" {
  type        = string
  default     = null
  description = "Optional explicit AMI ID override for customers with their own setup process. When unset, falls back to the latest Ubuntu AMI via the aws_ami data source."
}
