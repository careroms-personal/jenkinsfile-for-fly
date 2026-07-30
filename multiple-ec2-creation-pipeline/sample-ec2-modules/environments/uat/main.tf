module "this" {
  source = "../../modules/uat-ec2"

  customer_name = var.customer_name
  instance_type = var.instance_type
  ami_id        = var.ami_id
}

output "instance_id" {
  value = module.this.instance_id
}

output "private_ip" {
  value = module.this.private_ip
}
