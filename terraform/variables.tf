variable "project_name" {
  description = "プロジェクトの基本名。別の案件で使うときはここだけ変える"
  type        = string
  default     = "super-power-app"
}

variable "vpc_cidr" {
  description = "VPCのネットワーク範囲"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public Subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private Subnet CIDRs"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"] # パブリックと被らない値
}
