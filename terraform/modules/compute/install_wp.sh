#!/bin/bash
# 1. アップデートとインストール
dnf update -y
dnf install -y httpd php php-mysqlnd php-gd php-xml php-mbstring php-fpm mariadb105 jq

# パスワードを取得するコマンド
# ※secret_idはTerraformからtemplatefile経由で渡される
FETCHED_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${secrets_id} --region ap-northeast-1 --query SecretString --output text)


# 2. サービスの起動（これを忘れると動かない）
systemctl start httpd
systemctl enable httpd
systemctl start php-fpm
systemctl enable php-fpm

# 3. WordPressの配置
cd /var/www/html
wget https://ja.wordpress.org/latest-ja.tar.gz
tar -xzvf latest-ja.tar.gz
mv wordpress/* .
chown -R apache:apache /var/www/html

# 4. wp-config.php の作成
# 「EOF」までの内容を wp-config.php に書き込む
# Terraformの変数が自動的に展開されて注入される
cat <<EOT > /var/www/html/wp-config.php
<?php
define( 'DB_NAME', '${db_name}' );
define( 'DB_USER', '${db_user}' );
define( 'DB_PASSWORD', '$FETCHED_PASSWORD' );  # ここを Linux の変数に変更
define( 'DB_HOST', '${db_host}' );

define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );

\$table_prefix = 'wp_';
define( 'WP_DEBUG', false );

if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOT

# 権限を再度整える
chown apache:apache /var/www/html/wp-config.php

# --- WordPress設定の終わり ---

# 1. CloudWatch Agentのインストール
sudo yum install -y amazon-cloudwatch-agent

# 2. 設定ファイルの作成
# ※ヒアドキュメント(EOF)を使ってJSONを書き出す
cat <<EOF > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/httpd/access_log",
            "log_group_name": "/aws/ec2/${target_env}/wordpress-access-log",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

# 3. エージェントの起動
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s