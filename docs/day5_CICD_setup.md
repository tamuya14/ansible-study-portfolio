# Day 5: 「フルオートメーションの実装 〜GitHub ActionsによるCI/CDと環境分離〜」の記録

**⚠️ 本ドキュメントの性質について**

このドキュメントは、本プロジェクト完成に至るまでの学習プロセスを記録したログです。
当時の試行錯誤やエラー解決の過程を重視して記述しているため、一部の手順やコードは最終的なリポジトリの構成（README参照）と異なる、または不十分な箇所があります。
最新かつ再現性のある構築手順については、ルートディレクトリの [README.md](/README.md) を参照してください。

---

## 1. 目的と構成

**目的**:
- **CI/CDの実装**: 
  GitHubへの `push` をトリガーに、Terraformによるインフラ更新とAnsibleによる構成管理をシーケンシャルに実行し、「手動操作ゼロ」のデプロイフローを実現する。また、プルリクエストによる承認を経由することで運用環境を壊すリスクを抑制する。

- **環境分離の厳密化**: 
  `main` (prd) と `dev` ブランチを運用し、Terraform WorkspaceとAWSタグによるAnsibleの動的インベントリフィルタを連動させることで、1つのコードから完全に独立した2環境を制御する。

- **コード品質の担保**: 
  静的解析(`ansible-lint`) をパイプラインに組み込み、構文エラーやベストプラクティス違反をデプロイ前に自動検知する。


**構成**:
- **GitHub Actions**: Terraform (Plan/Apply) と Ansible (Playbook) の統合ワークフロー。
- **CIパイプライン**: ansible-lint による自動構文チェック、Terraform Apply後のAnsible自動実行（SSM経由）。
- **環境識別**: Terraform `default_tags` と Ansible `filters` によるタグベースのターゲット管理。
- **スケジュール削除**: 開発環境のコスト最適化のための `cron` 実行。


**<イメージ図>**

- **GitHub Actionsによるデプロイフロー**: 
workspaceとタグを用いたフィルターによって、１つのコードで異なる環境が構築できることを表現。

![GitHub Actionsによるデプロイフローのイメージ図](/docs/images/Day5イメージ図.png)
<p align="center">図1：GitHub Actionsによるデプロイフロー</p>

## 2. 作業プロセスと試行錯誤の記録

### ① GitHub Actions における「Python環境の不一致」と解決
- **課題**:
Actions上で動的インベントリやAWS連携（Secrets Manager等）を実行した際、boto3 をインストールしているにもかかわらず、Ansible実行時に「Pythonモジュールが見つからない」というエラーが発生し、Playbookが停止した。

> 実際のエラーログ：
 Failed to import the required Python library (botocore and boto3) on runnervm46oaq's Python /opt/pipx/venvs/ansible-core/bin/python.

- **原因分析**:
 GitHub Actionsの標準環境では、Ansible本体が pipx による独立した仮想環境で管理されている一方、追加ライブラリ（boto3）をシステム側のPythonにインストールしていたため、「Ansibleが動いているPython環境」と「ライブラリが存在する環境」が分離していたことが原因であった。

- **対策/成果**:
 当初は pipx inject で個別注入を試みたが、最終的に python3 -m pip を用いて ansible-core と boto3 を同一のシステム環境へ一括インストールする構成へ変更。環境変数や interpreter オプションによる複雑なパス指定を排除し、Ansible本体とライブラリの参照先を完全に一致させることで、シンプルかつ堅牢な実行基盤を確立した。


### ② 秘密鍵（SSH）のセキュアかつ正確な搬送
- **課題**: 
  GitHub Secretsに保存した秘密鍵をファイル化して接続しようとしたが、「形式不正」でSSH接続が拒否された。
- **原因分析**: 
  `echo` を用いた流し込みにより改行コードや末尾の空行が崩れていたこと、また `BEGIN/END` 行の欠落、さらに対応する公開鍵がインスタンス側に正しく配置されていなかった。
- **対策/成果**: 
  Secretsへの保存形式をヘッダー含め厳密に管理し、`cat` コマンドで安全にファイル化。また、Terraform側で公開鍵を生成しASGへ渡すフローを確立。セキュリティと自動化の両立に成功した。

### ③ ASGにおけるタグ伝播（Propagate at launch）の罠
- **課題**: 
  Terraformで `default_tags` を設定したが、ASGによって起動した新しいインスタンスに `Env` タグが付与されず、Ansibleのフィルタにヒットしなかった。
- **原因分析**: 
  `default_tags` はASGリソース自体には付与されるが、そこから派生するEC2インスタンスには自動伝播しない仕様であった。
- **対策/成果**: 
  `aws_autoscaling_group` 内に個別の `tag` ブロックを定義し、`propagate_at_launch = true` を明示。これにより、動的インベントリが常に正しい環境（dev/prd）のインスタンスを識別できるようになった。

### ④ ヘルスチェック猶予期間とプロビジョニングの競合
- **課題**: 
  初回デプロイ時、RDSの作成待ちやAnsibleの実行中にASGのヘルスチェック（ELB）がタイムアウトし、インスタンスが強制終了（Terminated）されてしまった。
- **対策**: 
  `health_check_grace_period` を適切な値（例: 300〜600秒）に調整。また、失敗時はActionsの `Re-run` を活用し、インフラが安定した状態で構成管理を再試行する運用フローを確立した。

### ⑤ 継続的な品質管理：Ansible Lintの導入
- **課題**:
 WordPressのセットアップにCloudWatchエージェントの導入、そしてRole化などコードの数が増加したことで、手動ですべての記述を１つ１つ確認することに限界が生じた。

- **対策**:
　`ansible-lint`を活用し、自動解析を導入。また、`ansible-lint`による修正指示によって、将来的なモジュール衝突を防ぐFQCN（完全修飾コレクション名）の重要性などを理解。また、同時にVS Codeの機能を用いた効率的な置換方法を習得。


## 3. 構築の実行ログ

### 3.1. 自動クリーンアップの実装
リソースの消し忘れによるコスト増加を防ぐため、深夜０時に自動で`terraform destroy`を実行するワークフローを作成。
 - **ポイント**: `workflow_dispatch` を付与し、手動での一括削除も可能に。

<details>

<summary> 作成した`.github/workflows/cleanup.yml`の詳細 </summary>

```yaml
name: Scheduled Resource Cleanup

on:
  schedule:
    # 毎日 日本時間 深夜0時（UTC 15:00）に実行
    - cron: '0 15 * * *'
  workflow_dispatch: # ボタンから手動実行も可能にする設定

permissions:
  id-token: write
  contents: read

jobs:
  destroy:
    runs-on: ubuntu-latest
    env:
      # 消し忘れ防止のため、基本的には dev 環境を対象とする例
      TF_WORKSPACE: dev 
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-role
          aws-region: ap-northeast-1

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: terraform init

      - name: Terraform Destroy
        run: terraform destroy -auto-approve
```

</details>


### 3.2. Ansibleコードの標準化（Lint対応）
手元で`ansible-lint` を実行し、既存のPlaybookを最新のベストプラクティスに適合させる。
VS Codeの一括置換機能を活用し、効率的に修正を行う。

**主な修正点**
- `yes / no `を `true / false` へ統一。

- 全てのモジュールをFQCN形式（`ansible.builtin.xxx`）へ変換。

- ファイル末尾の改行やパーミッション設定（`mode: '0644'`）を補完。

`ansible-lint`による修正が完了したら、Actionsで実行するための専用のワークフローを作成。

<details>
<summary> `.github/workflows/ansible-lint.yml`の詳細 </summary>

```yaml
name: Ansible Lint

on:
  push:
    branches: [ main, dev ]
  pull_request:
    branches: [ main, dev ]

jobs:
  ansible-lint:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.9'

      - name: Install ansible-lint
        run: |
          pip install ansible-lint

      - name: Run ansible-lint
        # 修正した site.yml と roles ディレクトリを対象にします
        run: ansible-lint site.yml roles/
```
</details>


### 3.3. GitHub Actions ワークフローの実装 (`terraform.yml`)
Terraform、Ansibleを1つのパイプラインに統合。
Ansible統合に合わせて、ActionsがAnsibleを実行するためのステップを`terraform.yml`に追加。

- SSH Keyの配置: Secretsから秘密鍵を復元し、公開鍵も生成。

- SSH Config: Session Managerを `ProxyCommand` に組み込み、Actions環境から直接EC2を操作可能にする。

> ※事前にGitHub シークレットに現在使用している秘密鍵(`-`による`BEGIN/END` 行の区切りを含む)を保存する。
加えて、AnsibleがPlaybookを実行する前にEC2の起動準備時間を想定した、「まず接続できるまで待つ」タスクをPlaybookに追加。

- `site.yml`を以下のように修正。
```yml
- name: Setup WordPress Web Server
  hosts: web_servers
  become: true
  gather_facts: false # 接続できる前にファクト（OS情報）を取りに行くとエラーになるため、一旦false

  pre_tasks:
    - name: Wait for instance to be reachable via SSM
      ansible.builtin.wait_for_connection:
        timeout: 300 # 最大5分待機
        delay: 5      # 5秒ごとに試行

    - name: Gather facts after connection is established
      ansible.builtin.setup: # ここで手動でファクトを取得

  roles:
    - cloudwatch_agent
    - wordpress
```

- `terraform.yml`にAnsible実行ステップを追加。
<details>

<summary> `terraform.yml`詳細 </summary>

```yaml

# 既存の`terraform apply`までのタスク

      # 9. Ansible 用の SSH 秘密鍵を配置
      - name: Setup SSH key
        run: |
          mkdir -p ~/.ssh
          cat <<'EOF' > ~/.ssh/id_ed25519
          ${{ secrets.SSH_PRIVATE_KEY }}
          EOF
          chmod 600 ~/.ssh/id_ed25519
          ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub

      # 10. GitHub Actions 用の SSH Config 生成
      - name: Create SSH Config
        run: |
          cat <<EOT >> ~/.ssh/config
          Host i-* mi-*
              User ec2-user
              IdentityFile ~/.ssh/id_ed25519
              StrictHostKeyChecking no
              UserKnownHostsFile /dev/null
              ProxyCommand sh -c "aws ec2-instance-connect send-ssh-public-key --instance-id %h --instance-os-user ec2-user --ssh-public-key file://~/.ssh/id_ed25519.pub && aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p"
          EOT


      # 11. Ansible の実行
      - name: Run Ansible Playbook
        if: github.event_name == 'push' # Apply が成功した時だけ実行
        env:
          ANSIBLE_HOST_KEY_CHECKING: "False"

        run: |
          # 1. システム側に追加ライブラリ(boto3)とAnsible本体(ansible-core)をインストール
          python3 -m pip install --upgrade pip
          python3 -m pip install boto3 botocore ansible-core

          # 2. 必要なコレクションのインストール
          ansible-galaxy collection install amazon.aws

          # 3. 実行
          ansible-playbook -i inventory.aws_ec2.yml site.yml 
 
```
</details>

### 3.4. Terraform：デフォルトタグの導入/`local`プロバイダーの定義
全リソースへの環境識別タグ付与を自動化。
また、`ansible_config.tf`内で使用している`local_file`リソース作成のため、`local`プロバイダーの定義も追加。

既存のルートにある`main.tf`にデフォルトタグ/プロバイダー定義を追加。
<details>
<summary> `main.tf`の詳細 </summary>

```hcl
terraform {
  required_version = "~> 1.14.0"

backend "s3" {
   # 既存のバックエンド設定
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # ここを追加
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
```
</details>

### 3.5. ASG：インスタンスへのタグ伝播設定
EC2インスタンスが確実にAnsibleのフィルタに掛かるように設定。
既存の`modules/compute/main.tf`内にあるASGの定義に以下を追加。

```hcl
resource "aws_autoscaling_group" "web" {
  # ...
  tag {
    key                 = "Env"
    value               = terraform.workspace
    propagate_at_launch = true # 必須設定
  }
}
```

### 3.6. Ansible：動的インベントリの環境フィルタリング
実行時の環境変数に応じて対象を自動で切り替える。
`inventory.aws_ec2.yml`に以下を追加。

```yaml

filters:
  tag:Env: "{{ lookup('env', 'TF_WORKSPACE') }}"
  instance-state-name: running
```

### 3.7. ブランチ戦略と環境分離
作業用ブランチと、`dev`ブランチを作成。
作業用ブランチに`push`し、GitHubのリポジトリからプルリクエスト経由で`dev`へ反映させることで、マージ前に検証するフローを実装。
`dev`へのマージが完了したら、`main`へプルリクエスト・マージを行う。
Actionsの実行ログを確認し、`dev`と`main`でPlaybookが操作しているインスタンスが異なることを確認。
これにより、異なる環境を１つのコードで操作する環境分離を実装できた。


## 4. 技術的考察・まとめ（Tips）

- **疎結合な環境分離**:
  `lookup('env', ...)` を使うことで、Ansibleのコード自体に `dev` や `prd` といった値をハードコードせず、実行環境（GitHub Actions）から注入する「疎結合」な設計を実現できた。また、`Terraform Workspace` + `GitHub Branch` + `Ansible Dynamic Inventory Filter` を組み合わせることで、開発者が意識せずとも適切な環境に適切な設定が流れる「安全なレール」を敷くことができた。

- **CI/CDによる「証跡」の重要性**:
  すべての失敗（PythonエラーやSSH拒否）がActionsのログに残り、それを一つずつ確認、解消していくことで、原因特定と構築の成功につながった。

- **運用のレジリエンス（回復力）**:
  ヘルスチェックによる意図しない終了に対し、`Re-run` という再試行手段を持つことで、不確実なクラウド環境下でも最終的に「あるべき状態」へ到達できる仕組みを構築できた。

- **ansible-lint によるシフトレフト**:
 PR（プルリクエスト）の段階で静的解析を行うことで、実行環境でのエラーを未然に防ぎ、デバッグ時間を大幅に短縮できた。

- **Ansibleの実行環境(Python)の管理**:
 エラー解消を通じて、システムで利用されるPythonとAnsibleが利用するPythonがことなることを理解した。そして、自動化環境では「どのPythonが動いているか」を常に意識すべきということを理解した。GitHubの標準環境のようなその場限りで構築される環境では、システムに直接追加ライブラリやAnsibleの本体をインストールすることで、複雑な指定を排除し、シンプルなコードを実現できた。

- **動的インベントリの依存性**:
 Playbookを実行する「前段」で、必要なコレクションやライブラリをセットアップする工程をパイプラインに組み込むことが、自律的な自動化には不可欠であることを学んだ。

- **秘密情報の完全な復元**:
 秘密鍵は単なる文字列ではなく「構造体」であることを理解した。`cat` やヒアドキュメントを用い、改行やヘッダーを含む「そのままの形」で復元することが、SSH認証トラブルを防ぐ道であることを学んだ。

- **イミュータブルな運用意識**:
 ASGのタグ伝播問題を通じ、クラウドでは「既存を直す」のではなく「設定を変えて焼き直す（再起動・再生成）」という不変インフラ（Immutable Infrastructure）の思考が重要であることを学んだ。
 
---

