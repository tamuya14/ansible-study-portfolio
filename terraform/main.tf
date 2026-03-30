# どのプロバイダー（クラウド）を使うか宣言
terraform {
  required_version = "~> 1.14.0"

#Backendはマスク処理を実施
#※自身のものに差し替える
backend "s3" {
    bucket         = "YOUR-UNIQUE-S3-BUCKET-NAME"
    key            = "aws-ansible-study/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "YOUR-DYNAMODB-TABLE-NAME"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# リージョン/共通タグの設定
provider "aws" {
  region = "ap-northeast-1" # 東京

  default_tags {
    tags = {
      # ブランチ（workspace）に応じた環境識別
      Env       = terraform.workspace
      # どのツールで管理されているか（手動変更禁止の意思表示）
      ManagedBy = "Terraform"
      # プロジェクト全体を横断して検索したい場合に便利
      Project   = var.project_name
    }
  }




}

module "base_network" {
  source               = "./modules/network"
  vpc_cidr             = var.vpc_cidr # 外側の変数からモジュールへ渡す
  env_name             = local.env_name
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}


module "security_group" {
  source   = "./modules/security_group"
  env_name = local.env_name
  vpc_id   = module.base_network.vpc_id # networkの出力を渡す
}

module "database" {
  source             = "./modules/database"
  env_name           = local.env_name
  vpc_id             = module.base_network.vpc_id             # networkの出力を渡す
  private_subnet_ids = module.base_network.private_subnet_ids # networkの出力を渡す
  web_sg_id          = module.security_group.web_sg_id
}

module "compute" {
  source = "./modules/compute"

  env_name      = local.env_name
  instance_type = local.current_config.instance_type

  vpc_id             = module.base_network.vpc_id             # networkの出力を渡す
  public_subnet_ids  = module.base_network.public_subnet_ids  # networkの出力を渡す
  private_subnet_ids = module.base_network.private_subnet_ids # networkの出力を渡す

  db_name             = module.database.db_name
  db_user             = module.database.db_user
  db_host             = module.database.db_host
  secrets_id          = module.database.secrets_id
  secrets_manager_arn = module.database.secrets_manager_arn

  web_sg_id = module.security_group.web_sg_id
  alb_sg_id = module.security_group.alb_sg_id

  max_size         = local.current_config.max_size
  min_size         = local.current_config.min_size
  desired_capacity = local.current_config.desired_capacity
}
