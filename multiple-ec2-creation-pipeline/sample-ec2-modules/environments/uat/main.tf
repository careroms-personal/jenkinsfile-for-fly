locals {
  customer_config = yamldecode(file("${path.module}/customers/${var.customer_name}.yaml"))
}

module "this" {
  source = "../../modules/uat-ec2"

  customer_name = local.customer_config.customer_name
  instance_type = local.customer_config.instance_type
  ami_id        = try(local.customer_config.ami_id, null)
}

output "instance_id" {
  value = module.this.instance_id
}

output "private_ip" {
  value = module.this.private_ip
}
