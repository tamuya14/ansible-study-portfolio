output "alb_dns_name" {
  value = "http://${module.compute.alb_dns_name}"
}

output "asg_name" {
  description = "Auto Scaling Group の名前"
  value       = module.compute.asg_name
}
