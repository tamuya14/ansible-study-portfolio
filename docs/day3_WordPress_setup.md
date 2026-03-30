# Day3: 「Ansible Playbookによる構成管理の自動化とTerraform連携」の記録

**⚠️ 本ドキュメントの性質について**

このドキュメントは、本プロジェクト完成に至るまでの学習プロセスを記録したログです。
当時の試行錯誤やエラー解決の過程を重視して記述しているため、一部の手順やコードは最終的なリポジトリの構成（README参照）と異なる、または不十分な箇所があります。
最新かつ再現性のある構築手順については、ルートディレクトリの [README.md](/README.md) を参照してください。

---

## 1.目的と構成
**目的**:
 * UserDataで行っていたWebサーバの構築・WordPressの配置をPlaybook（`site.yml`）に集約し、Ansibleを用いたコードによる構成管理（IaC）を実現する。
 * Terraformで構築したインフラ情報（RDSエンドポイント等）をAnsibleへ自動的に受け渡し、かつデータベースのパスワードなどの機密情報を、ファイルに書き出すことなくAWS Secrets Managerから安全に取得・適用する仕組みを構築する。

**構成**：
 * SSH接続設定の共通化（`~/.ssh/config`）
 * Terraformの値をAnsibleへ自動引き渡し（`local_file`）
 * `lookup`プラグインを用いたメモリ上でのSecrets Managerからの動的なパスワード取得

**<イメージ図>**

 ![Terraform単独からAnsibleと連携した管理分担](/docs/images/Day3イメージ図.png)
<p align="center">図1：Terraform単独からAnsibleと連携した管理分担への移行</p>


**※検証方針**:
本演習では、Ansibleによる構成管理の有用性を厳密に検証するため、既存のUserDataによる自動構築をあえて排除し、OS起動後のミドルウェアインストールからWordPress配置までの全工程をAnsibleのみで完結させる手法をとる。


## 2. 作業プロセスと試行錯誤の記録
本環境の構築において直面した課題と、それをどのように解決したかの記録。

### ① 接続の効率化とホストキー問題
* **課題**:学習環境ではインスタンスの作成・削除が頻繁に行われるため、その都度発生する「ホストキーの不一致エラー」が障害となった。

* **対策**: `~/.ssh/config`に設定を集約。`StrictHostKeyChecking no `および` UserKnownHostsFile=/dev/null `を設定することで、セキュリティレベルを担保しつつ、接続エラーを回避した。

### ② ASGの「無限ループ」問題への対処
* **課題**:
 UserDataを削除したことでWordPressが未インストールとなり、ALBのヘルスチェック（ELB方式）が失敗、ASGがインスタンスを強制終了・再起動し続けるループが発生した。

* **対策**:
 ASGのヘルスチェックタイプを一時的に `ELB` から `EC2` へ切り替え、インスタンスの「生存」のみを確認するように修正。これにより、Ansibleを実行するための安定した時間を確保した。

### ③インフラ情報の受け渡し方法
* **課題**:
 Terraformで払い出されたRDSの接続先（エンドポイント）を、手動でAnsibleに転記するのは非効率であり、ミスを誘発する。

* **対策:**
 Terraformの `local_file` リソースを活用。`apply` 時に、Ansibleが自動的に読み込む `group_vars/all/db_config.yml` を直接生成する「出力の自動化」を採用した。

### ④-1【失敗】 シークレット取得モジュールの選定ミス
当初、`community.aws.secretsmanager_secret` モジュールによるシークレット取得を試みた。

* **発生したエラー**:
 ` Failed to update secret: Parameter validation failed: Invalid type for parameter SecretString, value: None `

* **分析**:
 `secretsmanager_secret` モジュールは「シークレットの作成・更新」を主目的としており、デフォルトの `state: present` では値を更新しようとしてしまう。取得専用のモジュールが手元の環境に見当たらず、タスクとしての実行に限界を感じた。

### ④-2【採用】 lookup プラグインによるオンメモリ取得
`ansible-doc` を活用したモジュール仕様の確認などを実施。タスクとしてシークレットを取得するのではなく、変数定義の中で `lookup` プラグイン（`amazon.aws.secretsmanager_secret`）を使用する方式を採用。

**本方式のメリット:**
* **非永続性**: 
 パスワードをディスク上のファイル（`group_vars`等）に一切書き出さないため、Git等への漏洩リスクをゼロにできる。

* **簡潔性**: 
 `register` や `changed_when` を用いた複雑なタスク記述が不要になり、`template` 内で直接変数を参照できる。


## 3. 構築の実行ログ

### 3.1. 事前準備：接続環境とASGの調整
Ansibleを確実に実行するため、接続設定の共通化と、検証の妨げになる自動復旧機能を一時的に調整。

1. **SSH接続の集約化 (`~/.ssh/config`)**
既存の`inventory.yml`で記述している踏み台経由の接続を簡略化するため、SSH接続設定を集約。
また、ホストキーエラーを防ぐ設定を追加。
`~/.ssh/config`に以下を追記
```bash
# --- AWS EC2 (SSMトンネル + Instance Connect + セキュリティ緩和) ---
Host i-* mi-*
    User ec2-user
    IdentityFile ~/.ssh/id_ed25519
    # ホストキーチェックをスキップする設定をここに集約
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    # ProxyCommand 内で鍵の登録(Instance Connect)とセッション開始(SSM)を連結
    ProxyCommand sh -c "aws ec2-instance-connect send-ssh-public-key --instance-id %h --instance-os-user ec2-user --ssh-public-key file://~/.ssh/id_ed25519.pub && aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p"
```

2. **ASGヘルスチェックの変更**
UserDataを削除すると、Webサーバが立ち上がるまでALBから「異常（Unhealthy）」と判定され、ASGがインスタンスを削除し続けてしまう。
既存のTerraform構成のうち、ASGの `health_check_type` を `ELB` から `EC2` に変更し、`apply` を実行。
これにより、Ansible実行中にインスタンスが勝手に削除される「無限ループ」を回避。
※変更したヘルスチェックタイプは今後学習する動的インベントリの導入まで、不要なエラーを防ぐために`EC2`のままにしておく。


### 3.2. Terraform連携設定（`ansible_config.tf`）
Ansibleが必要とする「公開情報（ホスト名やDB名、シークレットの名前）」のみをファイルに出力する。
※Terraformの変数は実際のものを入力
```bash
resource "local_file" "ansible_db_vars" {
  filename = "${path.module}/group_vars/all/db_config.yml"
  content  = <<EOT
db_host: "${module.database.db_host}"
db_name: "${module.database.db_name}"
db_user: "${module.database.db_user}"
db_secret_name: "${module.database.db_secret_name}"
EOT
}
```

### 3.3. RDSのシークレット名を出力(`modules/database/outputs.tf`への追記)
`ansible_config.tf`で設定した変数のうち、シークレット名のみ、現在の構成では`outputs`していない。
そのため、既存の`modules/database/outputs.tf`に以下を追記。
```bash
output "db_secret_name" {
  value = aws_secretsmanager_secret.db_password.name
}
```

### 3.4. IAM権限の適正化
EC2インスタンス（Ansible実行側）に付与するロールに、シークレット読み取りに必要な最小権限を定義する。
現在は`GetSecretValue` だけを設定しているが、加えてメタデータを参照するための `DescribeSecret` が必須となる。
既存の`modules/compute/iam.tf`に記載しているSecrets Managerにアクセスするためのポリシーに以下を追加。
```bash
# 権限追加の要点
Action = [
  "secretsmanager:GetSecretValue",
  "secretsmanager:DescribeSecret"  #追加
]
```

### 3.5. WordPressのDB設定テンプレートの作成
Ansibleの`templates`を用いて、Terraformから動的に取得したRDSの情報をもとに、
WordPressのDB設定ファイル(`wp-config.php`)を自動生成するテンプレートを作成する。
`templates`ディレクトリを作成し、その配下に`wp-config.php.j2`ファイルを作成。
`wp-config.php.j2`内に既存のUserData(`install_wp.sh`)にてヒアドキュメント(`cat <<EOT ~ EOT`)で流し込んだコードを貼り付ける。
※Terraformの変数からAnsibleの変数に変更することに注意!
※Shellが変数として読み込まないように回避していた`/`も削除することに注意!

```bash
<?php
define( 'DB_NAME', '{{ db_name }}' );
define( 'DB_USER', '{{ db_user }}' );
define( 'DB_PASSWORD', '{{ db_password }}' );
define( 'DB_HOST', '{{ db_host }}' );

define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );

$table_prefix = 'wp_';
define( 'WP_DEBUG', false );

if ( ! defined( 'ABSPATH' ) ) {
  define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
```

### 3.6. Playbook（site.yml）の実装
新規でルート（`inventory.yml`があるディレクトリ）に`site.yml`を作成する。
このファイル内にサーバ機能のインストールから、WordPressの配置、Jinja2テンプレート（.j2）を用いた設定ファイル（wp-config.php）の生成までを一括で行う。

<details>

<summary> ファイル詳細 </summary>

```yaml

- name: Setup WordPress Web Server
  hosts: web_servers
  become: true  # sudo 権限で実行することを意味

  tasks:
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

    - name: Start and enable httpd
      ansible.builtin.service:
        name: httpd
        state: started
        enabled: true

    - name: Start and enable php-fpm
      ansible.builtin.service:
        name: php-fpm
        state: started
        enabled: true

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
        src: templates/wp-config.php.j2
        dest: /var/www/html/wp-config.php
        owner: apache
        group: apache
        mode: '0644'
      vars:
        # lookupプラグインを使用して、直接パスワードを取得
        # ※ db_secret_name は group_vars/all/db_config.yml から自動的に読み込まれる
        db_password: "{{ lookup('amazon.aws.secretsmanager_secret', db_secret_name) }}"
      no_log: true

```

</details>

### 3.7. 環境のクリーンアップ
Ansibleによる構築をゼロから検証するため、あえて既存の設定を一度破棄。

1. **UserDataの無効化**
Terraformの起動テンプレートからUserDataをコメントアウトし、`apply` を実行。その後、既存のインスタンスを一度終了（Terminate）させ、新しい「真っさらな」インスタンスが起動するまで待機。

2. **インベントリの更新**
新規起動したインスタンスのIDを確認し、`inventory.yml` を書き換える。

### 3.8. Playbook実行前の準備
実行環境と必要ツールが準備できているか確認するための念のため以下のコマンドを実行。
```bash
# 仮想環境の有効化
source .venv/bin/activate
# コミュニティコレクションのインストール
ansible-galaxy collection install amazon.aws
```

### 3.9. Playbookの実行

既存のUserDataによる構築をクリーンアップした「真っさらな」インスタンスの準備と、
AnsibleによるWordPressセットアップのためのPlaybook(`site.yml`)、テンプレート(`wp-config.php.j2`)などの準備が完了したら、`ansible-playbook`を実行する。
実行前に再度以下の点をチェックする。

- [ ] ASGの`health_check_type` を`EC2`に変更。
- [ ] Terraformの起動テンプレート内の`user_data` 定義のコメントアウトと`apply`の実行。
- [ ] 既存のインスタンスの終了(Terminate)と新しく起動したインスタンスIDを`inventory.yml`に反映。
- [ ] `ansible_config.tf`の確認
- [ ] `templates/wp-config.php.j2`の確認
- [ ] `group_vars/all`ディレクトリの確認(`db_config.yml`は`ansible_config.tf`を作成後に`apply`していれば存在する)
- [ ] `ansible_config.tf`で設定した変数名と`templates/wp-config.php.j2`で設定した変数名の一致の確認
- [ ] `ansible_config.tf`で設定したTerraformの変数が`modules/database/outputs.tf`で出力されているかの確認
- [ ] `インスタンスに付与する権限の確認

以上を確認し、不備なく設定できていれば以下コマンドを実行。
```bash
ansible-playbook -i inventory.yml site.yml
```

Taskの結果が`ok`もしくは`changed`であれば、成功。



## 4. 技術的考察・まとめ（Tips）

* **宣言的インフラの神髄**:
 `dnf` や `service` モジュールにおいて「どのような状態（state）であるべきか」を記述するだけで、Ansibleが現状を判断して差分のみを実行する「冪等性」の利便性を体感できた。

* **情報の仕分け**: 
 「インフラ構成情報（Terraformが知っていること）」と「機密情報（Secrets Managerが知っていること）」を明確に分け、Ansibleをその仲介役として正しく配置できた。

* **データ型の意識**:
 `from_json` 使用時に発生した `Expecting value: line 1 column 1` エラーを通じ、取得データが「JSON形式の文字列」なのか「生のプレーンテキスト」なのかを以下のようなデバッグタスク（debug）で確認することの重要性を再認識した。

```bash
- name: Debug Secret Value (一時的な確認用)
      debug:
        msg: "取得した値は: {{ lookup('amazon.aws.secretsmanager_secret', db_secret_name) }}"
```

* **冪等性の維持**:
 シークレット取得を `lookup` で行うことで、設定変更がない限り「常にOK」の状態を保てるようになり、Ansibleの冪等性を損なわない設計が実現できた。

* **`ansible-doc` の活用**:
 シークレット取得タスクで、エラーが発生した際に、`ansible-doc`を活用することで、モジュール選定のミスに気づき、正しいモジュールに修正することができた。モジュール関係で困ったら、まずは`ansible-doc`を活用する。

* **`no_log: true` の重要性**:
 `site.yml`内のテンプレートタスクでにて機密情報（RDSのパスワード）の取得を実行している。そのため、Ansibleの実行ログへの機密情報の混入を防ぐため、機密情報を扱うタスクには `no_log: true` を適用した。これにより、CI/CDパイプライン上でログが共有されても、機密情報が流出しない安全な運用を実現した。
---
