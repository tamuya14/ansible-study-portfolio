variable "env_name" {
  description = "プロジェクト名と環境名を合わせた名前"
  type        = string
}

variable "instance_type" {
  description = "EC2のインスタンスタイプ"
  type        = string
}


variable "vpc_id" {
  description = "ターゲットグループ用のVPCのID"
  type        = string
}

variable "public_subnet_ids" {
  description = "ALBに使用するパブリックサブネットのリスト"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "EC2インスタンスに使用するプライベートサブネットのリスト"
  type        = list(string)
}

variable "db_name" {
  description = "RDSのデータベース名"
  type        = string
}

variable "db_user" {
  description = "RDSのユーザ名"
  type        = string
}

variable "db_host" {
  description = "RDSのエンドポイント"
  type        = string
}

variable "secrets_id" {
  description = "RDS用のSecrets ManagerのシークレットID"
  type        = string
}

variable "secrets_manager_arn" {
  description = "RDS用のSecrets Manager のARN"
  type        = string
}

variable "web_sg_id" {
  description = "WebサーバのALBからの通信を許可するセキュリティグループのID"
  type        = string
}

variable "alb_sg_id" {
  description = "ALBのセキュリティグループのID"
  type        = string
}

variable "min_size" {
  description = "最小維持台数"
  type        = string
}

variable "desired_capacity" {
  description = "希望維持台数"
  type        = string
}

variable "max_size" {
  description = "最大台数"
  type        = string
}