# 最新の Amazon Linux 2023 の AMI ID を自動で検索して持ってくる
data "aws_ami" "recent_amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-kernel-6.1-x86_64"] # 名前でパターンマッチング
  }
}


# Parameter Store から値を取得する
data "aws_ssm_parameter" "sns_email" {
  name = "/my-aws-infra/common/sns_email"
}
