locals {
  # Graviton family codes end in "g" right after the generation digit (t4g, m6g, c6g, c7g, ...).
  ami_arch = can(regex("^[a-z]+[0-9]+g", var.instance_type)) ? "arm64" : "amd64"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-${local.ami_arch}-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = [local.ami_arch]
  }
}

resource "aws_instance" "uat" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.vpc_security_group_ids

  tags = {
    Name        = "uat-${var.customer_name}"
    ManagedBy   = "jenkins-ec2-portal"
    Customer    = var.customer_name
    Environment = "UAT"
  }
}
