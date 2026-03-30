# WSL2 Ubuntu 22.04に近い環境を使用
FROM ubuntu:24.04

# 環境変数の設定（インタラクティブな入力を防ぐ）
ENV DEBIAN_FRONTEND=noninteractive

# 作業ディレクトリ
WORKDIR /workspace

# 2. システムパッケージのインストール
RUN apt-get update && apt-get install -y \
    python3-pip python3-venv git curl wget unzip lsb-release gnupg \
    software-properties-common sudo \
    && rm -rf /var/lib/apt/lists/*

# 3. Terraformのインストール
RUN wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update && apt-get install -y terraform

# 4. AWS CLI v2 のインストール
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# 5. Session Manager Plugin のインストール
RUN curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb" \
    && dpkg -i session-manager-plugin.deb \
    && rm session-manager-plugin.deb

# プロジェクトファイルをコンテナにコピー
COPY . .

# Python仮想環境の作成とライブラリインストール
# (READMEの手順3に相当)
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
# requirements.txtがある前提
RUN pip install --upgrade pip \
    && pip install -r requirements.txt \
    && ansible-galaxy collection install amazon.aws community.docker community.general

# デフォルトのシェルをbashに設定
CMD ["/bin/bash"]
