locals {
  # プロジェクト名と現在のWorkspace名を連結して一つの変数にする
  env_name = "${var.project_name}-${terraform.workspace}"

  # 環境ごとのスペック設定をここに集約
  env_config = {
    dev = {
      instance_type    = "t3.micro"
      max_size         = 3 # 最大何台まで増やしていいか
      min_size         = 2 # 最小何台維持するか
      desired_capacity = 2 # 通常時に動かしておきたい台数
    }

    prd = {
      instance_type    = "t3.small"
      max_size         = 5 # 最大何台まで増やしていいか
      min_size         = 3 # 最小何台維持するか
      desired_capacity = 3 # 通常時に動かしておきたい台数
    }
  }

  # 今の Workspace に対応する設定を抽出
  current_config = local.env_config[terraform.workspace]
}
