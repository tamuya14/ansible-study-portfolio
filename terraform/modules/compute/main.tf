
# 1. 起動テンプレートの定義
resource "aws_launch_template" "web" {
  name_prefix   = "${var.env_name}-template-"
  image_id      = data.aws_ami.recent_amazon_linux_2023.id # dataで取得したAMI ID
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ssm_profile.name
  }

  # ネットワーク設定
  network_interfaces {
    associate_public_ip_address = false # プライベートサブネットに置くため
    security_groups             = [var.web_sg_id]
  }

  # UserData（templatefile を使う）
  #user_data = base64encode(templatefile("${path.module}/install_wp.sh", {
  #  db_name    = var.db_name
  #  db_user    = var.db_user
  #  db_host    = var.db_host
  #  secrets_id = var.secrets_id
  #  target_env = terraform.workspace
  #  region     = "ap-northeast-1"
  #}))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.env_name}-web"
    }
  }
}


# 2. Auto Scaling Group の定義
resource "aws_autoscaling_group" "web" {
  name             = "${var.env_name}-asg"
  max_size         = var.max_size         # 最大何台まで増やしていいか
  min_size         = var.min_size         # 最小何台維持するか
  desired_capacity = var.desired_capacity # 通常時に動かしておきたい台数

  vpc_zone_identifier = var.private_subnet_ids # インスタンスを配置するサブネット

  # 使用する起動テンプレートの指定
  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest" # 常に最新バージョンのテンプレートを使用
  }

  # ALBとの紐付け
  target_group_arns = [aws_lb_target_group.web.arn]

  # インスタンスのヘルスチェック設定
  health_check_type         = "ELB"
  #health_check_type = "EC2"      # <-- これに変更
  health_check_grace_period = 600 # 起動後、Ansible Playbook実行前に異常判定されないよう10分間待機


  # Name タグ (人間用)
  tag {
    key                 = "Name"
    value               = "${var.env_name}-asg-wordpress-instance"
    propagate_at_launch = true # インスタンス起動時にこのタグを付与する
  }
  
  # Role タグ (Ansible用)
  tag {
    key                 = "Role"
    value               = "web_server"
    propagate_at_launch = true
  }

  tag {
    key                 = "Env"
    value               = terraform.workspace
    propagate_at_launch = true
  }
  
}


# CPU使用率をターゲットにするスケーリングポリシー
resource "aws_autoscaling_policy" "cpu_tracking" {
  name                   = "${var.env_name}-cpu-tracking"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0 # 平均CPU使用率を50%に保つ
  }
}


# ロググループの作成
resource "aws_cloudwatch_log_group" "wp_log_group" {
  name              = "/aws/ec2/${terraform.workspace}/wordpress-access-log"
  retention_in_days = 7 # 7日間保存（学習用なので短くしてコストを節約）
}
