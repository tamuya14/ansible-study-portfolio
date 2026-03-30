# EC2用のIAMロールを作成
resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.env_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# ロールにSSM用の管理ポリシーをアタッチ
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EC2用IAMロールに、CloudWatch Agent用の管理ポリシーを追加
resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

#  IAMインスタンスプロフィール
resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "${var.env_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

#Secrets Managerにアクセスするための権限追加
resource "aws_iam_role_policy" "secrets_manager_policy" {
  name = "SecretsManagerAccess"
  role = aws_iam_role.ec2_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Effect   = "Allow"
        Resource = var.secrets_manager_arn
      }
    ]
  })
}