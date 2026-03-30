# Day1:「Ansible学習環境の構築」の記録

**⚠️ 本ドキュメントの性質について**

このドキュメントは、本プロジェクト完成に至るまでの学習プロセスを記録したログです。
当時の試行錯誤やエラー解決の過程を重視して記述しているため、一部の手順やコードは最終的なリポジトリの構成（README参照）と異なる、または不十分な箇所があります。
最新かつ再現性のある構築手順については、ルートディレクトリの [README.md](/README.md) を参照してください。

---

## 1. 目的と構成
* **目的**: Ansibleによる構成管理を学ぶため、Terraformで構築した既存インフラをベースに学習用環境を分離・構築する。

* **構成**: 
  1. ローカル環境（WSL2）にUbuntuをインストールし、サーバ内に必要ツール（Python, AWS CLI, Session Manager Plugin, Terraform）をインストールする。
  2. Python仮想環境を作成し、Ansible をセットアップする。

**<イメージ図>**

![構築する環境のイメージ図](/docs/images/Day1イメージ図.png)
<p align="center">図1：構築する環境のイメージ</p>

## 2. 環境構築の実行ログ
本プロジェクトは過去に学習したTerraform構築で作成したコードを元にAnsibleの実装を行う。
Terraform構築環境が手元にない場合は、[こちらのリポジトリ](https://github.com/tamuya14/my-aws-infra-portfolio)をクローンして環境を準備する。


### 2.1. インフラ状態の分離 (Backend構成の変更)
既存のTerraform構築ファイルのうち、Stateファイルの保存先である`Backend`の`key`を変更。
`main.tf` (または `backend.tf`) の `key` を以下のように修正。
```hcl
backend "s3" {
  bucket = "my-terraform-state-bucket"　# 自身の環境のものに変更
  key    = "aws-ansible-study/terraform.tfstate" # 学習用にパスを分離
  region = "ap-northeast-1"
  dynamodb_table = "my-terraform--dynamodb-locks" # 自身の環境のものに変更
  encrypt        = true
}
```


### 2.2. ローカル環境の構築
Ansibleの実行環境としてWSL2を利用する。
まずは、PowerShellを開きWSL2,Ubuntuをインストール。
```shell 
#ローカルPC（Windows）がAnsibleを実行するための土台構築
wsl --install

#土台の上にLinuxサーバ（Ubuntu）の構築
wsl --install -d Ubuntu

```

### 2.3. Ubuntuのセットアップ
Linuxサーバで使用するユーザとパスワードの設定。
ユーザのパスワードは後の`sudo`実行の際に必要なため必ずメモ！

```bash
# ユーザ名の入力
Enter new UNIX username: 
#ユーザのパスワード入力（今後管理者権限での実行の際に必要）
New password: 
```

### 2.4. 実行環境の構築
コマンド入力はVS Codeで実行。
※必要に応じてVS CodeにWSLをインストール。


```bash
#作業用ディレクトリの作成
mkdir ~/work

#Linuxサーバの作業用ディレクトリに既存のWindows上にあるTerraform構築ファイルをコピー
#コピー元のパス/ディレクトリ名は自身の環境に合わせて読み替える
cp -r /mnt/c/Users/*実際のユーザ名*/aws-ansible-study ~/work/aws-ansible-study

#ホームディレクトリ移動
cd ~

# Pythonのインストール
sudo apt update && sudo apt install -y python3-pip python3-venv

# Terraformのインストール
 # 1. 署名鍵とリポジトリを追加（コピー＆ペーストで一気にOK）
 wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
 echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
 
 # 2. インストール
 sudo apt update && sudo apt install terraform -y
 
 # 3. 確認（バージョンが出れば成功）
 terraform -v

# AWS CLIのインストール
 # 1. ダウンロードしてインストール
 curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
 unzip awscliv2.zip
 sudo ./aws/install

 # 2. 確認（バージョンが出れば成功）
 aws --version

# Session Manager Pluginのインストール
 # 1. ダウンロードとインストール
 curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
 sudo dpkg -i session-manager-plugin.deb

 # 2. 確認（バージョンが出れば成功）
 session-manager-plugin --version


# AWS環境構築のための認証情報の設定
 aws configure
 #対話形式で入力：
 AWS Access Key ID: 演習用ユーザのアクセスキーを入力
 AWS Secret Access Key: 演習用ユーザのシークレットキーを入力
 Default region name: ap-northeast-1 (東京リージョン)
 Default output format: json

 # 確認（ユーザ情報が表示されたら成功）
 aws sts get-caller-identity
 # 期待される出力例: { "UserId": "AID...", "Account": "************(12桁のID)", "Arn": "..." }

#不要ファイルの削除
 # 学習用ディレクトリ（~/work/aws-ansible-study）にいることを確認して実行
 rm -rf aws awscliv2.zip session-manager-plugin.deb


# 仮想環境上へAnsibleのインストール
 cd ~/work/aws-ansible-study
 python3 -m venv .venv
 source .venv/bin/activate
 pip install ansible

# Linux上からTerraformにて環境構築できるかの確認
 # 初期化の実行
 terraform init

 # 学習用ディレクトリに移動したことでworkspaceがdefaultに戻っているため、dev環境を選択。
 terraform workspace select dev

 # 作成されるリソースの確認
 terraform plan
 
 # リソースのデプロイ 
 terraform apply

```

### 2.5. `gitignore`の設定
環境構築に合わせて、既存の構築ファイルのうち、`gitignore`に追記を行う。
今後、`venv` などのファイルを作成する可能性があるため、あらかじめ以下を設定する。
（既存のものと重複しているファイル有）
```bash
.terraform/
*.tfstate
*.tfstate.backup
.terraform.lock.hcl
*.pem
*.tfvars
.venv/
__pycache__/
*.pyc
.vscode/
.env
.DS_Store
id_ed25519
id_ed25519.pub
```

## 3. 技術的考察（Tips）
Day1の学習では、既存のTerraform構築コードをベースにしており、そのリポジトリからコードをコピーして学習を行った。
当初実施していたWindowsでの作業から、WSL2を利用したLinuxベースでの作業に移行した理由が以下の通りである。

* **State管理の分離**: Terraformのリポジトリをコピーした１つ目の理由は、Ansibleが制御する対象のインフラを既存環境と競合させないためである。これにより冪等性（何度実行しても同じ結果になること）を担保する。既存の`Backend`設定のうち、`key`を変更することで１つのバケットで複数の環境を保存する。

* **既存のファイルの移動**: Terraformのリポジトリをコピーした２つ目の理由は、Windowsファイルのマウントによって発生するトラブルの解消のためである。LinuxサーバからWindowsファイルをマウントした状態でツールのインストールやterraformの実行をすると、LinuxとWindowsにおけるファイルシステムの違いによって権限エラーや実行速度の遅延などの問題が発生する。既存のファイルをLinuxサーバ内に移動させることで、Linuxサーバ内で作業を完結させ、権限や速度問題が解消された。

* **クリーンアップ**: 作業ディレクトリ内に残ったインストール用のバイナリやインストーラーは、セキュリティおよびリポジトリの肥大化を防ぐために `rm` で削除した。
---
