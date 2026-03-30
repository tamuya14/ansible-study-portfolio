# Terraform で作成した値を Ansible 用の YAML ファイルとして書き出す
resource "local_file" "ansible_db_vars" {
  # Ansible の Playbook が参照しやすい場所に配置します
  filename = "${path.module}/../ansible/group_vars/all/db_config.yml"
  
  content  = <<EOT
db_host: "${module.database.db_host}"
db_name: "${module.database.db_name}"
db_user: "${module.database.db_user}"
db_secret_name: "${module.database.db_secret_name}"
EOT
}

resource "local_file" "env_vars" {
  # Ansible の Playbook が参照しやすい場所に配置します
  filename = "${path.module}/../ansible/group_vars/all/env_vars.yml"
  
  content  = <<EOT
target_env: "${terraform.workspace}"
EOT
}
