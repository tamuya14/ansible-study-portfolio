# Day4: 「Ansible Roleによる構造化とAWS動的インベントリの導入」の記録

**⚠️ 本ドキュメントの性質について**

このドキュメントは、本プロジェクト完成に至るまでの学習プロセスを記録したログです。
当時の試行錯誤やエラー解決の過程を重視して記述しているため、一部の手順やコードは最終的なリポジトリの構成（README参照）と異なる、または不十分な箇所があります。
最新かつ再現性のある構築手順については、ルートディレクトリの [README.md](/README.md) を参照してください。

---

## 1. 目的と構成

**目的**:
- **Role(ロール)化**:
 肥大化した `site.yml` を機能単位（WordPress, CloudWatch Agent）に分割・整理し、再利用性と保守性の高いコード構造を実現する。

- **動的インベントリ(Dynamic Inventory)**:
 AWS APIと連携し、EC2のタグ情報から接続対象を自動抽出することで、インスタンスIDの手動管理（`inventory.yml`）を完全に撤廃する。
 また、インスタンスの増減やID変更に左右されない運用基盤を構築する。

**構成**:
- **Role構造**: CloudWatch Agent用とWordPress用に分割管理。

- **動的インベントリ**: AWS EC2プラグインによる自動ターゲット抽出。

- **AWS連携**: TerraformタグとAnsibleグループの紐付け。

- **SSH接続の動的紐付け**: インスタンスIDをキーにした ~/.ssh/config との自動連携

**<イメージ図>**

- **動的インベントリによる自動ターゲット抽出**:
 AWSタグをキーにインスタンスを自動認識し、Session Managerトンネル経由で安全に接続する「運用の自動化」を表現。
 
![動的インベントリによる自動ターゲット抽出](/docs/images/Day4イメージ図1.png) 
<p align="center">図1：AWS動的インベントリと接続経路の概要</p>

- **Roleによる構成の部品化**:
 処理（Role）と変数（group_vars）を分離し、site.yml でそれらを組み合わせる「保守性の高い設計」を表現。
 
![Roleによる構成の部品化](/docs/images/Day4イメージ図2.png) 
<p align="center">図2：Ansible Role構造と変数の依存関係</p>


## 2. 作業プロセスと試行錯誤の記録

### ①ロール化による「設定のポータビリティ」向上
- **課題**:
 `site.yml` に全タスクを記述すると、特定の機能（監視だけ、Webだけ）を再利用することが難しく、コードの可読性も低下する。

- **対策**:
 Ansibleの標準的な階層構造（`tasks`, `templates`, `handlers`）に従いロール化。`site.yml` は「どのホストに、どのロールを適用するか」を宣言するだけのシンプルな定義ファイルへ修正した。

- **成果**:
 `tasks`, `handlers`, `templates` が自動的に関連付けられる「暗黙の規約」により、パス指定が簡略化され、ポータビリティ（持ち運びやすさ）が向上。
 Playbook本体（site.yml）が非常にスリムになり、全体の構成が把握しやすくなった。


### ②ハンドラ（Handlers）による効率的な再起動
- **課題**:
 設定に変更を加えた時にはシステムの再起動が必要となる。だが、Taskとして再起動を記述するとPlaybookの実行をするたびに再起動が発生し、システムの中断を引き起こす可能性がある。

- **対策**:
 CloudWatch Agentの設定変更時のみサービスを再起動する `notify` と `handlers` を実装。

- **成果**:
 Playbookの実行時、毎回サービスを再起動するのではなく、「変更があった時だけ」動く仕組みにすることで、不要なサービス中断を防ぎ、冪等性をより高いレベルで維持できる。


### ③手動インベントリ管理の限界と自動化

- **課題**:
 ASGによるインスタンスの入れ替わりや、検証ごとの `destroy` & `apply` のたびに、最新のインスタンスIDを調べて `inventory.yml` を書き換える作業が運用のボトルネックとなっていた。

- **対策**:
 `amazon.aws.aws_ec2` プラグインを導入。Terraform側で付与した `Role: web_server` タグをキーに、Ansibleが実行時に最新のターゲットを自動的に取得する仕組みを構築した。

- **成果**:
 `filters` で「タグ（Role: web_server）」を指定することで、Auto Scaling等でインスタンスが入れ替わっても、Ansibleは常に正しいターゲットを自動認識できるようになり、インスタンスIDを手動で設定せずともインスタンスの設定を行える仕組みを実現。


### ④動的インベントリにおける接続エラー（SSH タイムアウト）

- **課題**:
 動的インベントリ導入後、ターゲットは認識されるものの SSH 接続がタイムアウトする事象が発生した。

- **原因分析**:
 動的インベントリがデフォルトで「内部DNS名」をホスト名として取得していたため、` ~/.ssh/config` で定義していた `Host i-*`（インスタンスID指定）の設定とマッチせず、ProxyCommandが実行されていなかった。

- **対策/成果**:
 `inventory.aws_ec2.yml` の `compose` 機能を使い、Ansible上のホスト変数を強制的に `instance_id` へマッピング。これにより、動的なリスト取得と既存のProxyCommandを用いた接続経路（Instance Connect + SSM）の共存に成功した。


## 3. 構築の実行ログ

### 3.1. ロール構造の作成
機能ごとにディレクトリを分離し、規約に基づいた配置を行う。

```bash
# ロールディレクトリの作成
mkdir -p roles/wordpress/{tasks,templates}
mkdir -p roles/cloudwatch_agent/{tasks,templates,handlers}
```

### 3.2. CloudWatch Agent ロールの実装
設定ファイルの配置と、設定変更時のみ実行される `handlers` を定義。

1. `roles/cloudwatch_agent/tasks/main.yml` に以下を記述。
パッケージのインストール後、`systemctl daemon-reload` を実行してOSにサービスを認識させるタスクを追加する。
<details>

<summary> ファイル詳細</summary>

```bash
- name: Install CloudWatch Agent
  ansible.builtin.dnf:
    name: amazon-cloudwatch-agent
    state: present

- name: Reload systemd daemon
  ansible.builtin.command: systemctl daemon-reload

- name: Create CloudWatch Agent config file from template
  ansible.builtin.template:
    src: amazon-cloudwatch-agent.json.j2
    dest: /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    owner: root
    group: root
    mode: '0644'
  notify: Restart CloudWatch Agent

- name: Start and enable CloudWatch Agent
  ansible.builtin.service:
    name: amazon-cloudwatch-agent
    state: started
    enabled: true
```

</details>

2. `roles/cloudwatch_agent/handlers/main.yml` に以下を記述。
設定ファイルの更新時のみエージェントを再起動する処理を共通化。
<details>

<summary> ファイル詳細</summary>

```bash
- name: Restart CloudWatch Agent
  ansible.builtin.service:
    name: amazon-cloudwatch-agent
    state: restarted
```

</details>

3. `roles/cloudwatch_agent/templates/amazon-cloudwatch-agent.json.j2`に以下を記述。
UserDataで記述していた形式と変数(`target_env`)の記述方法が異なることに注意。
```bash
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/httpd/access_log",
            "log_group_name": "/aws/ec2/{{ target_env }}/wordpress-access-log",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
```

### 3.3. WordPress ロールの実装

1. `roles/wordpress/tasks/main.yml`に以下を記述。
基本的には`site.yml` から WordPress 関連タスクを `roles/wordpress/tasks/main.yml` への移動だけだが、より記述をスリムにするために、`{{ item }}`と`loop`を利用し、システム起動タスクを1つにまとめる。また、テンプレートパスはロール内の `templates/` を自動参照するため、相対パスを簡略化した。

<details>

<summary> ファイル詳細</summary>

```bash
- name: Install Apache and PHP packages
  ansible.builtin.dnf:
    name:
      - httpd
      - php
      - php-mysqlnd
      - php-gd
      - php-xml
      - php-mbstring
      - php-fpm
      - mariadb105
    state: present
    update_cache: true

- name: Ensure python3-pip is installed
  ansible.builtin.dnf: # Amazon Linux 2023等の場合。Ubuntuならapt。
    name: python3-pip
    state: present

- name: Install required Python libraries for AWS
  ansible.builtin.pip:
    name:
      - boto3
      - botocore
    state: present
    executable: pip3

- name: Start and enable services
  ansible.builtin.service:
    name: "{{ item }}"
    state: started
    enabled: true
  loop:
    - httpd
    - php-fpm

- name: Download WordPress
  ansible.builtin.get_url:
    url: https://ja.wordpress.org/latest-ja.tar.gz
    dest: /tmp/latest-ja.tar.gz

- name: Extract WordPress
  ansible.builtin.unarchive:
    src: /tmp/latest-ja.tar.gz
    dest: /var/www/html/
    remote_src: true
    creates: /var/www/html/wp-settings.php
    extra_opts: [--strip-components=1] # 解凍時にディレクトリ階層を1つ上に上げる設定

- name: Set permissions for WordPress
  ansible.builtin.file:
    path: /var/www/html
    owner: apache
    group: apache
    recurse: true
    
- name: Create wp-config.php
  ansible.builtin.template:
    src: wp-config.php.j2
    dest: /var/www/html/wp-config.php
    owner: apache
    group: apache
    mode: '0644'
  vars:
    # lookupプラグインを使用して、直接パスワードを取得
    # ※ db_secret_name は group_vars/all/db_config.yml から自動的に読まれます
    db_password: "{{ lookup('amazon.aws.secretsmanager_secret', db_secret_name) }}"
  no_log: true

```
</details>

2. `templates/wp-config.php.j2`の移動
`site.yml` と同じ場所にある `templates/wp-config.php.j2` を、新しく作成したロール(`roles/wordpress/templates`)の中に移動。

```bash
mv templates/wp-config.php.j2 roles/wordpress/templates/
```

### 3.4. 動的インベントリの設定 (inventory.aws_ec2.yml)
特定のタグを持つ、実行中のインスタンスのみを自動抽出する設定。
プロジェクトのルートに`inventory.aws_ec2.yml`を作成し、以下を記述。
```bash
plugin: amazon.aws.aws_ec2
regions:
  - ap-northeast-1
filters:
  tag:Role: web_server  # Terraformで付与したタグでフィルタ
  instance-state-name: running
keyed_groups:
  - prefix: tag
    key: tags
compose:
  ansible_host: instance_id # ホスト名をIDに変換して~/.ssh/configとマッチさせる
  ansible_user: "'ec2-user'"
  ansible_python_interpreter: "'/usr/bin/python3.9'"
groups:
  web_servers: "'web_server' in tags.Role" # 既存のPlaybookのhosts指定を維持
```


### 3.5. Terraform側の修正（タグの追加と`target_env`の受け渡し）
1. **タグの付与**:
 `modules/compute/main.tf` 内のASG設定に `Role: web_server` タグを追加。
```bash
 # Role タグ (Ansible用)
  tag {
    key                 = "Role"
    value               = "web_server"
    propagate_at_launch = true
  }
```

2. **変数の受け渡し**:
`ansible_config.tf`に以下を追記。
`target_env`を別の変数ファイルとして書き出す。
```bash
resource "local_file" "env_vars" {
  filename = "${path.module}/group_vars/all/env_vars.yml"
  content  = <<EOT
target_env: "${terraform.workspace}"
EOT
}
```

3. **設定の反映**:
タグの追加と変数の書き出し設定が完了したら、設定を反映させるため、再度`terraform apply`を実行。
また、既存のインスタンスが存在する場合、ASGのタグ追加が反映されないので、既存のインスタンスを終了させる。



### 3.6. Playbook（site.yml）のスリム化
ロールを呼び出すだけのシンプルな形に修正。
```bash
- name: Setup Web Server
  hosts: web_servers
  become: true
  roles:
    - cloudwatch_agent
    - wordpress
```

### 3.7. 動的インベントリを用いたPlaybookの実行
Playbookを実行する際に新しく作成した動的インベントリを参照するよう指定する。
`ansible-playbook -i inventory.aws_ec2.yml site.yml `

タスクが成功したら、動的インベントリとロール化の成功。


### 3.8. ヘルスチェックタイプの修正
Day3の演習にてUserDataの削除に伴い、一時的にASGのヘルスチェックタイプを `EC2` に変更していた。
だが、今回、動的インベントリにより即座に新しいインスタンスへ接続可能になった。
そのため、`health_check_type` を `ELB` に戻し、本番環境同様の死活監視を有効化。
```bash
resource "aws_autoscaling_group" "web" { 
# ... (既存設定) ...
 health_check_type         = "ELB"
  health_check_grace_period = 300 
# ... (既存設定) ...
}
```


## 4. 技術的考察・まとめ（Tips）

- **Ansible Vaultの見送り**:
 セキュリティレベルを検討した結果、AWS Secrets Managerを既に導入している本環境において、Vault（ファイル暗号化）を重ねて導入する複雑さよりも、既存のクラウドネイティブな仕組みを優先。

- **Roleによる暗黙の規約**:
 ロール内の `tasks` からは `templates/` フォルダをフルパス指定なしで参照できる。この「規約による簡略化」が、コードの可読性とポータビリティを支えていることを実感した。

- **動的インベントリの柔軟性**:
`compose` 機能を使い、取得したデータに `ansible_host: instance_id` などの別名を付与することで、既存のSSH設定（`.ssh/config`）を一切変えずに自動化を継続できた。

- **運用フェーズへの移行**:
ASGのヘルスチェックを `ELB` に戻しても、インスタンスの入れ替わりをAnsibleが自動追随できるようになった。これにより、「構築して終わり」ではなく「変化し続けるクラウド環境を管理し続ける」準備が整った。

- **`item` と `loop` によるタスクの抽象化**:
これまで複数の service タスクとして記述していた処理を、loop を用いて1つに集約。
  - メリット:
    - 可読性: 処理（起動・有効化）と対象（httpd, php-fpm）を分離することで、「何をするタスクか」が直感的に理解できる。

    - 拡張性: 今後管理するサービスが増えた際も、リストに1行追加するだけで対応でき、Playbook全体の肥大化を防げる。

    - 保守性: `state: started` などの設定値を変更したい場合、1箇所の修正で全対象に反映されるため、修正漏れのリスクが激減。
---
