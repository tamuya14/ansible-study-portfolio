
#  ALB本体の設定
resource "aws_lb" "web" {
  name               = "super-power-app-${terraform.workspace}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "${var.env_name}-alb"
  }
}

# ターゲットグループ
resource "aws_lb_target_group" "web" {
  name     = "${var.env_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  deregistration_delay = 30

  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200,302" # ここに 302(初期設定画面時の応答) を追加
  }
}

#  リスナー
resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}


