# 付録: GitHub Runner用ACRイメージのセットアップ

このドキュメントでは、GitHub ActionsのSelf-hosted Runnerを動的に起動するために必要な、Azure Container Registry (ACR)へのカスタムRunnerイメージのビルドとプッシュ手順を説明します。

## 📚 概要

このプロジェクトでは、完全閉域ネットワーク環境でCI/CDパイプラインを実現するために、以下のアーキテクチャを採用しています:

1. **カスタムGitHub Runnerイメージ**: Azure CLI、Node.js、Pythonなどのツールをプリインストール
2. **Azure Container Registry (ACR)**: Private Endpoint経由でイメージを安全に保管
3. **Azure Container Instances (ACI)**: ワークフロー実行時に動的にRunnerを起動
4. **vNet統合**: すべてのリソースがvNet内で通信、インターネット経由のアクセスなし

## 前提条件

- Azure CLIがインストールされていること
- `deployment_step_by_step`リポジトリでStep 01-03が完了していること
- 以下のリソースが作成済みであること:
  - Azure Container Registry: `acrinternalragdev`
  - Virtual Network: `vnet-internal-rag-dev`
  - Private Endpoint (ACR用)
  - NSG (Network Security Group)

## 必要なファイル

このリポジトリには、GitHub Runnerイメージのビルドに必要な以下のファイルが含まれています:

```
internal_rag_Application_sample_repo/
├── Dockerfile.runner    # GitHub Runnerイメージの定義
└── start.sh            # Runnerの起動スクリプト
```

## ACRイメージのビルド手順

```powershell
# 環境変数の設定
$RESOURCE_GROUP = "rg-internal-rag-dev"
$ACR_NAME = "acrinternalragdev"  # 実際のACR名に変更

# 1. パブリックアクセスを一時的に有効化
az acr update --name $ACR_NAME --public-network-enabled true

# 2. ネットワークルールのデフォルトアクションをAllowに変更
az acr update --name $ACR_NAME --default-action Allow

# 3. ACR上で直接ビルドとプッシュ
az acr build `
  --registry $ACR_NAME `
  --image github-runner:latest `
  --image github-runner:1.0.0 `
  --file Dockerfile.runner `
  .

# 4. イメージ確認
az acr repository show-tags --name $ACR_NAME --repository github-runner --output table

# 5. ネットワークルールをDenyに戻す
az acr update --name $ACR_NAME --default-action Deny

# 6. パブリックアクセスを無効化
az acr update --name $ACR_NAME --public-network-enabled false

```

## Dockerfile.runnerの構成

### ベースイメージ

```dockerfile
FROM mcr.microsoft.com/cbl-mariner/base/core:2.0
```

**選定理由**:
- Microsoft公式のCBL Mariner 2.0を使用
- セキュリティアップデートが継続的に提供される
- 軽量で起動が高速

### インストールされるパッケージ

| パッケージ | 用途 |
|-----------|------|
| `curl`, `tar`, `gzip` | GitHub Runnerのダウンロードと展開 |
| `jq` | JSONの解析(ワークフロー内で使用) |
| `git` | ソースコードのチェックアウト |
| `python3`, `python3-pip` | Python環境(Azure CLI、Functionsデプロイ用) |
| `nodejs`, `npm` | Node.js環境(Web Appデプロイ用) |
| `zip`, `unzip` | デプロイパッケージの作成 |
| `icu` | .NET Core依存関係 |

### Azure CLIのインストール

```dockerfile
RUN python3 -m pip install --no-cache-dir --upgrade pip setuptools && \
    python3 -m pip install --no-cache-dir --upgrade azure-core azure-mgmt-core && \
    python3 -m pip install --no-cache-dir azure-cli
```

**重要なポイント**:
- `azure-core`と`azure-mgmt-core`を先にアップグレード
- 依存関係の競合を事前に解決
- システムグローバルにインストール(全ユーザーで共有)

### 環境変数の設定

```dockerfile
ENV PYTHONNOUSERSITE=1 \
    PIP_NO_USER=1
```

**目的**:
- ユーザーローカルディレクトリへのpipインストールを無効化
- Azure CLIとの依存パッケージ競合を防止
- システム全体のパッケージのみを使用

### GitHub Runnerのインストール

```dockerfile
ARG RUNNER_VERSION=2.311.0
WORKDIR /actions-runner

RUN curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && chown -R runner:runner /actions-runner
```

**バージョン管理**:
- `RUNNER_VERSION`はARGで定義(ビルド時に変更可能)
- 現在は`2.311.0`を使用
- GitHub公式リリースから直接ダウンロード

### セキュリティ設定

```dockerfile
# 非rootユーザーを作成
RUN useradd -m -s /bin/bash runner

# 非rootユーザーに切り替え
USER runner
```

**理由**:
- GitHub Runnerはroot権限での実行を拒否する
- セキュリティベストプラクティスに準拠
- コンテナ環境での安全な実行

## start.shスクリプトの構成

### 起動時の診断機能

```bash
# デバッグ情報
echo "=== GitHub Runner Startup ==="
echo "Runner Name: ${RUNNER_NAME:-runner-$(hostname)}"
echo "Repository URL: ${RUNNER_REPOSITORY_URL}"

# ネットワーク接続テスト
if curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://github.com | grep -q "200\|301\|302"; then
    echo "✅ GitHub.com is reachable"
else
    echo "❌ Cannot reach GitHub.com"
    exit 1
fi
```

**機能**:
- 環境変数の確認
- GitHub.comへの接続テスト
- DNS解決の確認

### Runnerの設定

```bash
./config.sh \
    --url "${RUNNER_REPOSITORY_URL}" \
    --token "${RUNNER_TOKEN}" \
    --name "${RUNNER_NAME:-runner-$(hostname)}" \
    --work "${RUNNER_WORK_DIRECTORY:-_work}" \
    --labels "${RUNNER_LABELS:-self-hosted}" \
    --unattended \
    --replace
```

**オプション**:
- `--unattended`: 対話なしで設定
- `--replace`: 既存の同名Runnerを置き換え
- `--labels`: ワークフローでの指定に使用(`runs-on: self-hosted`)

## トラブルシューティング

### イメージのビルドが失敗する

**症状**: `az acr build`コマンドがエラーで終了

**確認事項**:
1. ACRにログインしているか (`az acr login`)
2. `Dockerfile.runner`と`start.sh`が存在するか
3. ネットワーク接続が正常か

**対処法**:
```powershell
# ACRの状態を確認
az acr check-health --name acrinternalragdev

# ローカルでDockerfileの構文チェック
docker build -f Dockerfile.runner -t test-runner:latest . --dry-run
```

### Private Endpoint経由でACRにアクセスできない

**症状**: Container InstanceからACRイメージをpullできない

**確認事項**:
1. Private Endpointが正しく構成されているか
2. DNS設定が正しいか
3. NSGでvNet内部通信が許可されているか

**対処法**:
```powershell
# Private Endpointの確認
az network private-endpoint show `
    --name pe-acr-internal-rag-dev `
    --resource-group rg-internal-rag-dev `
    --query "{name:name, provisioningState:provisioningState, subnet:subnet.id}" `
    --output table

# DNS設定の確認
az network private-dns record-set list `
    --resource-group rg-internal-rag-dev `
    --zone-name privatelink.azurecr.io `
    --output table

# Container InstanceからのDNS解決テスト
az container exec `
    --resource-group rg-internal-rag-dev `
    --name aci-runner-test `
    --exec-command "nslookup acrinternalragdev.azurecr.io"
```

### Runner起動時にGitHub.comに接続できない

**症状**: `start.sh`で「Cannot reach GitHub.com」エラー

**確認事項**:
1. NSGで443番ポート(HTTPS)のアウトバウンドが許可されているか
2. Container InstancesのSubnetに正しいNSGが関連付けられているか
3. Azure FirewallまたはProxy設定が正しいか

**対処法**:
```powershell
# NSGルールの確認
az network nsg rule list `
    --resource-group rg-internal-rag-dev `
    --nsg-name nsg-container-instances-dev `
    --query "[?direction=='Outbound' && access=='Allow'].{Name:name, Priority:priority, DestinationPortRange:destinationPortRange, Protocol:protocol}" `
    --output table

# 必要に応じて443番ポートを許可
az network nsg rule create `
    --resource-group rg-internal-rag-dev `
    --nsg-name nsg-container-instances-dev `
    --name AllowHTTPSOutbound `
    --priority 200 `
    --direction Outbound `
    --access Allow `
    --protocol Tcp `
    --destination-port-range 443 `
    --destination-address-prefix Internet
```

## バージョン履歴

| タグ | 変更内容 | 日付 |
|------|---------|------|
| `v9-azure-core-global` | azure-coreをグローバルアップグレード、依存関係競合解消 | 2025-11-19 |
| `v8` | PYTHONNOUSERSITE環境変数追加 | 2025-11-18 |
| `v7` | Azure CLI依存関係の改善 | 2025-11-17 |
| `latest` | 常に最新版を指すエイリアス | - |

## ベストプラクティス

### 1. タグ管理

```powershell
# 常にバージョンタグと`latest`の両方を付ける
az acr build `
    --registry acrinternalragdev `
    --image github-runner:latest `
    --image github-runner:v10 `
    --file Dockerfile.runner `
    .
```

**理由**:
- `latest`は常に最新版を指す
- バージョン番号タグでロールバック可能

### 2. ビルドログの保存

```powershell
# ビルドログをファイルに保存
az acr build `
    --registry acrinternalragdev `
    --image github-runner:latest `
    --file Dockerfile.runner `
    . 2>&1 | Tee-Object -FilePath "acr-build-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
```

### 3. 定期的なセキュリティアップデート

```powershell
# 月次でベースイメージを更新してリビルド
az acr build `
    --registry acrinternalragdev `
    --image github-runner:latest `
    --image github-runner:v10-$(Get-Date -Format 'yyyyMMdd') `
    --file Dockerfile.runner `
    --no-cache `
    .
```

**オプション**:
- `--no-cache`: キャッシュを使わず最新パッケージを取得

## 関連ドキュメント

- [Step 4: アプリケーションデプロイ](step04-deploy-app.md)
- [deployment_step_by_step - Step 03: GitHub Actions](https://github.com/matakaha/internal_rag_Application_deployment_step_by_step/tree/main/bicep/step03-github-actions)
- [GitHub Actions Self-hosted Runners公式ドキュメント](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Azure Container Registry公式ドキュメント](https://learn.microsoft.com/ja-jp/azure/container-registry/)

## 次のステップ

ACRイメージのセットアップが完了したら:

1. **[Step 4: アプリケーションデプロイ](step04-deploy-app.md)** に戻る
2. GitHub Actionsワークフローを実行してデプロイを確認
