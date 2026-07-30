variable "customer_name" {
  type        = string
  description = "Customer identifier, passed straight through to the uat-ec2 module."
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type, passed straight through to the uat-ec2 module."
}

variable "ami_id" {
  type        = string
  default     = null
  description = "AMI ID, passed straight through to the uat-ec2 module. If null, the module falls back to the latest Ubuntu LTS AMI."
}
