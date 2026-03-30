
# 1. SNSトピック（通知のチャンネル）の作成
resource "aws_sns_topic" "user_updates" {
  name = "${var.env_name}-updates"
}

# 2. メールの宛先設定（Parameter Storeに保存したメールアドレスを使用）
resource "aws_sns_topic_subscription" "user_updates_sqs_target" {
  topic_arn = aws_sns_topic.user_updates.arn
  protocol  = "email"
  endpoint  = data.aws_ssm_parameter.sns_email.value # ここで取得した値を入れる
}

# 3. ASGとSNSの紐付け（イベントが発生したらSNSへ送る）
resource "aws_autoscaling_notification" "web_notifications" {
  group_names = [
    aws_autoscaling_group.web.name,
  ]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]

  topic_arn = aws_sns_topic.user_updates.arn
}