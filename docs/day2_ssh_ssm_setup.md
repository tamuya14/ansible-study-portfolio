# Day2: 「SSMとInstance Connectを活用したセキュアな疎通確認」の記録

**⚠️ 本ドキュメントの性質について**

このドキュメントは、本プロジェクト完成に至るまでの学習プロセスを記録したログです。
当時の試行錯誤やエラー解決の過程を重視して記述しているため、一部の手順やコードは最終的なリポジトリの構成（README参照）と異なる、または不十分な箇所があります。
最新かつ再現性のある構築手順については、ルートディレクトリの [README.md](/README.md) を参照してください。

---

## 1. 目的と構成
* **目的**: 
  本演習では、Ansibleを用いてAWS上のプライベートサブネットに配置されたEC2インスタンスに対して、SSHポート（22番）を開放することなく、セキュアに操作・管理できる環境を構築することを目的とする。

* **構成**: 
  今回の接続は、直接SSHを行うのではなく、AWS CLIのSession Manager機能をトンネルとして利用（ProxyCommand）し、認証には一時的な鍵転送（EC2 Instance Connect）を組み合わせる。

**<イメージ図>**

  ![Instance ConnectとSessionManagerを用いたセキュアな接続の図](/docs/images/Day2イメージ図.png)
<p align="center">図1：Instance ConnectとSessionManagerを用いたセキュアな接続</p>

## 2. 作業プロセスと試行錯誤の記録
本環境の構築にあたり、以下の3つのアプローチを検討・実施した。

### ①【失敗】 システムへの直接インストールと制限
当初、AnsibleをOSのシステム環境に直接インストールしたが、Pythonパッケージの保護制限により依存ライブラリの管理が困難となった。

* **対策**: pipx による隔離環境の作成を試みたが、後のSSM連携においてライブラリ参照の複雑化を招いた。

* **補足**: Day1の手順書ではあらかじめPythonの仮想環境でのAnsibleインストールを記載しているが、Day2でのこのトラブルを受けて先んじて実行するように修正を行った。

### ②【断念】 aws_ssm コレクションによる接続
Ansibleのコミュニティコレクション（amazon.aws.aws_ssm）を用いた直接接続を試みた。

* **発生したエラー**: expected string or bytes-like object, got 'NoneType'

* **分析**: -vvv オプションによる詳細ログ解析の結果、内部的なユーザ識別コマンド（echo ~ec2-user）で停止していることを確認。

* **判断**: 環境依存の解決に多大な時間を要すると判断し、より汎用的でデバッグが容易な 「ProxyCommand方式」 へ切り替えた。

### ③【採用】 ProxyCommand + EC2 Instance Connect
SSHの標準機能である ProxyCommand を使い、通信経路をSSM経由に流す方式を採用。

**本方式のセキュリティ的メリット**:

* **秘密鍵の安全性**: 鍵はローカル（~/.ssh）で管理し、GitHub等の共有範囲には含めない。

* **EC2側の無垢性**: EC2 Instance Connectにより、公開鍵は接続時のみ一時的（60秒間）に転送されるため、サーバ側に鍵が残らない。

* **IAMによる制御**: 鍵の転送自体にIAM権限（EC2InstanceConnectFullAccess）が必要なため、二重の認証となる。


## 3. 構築の実行ログ

### 3.1. 仮想環境（.venv）の構築
パッケージの競合を避けるため、プロジェクト専用の仮想環境を作成する。
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install ansible boto3 botocore
```

### 3.2. ローカルでのキーペア作成
接続に使用する一時的な鍵を作成する。
```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
chmod 600 ~/.ssh/id_ed25519
```

### 3.3. IAM権限の付与
Ansibleを実行するIAMユーザ（演習用ユーザ）に、以下の権限を追加アタッチする。

* **EC2InstanceConnectFullAccess**

### 3.4. インベントリファイル（inventory.yml）の作成
SSM経由で通信を通すための設定を記述する。
インスタンスIDを手動で指定する静的インベントリを作成。

```yml
all:
  children:
    web_servers:
      hosts:
        i-xxxxxxxxxxxxxxxxx: # 自身のインスタンスID
          ansible_user: ec2-user
          ansible_python_interpreter: /usr/bin/python3.9
          ansible_connection: ssh
          ansible_ssh_private_key_file: ~/.ssh/id_ed25519
          ansible_ssh_common_args: >-
            -o ProxyCommand="sh -c 'aws ec2-instance-connect send-ssh-public-key --instance-id %h --instance-os-user ec2-user --ssh-public-key file://~/.ssh/id_ed25519.pub && aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p'"
```

### 3.5. 疎通確認の実行
```bash
# pingモジュールでの疎通確認
ansible web_servers -i inventory.yml -m ping

# 成功時、"ping": "pong" が返ってくることを確認
```

## 4. 技術的考察・まとめ（Tips）

* **トラブルシューティングの重要性**: NoneType エラーに対し、-vvv を用いて「どこで」「何のコマンドが」失敗しているかを特定できたことが、次の方針（ProxyCommandへの変更）を決める鍵となった。

* **適切な道具の選択**: 最新の便利なプラグイン（aws_ssm）が動かない場合、SSH本来の機能（ProxyCommand）に戻ることで、原因の切り分けがスムーズになり、最終的なゴールに辿り着くことができた。
---
