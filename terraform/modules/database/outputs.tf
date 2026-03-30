output "db_name" {
  value = aws_db_instance.example.db_name
}

output "db_user" {
  value = aws_db_instance.example.username
}

output "db_host" {
  value = aws_db_instance.example.endpoint
}

output "secrets_id" {
  value = aws_secretsmanager_secret.db_password.id
}

output "secrets_manager_arn" {
  value = aws_secretsmanager_secret.db_password.arn
}

output "db_endpoint" {
  value = aws_db_instance.example.endpoint
}

output "db_secret_name" {
  value = aws_secretsmanager_secret.db_password.name
}