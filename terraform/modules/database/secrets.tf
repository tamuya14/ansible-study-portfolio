# 1. 金庫の「箱」を作る
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.env_name}-db-password"
  description             = "WordPress DB password"
  recovery_window_in_days = 0 # 削除後すぐに消す設定（練習用）
}

# 2. 金庫の中に「中身（パスワード）」を保存する
resource "aws_secretsmanager_secret_version" "db_password_version" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result # 生成されたパスワードを保存 
}
