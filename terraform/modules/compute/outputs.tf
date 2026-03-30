output "alb_dns_name" {
  value = aws_lb.web.dns_name
}

output "asg_name" {
  value = aws_autoscaling_group.web.name 
}
