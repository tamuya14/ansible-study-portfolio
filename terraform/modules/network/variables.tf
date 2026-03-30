variable "vpc_cidr" {
  description = "VPCのCIDR範囲"
  type        = string
}

variable "env_name" {
  description = "プロジェクト名と環境名を合わせた名前"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "パブリックサブネットのCIDR範囲"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "プライベートサブネットのCIDR範囲"
  type        = list(string)
}
