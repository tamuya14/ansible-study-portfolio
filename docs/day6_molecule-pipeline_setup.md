# Day 6: 「テスト駆動インフラ開発の実装 〜Moleculeによる品質保証とローリングアップデート〜」の記録

**⚠️ 本ドキュメントの性質について**

このドキュメントは、本プロジェクト完成に至るまでの学習プロセスを記録したログ。
当時の試行錯誤やエラー解決の過程を重視して記述しているため、一部の手順やコードは最終的なリポジトリの構成（README参照）と異なる、または不十分な箇所があります。
最新かつ再現性のある構築手順については、ルートディレクトリの [README.md](/README.md) を参照してください。

---

## 1. 目的と構成

**目的**:

  - **インフラのユニットテスト実装**:
    Ansible Role単位でのテストフレームワーク `Molecule` を導入し、コード変更が既存機能（Apache/PHP等）を壊していないかをコンテナ環境で自動検証する。

  - **「壊れない」パイプラインの構築**:
    Lint（静的解析）→ Molecule（動的テスト）→ Terraform（インフラ更新）を `needs` キーワードで連結し、テストに合格したコードのみが本番デプロイに進める「信頼の連鎖」を構築する。

  - **ゼロダウンタイムへの布石**:
    `serial: 1` によるローリングアップデートを実装し、複数台構成においてサービスを継続しながら1台ずつ安全に更新する制御手法を習得する。

**構成**:

  - **Molecule & Testinfra**: Docker (Amazon Linux 2023) を用いた、インフラの「状態」をコードで定義・検証する仕組み。
  - **統合CI/CDパイプライン**: 3つのワークフロー（Lint/Test/Deploy）を1つの `.yml` に統合し、依存関係を制御。
  - **ローリングアップデート**: Ansibleの実行制御による、段階的なパッケージ更新と再起動の管理。

**<イメージ図>**

  - **CI/CD Pipeline & Safe Deployment Flow**:
    - Lint(OK) -\> Molecule(OK) -\> Plan(OK) -\> [Merge] -\> Apply の流れを視覚化。
    - `serial:1`によるローリングアップデートを視覚化。
    ![CI/CD Pipeline & Safe Deployment Flow](/docs/images/Day6イメージ図.png)
    <p align="center">図1：統合パイプラインの依存関係/ローリングアップデート図</p>
---

## 2. 作業プロセスと試行錯誤の記録

### ① Molecule状態管理の不整合とカスタムファイルの罠
  - **課題**:
    Molecule実行時、コンテナが存在しないにもかかわらず「作成済み（Skipped）」と表示され、テストが進まない「ゾンビ状態」に陥った。

  - **原因分析**:
    Docker DesktopのハングアップによりMoleculeの内部キャッシュ（State）と実環境が乖離したこと、および `molecule/default/` 内に古い形式の `create.yml` が存在していたため、最新のDockerドライバによる標準ロジックが阻害されていたことが判明した。

  - **対策/成果**:
    `create.yml` 等のカスタムファイルを削除し、「標準機能への回帰」を選択。Molecule内蔵の最新ロジックに任せることで、最もメンテナンス性の高い「最小構成」での安定稼働を実現した。

### ② ツール依存関係のフェーズ：実行主体の取り違え
  - **課題**:
    Ansible実行時に `boto3` や `botocore` が見つからないエラーが発生。コンテナ内にインストールしても解消しなかった。

  - **原因分析**:
    `lookup` プラグインや動的インベントリ・プラグインは、操作対象（コンテナ）ではなく、**コントロールノード（GitHub Actions Runner自身）**で動作するという「実行主体の違い」を見落としていた。

  - **対策/成果**:
    Actionsのワークフローステップで `pip install boto3 botocore` を実行。Ansibleの動作メカニズム（LocalアクションとRemoteアクションの区別）を深く理解する契機となった。

### ③ GitHub Actions (Cgroup V2) と systemd の競合

  - **課題**:
    GitHub Actions上でMoleculeを実行した際、Amazon Linux 2023コンテナの起動に失敗し、`Exit 255` で即座に終了した。それに伴い `Gathering Facts` も疎通不可で停止した。

  - **原因分析**:
    Actionsのホスト環境（Ubuntu 22.04以降）が採用している **Cgroup V2** と、コンテナ内の **systemd** のリソース管理の視界が不一致を起こしていた。また、コンテナ内のPythonパスが自動検知されず、一時ディレクトリの作成権限エラーを誘発していた。

  - **対策/成果**:
    `molecule.yml` に `privileged: true`、`volumes: /sys/fs/cgroup` に加え、**`cgroupns_mode: host`** を明示的に追加。ホストとコンテナの視界を一致させることで、コンテナ内での systemd 起動を安定させた。また、`ansible_python_interpreter` を `/usr/bin/python3` に固定し、接続性を確保した。

### ④ Lookup プラグインの「先行評価」による認証エラー

  - **課題**:
    Moleculeテスト（Docker環境）を実行しているだけなのに、AWS Secrets Managerへの lookup が走り、`NoRegionError` や `NoCredentialsError` でテストが中断した。

  - **原因分析**:
    AnsibleのJinja2テンプレート評価において、たとえデフォルト値（`| default`）が設定されていても、式の中に `lookup` が含まれているだけで、プラグインが接続初期化を試みてしまう「先行評価」の性質が原因であった。

  - **対策/成果**:
    `molecule.yml` の `provisioner.env` にダミーのAWS認証情報を注入し、プラグインの初期化をパスさせた。また、変数が定義済みであれば `lookup` 自体を行わない「遅延評価的」な記述をタスク側に徹底することで、外部依存のない純粋なユニットテストを実現した。

### ⑤ Testinfraにおける「コマンド不在」の検知

  - **課題**:
    `molecule verify` 実行時、ポート80の疎通確認テストのみが `RuntimeError` で失敗した。

  - **原因分析**:
    テストツール（Testinfra）がポート確認に使用する `ss` や `netstat` コマンドが、スリム化されたベースイメージ（Amazon Linux 2023）に含まれていなかった。

  - **対策/成果**:
    WordPressロールの前提パッケージに `net-tools` を追加。これにより、テストが「コードの正しさ」だけでなく「実行に必要なツールの欠落」まで検知できる、真に堅牢なロールへと進化した。

### ⑥ 統合パイプラインにおける Job 間の依存性 (needs)

  - **課題**:
    当初は別々のワークフローファイルであったため、Lintが失敗していてもTerraformのデプロイが動き出すリスクがあった。

  - **対策/成果**:
    3つのファイルを1つの `pipeline.yml` に統合。**`needs: [job_name]`** を用いてジョブを連結。さらに `if: github.event_name == 'push'` 条件を加えることで、「PR時はテストまで」「マージ後はデプロイまで」という、開発者の意図に沿った安全な自動化フローを完成させた。
---

## 3. 構築の実行ログ

### 3.1. Molecule の導入と初期化

Moleculeを実装するためのツールをインストール。

- 手順:

1. `cd` でプロジェクトルートへ移動。

2. `source .venv/bin/activate` で仮想環境を起動。

3. `pip install "molecule[docker]" ansible-lint pytest-testinfra` を実行。

これにより、プロジェクト専用の「テスト道具箱」が完成。

### 3.2. ロールのテスト初期化

Moleculeによるテストを実装したいロール（今回の場合wordpressロール）に移動し、初期化する。

```bash
cd roles/wordpress
molecule init scenario 
```
- 実行後、`roles/wordpress/`の中に `molecule/default/` というディレクトリが作成され、以下の主要ファイルが現れる。

1. `molecule.yml`: Molecule 全体の設定ファイル。「どの Docker イメージを使うか」「どの Playbook を流すか」を記述する。

2. `converge.yml`: テスト用コンテナに対して、あなたの wordpress ロールを適用するための「テスト用 Playbook」。

3. `verify.yml`: 設定後に「本当に Apache は動いているか？」などを確認するテストコードを記述する場所。

4. **`create.yml` / `destroy.yml`**: このファイルが作成された場合は上書きによるコンテナ起動失敗を防ぐため、リネームもしくは削除する。

### 3.3. Dockerのインストール
Moleculeによるテスト環境にDockerを使用する。これはDocker (コンテナ)が、 OSの核を共有して「アプリの実行環境」だけを切り出す技術であり、数秒で起動し、テストが終われば一瞬で消すことが出来る特徴があるためである。Moleculeで使用するDockerはWSL2内のLinuxに直接Dockerを入れるのではなく、Windows側のDocker DesktopをWSL Integration経由で使うことに注意する。

1. Docker 公式 から Docker Desktop for Windows をダウンロードしてインストール。

2. 設定で 「WSL Integration」 を有効にする。
これで、WSL2 の中から docker コマンドが使える。

3. `docker --version`でバージョン表示されたらOK。

### 3.4. `molecule.yml`の設定

Moleculeによるテストをするための環境を定義する。
`roles/wordpress/molecule/default/molecule.yml`にコードを記述。

<details>
<summary> `molecule.yml` の詳細 </summary>

```yaml
dependency:
  name: galaxy
driver:
  name: docker
platforms:
  - name: instance
    image: geerlingguy/docker-amazonlinux2023-ansible:latest
    privileged: true
    command: /usr/sbin/init
    cgroupns_mode: host  # これが抜けていると Cgroup V2 環境で落ちやすい
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    tmpfs:
      - /run
      - /tmp
    # コンテナ内の環境変数を追加
    env:
      container: docker
    pre_build_image: true
    vars:
      ansible_python_interpreter: /usr/bin/python3

provisioner:
  name: ansible
  config_options:
    defaults:
      remote_tmp: /tmp/ansible
      # 複雑なパイプ処理を避ける設定
      pipelining: true
  playbooks:
    converge: converge.yml
  env:
    # ロールを見つけるためのパス
    ANSIBLE_ROLES_PATH: ../../../
    AWS_REGION: ap-northeast-1
    AWS_ACCESS_KEY_ID: dummy_key_id
    AWS_SECRET_ACCESS_KEY: dummy_secret_key
  inventory:
    group_vars:
      all:
        # 本来 Secrets Manager から取るはずの変数をここで定義してしまう
        db_name: "wordpress_db_test"
        db_user: "wp_user_test"
        db_password: "dummy_password"
        db_host: "localhost"
        db_secret_name: "wp_db_test"
    host_vars:
      instance:
      # コンテナ内のPythonパスを明示（ログにある通り /usr/bin/python3）
        ansible_python_interpreter: /usr/bin/python3
        # 接続ユーザーを強制
        ansible_user: root
verifier:
  name: testinfra
```
</details>

### 3.5. `converge.yml`の定義

どのロールのタスクをテストするのか設定する。
`roles/wordpress/molecule/default/molecule.yml`のロール名とタスク名を実際のものに変更。
```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true # Disable if your role does not rely on facts
  tasks:
    - name: "Include wordpress role"
      ansible.builtin.include_role:
        name: "wordpress"
```


### 3.6. Molecule テストの定義

`roles/wordpress/molecule/default/` 内に、検証用のコードを配置。

<details>
<summary> `test_default.py` (検証コード) の詳細 </summary>

```python
import os
import pytest

def test_httpd_is_installed(host):
    # パッケージがインストールされているか
    assert host.package("httpd").is_installed

def test_httpd_running_and_enabled(host):
    # サービスが起動・実行状態か
    service = host.service("httpd")
    assert service.is_running
    assert service.is_enabled

def test_wordpress_files_exist(host):
    # 設定ファイルが存在し、所有者が正しいか
    assert host.file("/var/www/html/index.php").exists
    assert host.file("/var/www/html/wp-config.php").exists
    assert host.file("/var/www/html/wp-config.php").user == "apache"

def test_port_80_is_listening(host):
    # コンテナ内で 80番ポートが開いているか確認
    socket = host.socket("tcp://0.0.0.0:80")
    assert socket.is_listening
```

</details>

### 3.7. 統合パイプラインの実装 (`pipeline.yml`)

Lint, Molecule, Terraform を一本化。

<details>
<summary> `pipeline.yml` 構造の詳細 </summary>

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [ main, dev ]
  pull_request:
    branches: [ main, dev ]

# OIDC認証（AWSとの連携）に必要な最小限の権限
permissions:
  id-token: write
  contents: read

jobs:
# ---------------------------------------------------------------------------
# 1. 静的解析 (Lint)
# 役割: 文法ミスや非推奨の書き方を、テスト実行前に弾く「最初の門番」
# ---------------------------------------------------------------------------
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
      # site.yml と roles ディレクトリ全体をチェック
        run: ansible-lint site.yml roles/

# ---------------------------------------------------------------------------
# 2. 結合テスト (Molecule)
# 役割: Dockerコンテナ内で実際に構築を行い、OS設定やミドルウェアが正しく動くか検証
# ---------------------------------------------------------------------------
  molecule:
    needs: ansible-lint # Lintが通らない限り、重いテストは実行しない
    runs-on: ubuntu-latest
    strategy:
      matrix:
        ansible-version: ['stable-2.15']

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.10'

      - name: Install dependencies
        run: |
          python -m pip install boto3 botocore --upgrade pip
          pip install molecule molecule-plugins[docker] ansible-core pytest-testinfra

      - name: Install Ansible Galaxy collections
        run: |
          # MoleculeのDockerドライバが内部で使用するコレクションをインストール
          ansible-galaxy collection install community.docker community.general amazon.aws

      - name: Run Molecule Test
        run: |
          molecule test  # destroy -> create -> converge -> verify -> destroy を一気に行う
        working-directory: roles/wordpress
        env:
          PY_COLORS: '1'
          ANSIBLE_FORCE_COLOR: '1'   


# ---------------------------------------------------------------------------
# 3. インフラ構築 & デプロイ (Terraform & Ansible)
# 役割: テスト済みのコードを、本物のAWS環境へ反映する
# ---------------------------------------------------------------------------
  terraform_deploy:
    needs: molecule # テストが成功した時だけ、本番環境の操作を許可する
    runs-on: ubuntu-latest
    # PR時は Plan まで、マージ(Push)時は Apply まで実行する
    env:
      TF_WORKSPACE: ${{ (github.base_ref == 'main' || github.ref == 'refs/heads/main') && 'prd' || 'dev' }}

    steps:
      # 1. GitHub Actionsの仮想マシンにあなたのコードをコピーする
      - name: Checkout code
        uses: actions/checkout@v4

      # 2. AWSとの信頼関係（OIDC）を利用して一時的な鍵を取得する
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          # 変数 ${{ secrets.名前 }} で呼び出す
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-role
          aws-region: ap-northeast-1

      # 3. Terraformをインストールする
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.14.3 # 使っているバージョンに合わせる

      # 4. terraform init（S3バックエンドへの接続など）
      - name: Terraform Init
        run: terraform init

      # 5. TFLint のセットアップと実行
      - name: Setup TFLint
        uses: terraform-linters/setup-tflint@v3
        with:
          tflint_version: v0.48.0

      - name: Init TFLint
        run: tflint --init
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Run TFLint
        run: tflint -f compact

      # 6. Checkov の実行（セキュリティスキャン）
      - name: Run Checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: .
          framework: terraform
          soft_fail: true # 警告が出ても処理を止めない設定
          quiet: true

      # 7. terraform plan（プルリクエスト時などに実行）
      - name: Terraform Plan
        run: terraform plan

      # --- ここから下は「マージ(Push)」された時だけ実行される安全装置 ---
      # 8. pushイベント（マージ）の時だけ Apply を実行
      - name: Terraform Apply
        if: github.event_name == 'push'
        run: terraform apply -auto-approve

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
              IdentityFile $HOME/.ssh/id_ed25519
              StrictHostKeyChecking no
              UserKnownHostsFile /dev/null
              ProxyCommand sh -c "aws ec2-instance-connect send-ssh-public-key --instance-id %h --instance-os-user ec2-user --ssh-public-key file://$HOME/.ssh/id_ed25519.pub && aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p"
          EOT

      # 11. Ansible の実行
      - name: Run Ansible Playbook
        if: github.event_name == 'push' # Apply が成功した時だけ実行
        env:
          ANSIBLE_HOST_KEY_CHECKING: "False"

        run: |
          # システムに直接boto3とansible-core(Ansibleの本体)をインストール        
          python3 -m pip install --upgrade pip
          python3 -m pip install boto3 botocore ansible-core

          # 2. 必要なコレクションのインストール
          ansible-galaxy collection install amazon.aws

          # 3. 実行
          ansible-playbook -i inventory.aws_ec2.yml site.yml 
```

</details>

### 3.8. wordpresロールの`tasks/main.yml`の修正
Moleculeによるテスト時に、Lookup プラグインの「先行評価」による認証エラーを防ぐために、
テンプレート作成時に使用する変数を修正する。
※この時、テンプレート側でも変数名が一致するよう修正する。

`roles/wordpress/tasks/main.tf`の最期のタスクを修正。

```yaml

# ．．．既存の設定．．．

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
    # 修正のポイント: db_password が未定義の時だけ lookup を「文字列」として組み立てる
    # >- を使いつつ、内部の空白制御記法で Lint と実機出力を両立
    wp_db_password: >-
      {%- if db_password is defined -%}
        {{- db_password | trim -}}
      {%- else -%}
        {{- lookup('amazon.aws.secretsmanager_secret', db_secret_name) | trim -}}
      {%- endif -%}
  no_log: true

```


### 3.9. ローリングアップデートの設定

`site.yml` に同時実行数を制御する設定を追加。

```yaml
- name: Deploy WordPress
  hosts: web_servers
  serial: 1  # 1台ずつ順番に実行。1台目で失敗すれば全体を止める安全策。
  become: true
  roles:
    - wordpress
```
**補足**
既存の構成でASGの規模するキャパシティが1だった場合は、ローリングアップデートの挙動を確認するために2以上に変更する。

### 3.10. Actions の実行

ファイルの設定が完了したら、GitHubに`push`して動作確認を行う。
Day5の学習から、デプロイフローとして作業用ブランチ→devブランチという構成をとっているので、
作業用ブランチを作成し、作業用ブランチに`push`してから、GitHub上でdevブランチにプルリクエストを作成。
プルリクエストの成功が確認出来たら、devブランチにマージ。
Actionsのログを確認すると以下の点が確認できる。

- Actionsのフローが`lint`→`molecule`→`terraform`と段階を踏んでいる

- マージ時、Playbookの実行が複数台のインスタンスにまとめて実行から、1台ずつの実行に変わっている
---



## 4. 技術的考察・まとめ（Tips）

  - **トラブルシューティングの王道**:
    「Docker単体で動くか？」といった、レイヤーを分けた切り分け（アイソレーション）が、複雑なCI/CDトラブルを解決する最短距離であることを実感した。

  - **「手元で動く」は証明ではない**:
    ローカル環境（WSL2等）には、過去の認証情報やインストール済みライブラリといった「秘伝のタレ」が残りやすい。WSL2での成功に安住せず、CIという「真っさらな第三者の環境」でテストを完走させて初めて、コードの真の再現性(ポータビリティ)が担保されることを学んだ。

  - **シフトレフト（早期発見）**:
    ansible-lint による静的解析と Molecule による動的テストを組み合わせることで、本番環境への「事故」を物理的に未然に防ぐ仕組みが完成した。


  - **Cgroup V2と特権コンテナ**:
    近代的なLinux環境で systemd コンテナを動かすには、「権限（privileged）」「場所（volumes）」「視界（cgroupns）」の3つが不可欠であることを学んだ。これは今後のコンテナ運用においても重要な知見となる。

  - **テストは「未来の自分」への投資**:
    Moleculeを導入したことで、将来的にPHPのバージョンを上げたり、OSをAmazon Linux 2025（仮）に変えたりする際にも、「ボタン一つで既存機能の無事を確認できる」という安心感を得ることができた。

  - **オーケストレーションの真髄**:
    `serial: 1` 
    
---

## 5. 💡 最終的なリファクタリング：実用的なディレクトリ構造への移行

プロジェクトの完遂にあたり、学習過程でルートディレクトリに混在していたファイルを、保守性を高めるための再配置を行った。

- **変更内容**:

  - Terraform関連コードを `/terraform` ディレクトリへ集約。

  - Ansible関連（Playbook, Roles, Inventory）を `/ansible` ディレクトリへ集約。

- **対応作業**:

  - ディレクトリ移動に伴う各リソース間の相対パス参照を修正。

  - GitHub Actions（`.github/workflows`）内の実行パス（`working-directory`）を新構造に適合。

- **意図**:
学習段階では「動かすこと」を優先しルートで作業していたが、リポジトリとして、他のエンジニアが構造を直感的に理解できるよう、標準的なディレクトリレイアウトを採用した。
