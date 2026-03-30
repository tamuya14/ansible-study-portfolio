
# RDS用のサブネットグループ
resource "aws_db_subnet_group" "mysql" {
  name = "${var.env_name}-db-subnet-group"

  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.env_name}-db-subnet-group"
  }
}

resource "aws_db_instance" "example" {
  identifier = "${var.env_name}-db-instance" # 識別子（AWSコンソール上の名前）

  allocated_storage = 20
  storage_type      = "gp2"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro" # 無料枠対象のサイズ

  # データベース名も環境ごとに分ける（ハイフンが使えないのでアンダースコア推奨）
  db_name = "${replace(var.env_name, "-", "_")}_db"

  username = "admin"
  password = random_password.db_password.result # 自動生成された値を使う

  db_subnet_group_name = aws_db_subnet_group.mysql.name

  vpc_security_group_ids = [aws_security_group.db_sg.id]

  # 学習用なので、削除時にスナップショットをとらない設定（すぐ消せるように）
  skip_final_snapshot = true

  # マルチAZにする場合はここを true に（今回はコストと時間節約のため false）
  multi_az = false

  tags = {
    Name = "${var.env_name}-rds"
  }
}


# パスワードの自動生成
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}



# RDS用セキュリティグループ
resource "aws_security_group" "db_sg" {
  name        = "${var.env_name}-db-sg"
  vpc_id      = var.vpc_id
  description = "Allow MySQL traffic from Web servers"

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.web_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
