variable "env_name" {
  description = "プロジェクト名と環境名を合わせた名前"
  type        = string
}

variable "vpc_id" {
  description = "セキュリティグループを作成するVPCのID"
  type        = string
}

variable "private_subnet_ids" {
  description = "DBサブネットグループに使用するプライベートサブネットのリスト"
  type        = list(string)
}

variable "web_sg_id" {
  description = "RDSへの通信を許可する送信元のセキュリティグループID"
  type        = string
}