output "instance_id" {
  value = aws_instance.uat.id
}

output "private_ip" {
  value       = aws_instance.uat.private_ip
  description = "Target subnet is private — no public IP is assigned, so private_ip is the reachable address (Jenkins/k8s shares the same VPC)."
}
