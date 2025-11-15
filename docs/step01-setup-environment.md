# Step 1: 環境準備

このステップでは、閉域RAGアプリケーション開発に必要な環境を準備します。

## 📚 学習目標

このステップを完了すると、以下ができるようになります:

- GitHubリポジトリのフォークとクローン
- 必要な環境変数の設定
- Azure CLIでのリソース確認
- ローカル開発環境のセットアップ

## 前提条件

以下が完了していることを確認してください:

### 1. 前提リポジトリの完了

✅ **[internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step)** が完了していること

作成されているリソース:
- Virtual Network (vNet)
- Azure OpenAI Service (Private Endpoint付き)
- Azure AI Search (Private Endpoint付き)
- Azure Storage Account
- App Service (vNet統合済み)

✅ **[internal_rag_Application_deployment_step_by_step](https://github.com/matakaha/internal_rag_Application_deployment_step_by_step)** が完了していること

作成されているリソース:
- Key Vault (Private Endpoint付き)
- Self-hosted Runner用Subnet
- GitHub Secrets設定

### 2. ツールのインストール

```powershell
# Azure CLIバージョン確認
az --version
# 必要: 2.50.0以上

# Pythonバージョン確認
python --version
# 必要: 3.11以上

# Gitバージョン確認
git --version
# 必要: 2.30以上
```

## セットアップ手順

### 1. GitHubリポジトリの準備

#### オプションA: このリポジトリをフォーク(推奨)

1. GitHubでこのリポジトリをフォーク
2. フォークしたリポジトリをクローン

```powershell
# 自分のアカウントのリポジトリをクローン
git clone https://github.com/<your-github-username>/internal_rag_Application_sample_repo.git
cd internal_rag_Application_sample_repo
```

#### オプションB: 新規リポジトリとして作成

```powershell
# 新規GitHubリポジトリを作成
gh repo create <your-org>/internal-rag-app --private

# ローカルに初期化
git init
git remote add origin https://github.com/<your-org>/internal-rag-app.git

# このリポジトリの内容をコピー
# (別途ダウンロードして配置)
```

### 2. Azure リソース情報の収集

前提リポジトリで作成したAzureリソースの情報を収集します。

```powershell
# リソースグループ名を設定
$RESOURCE_GROUP = "rg-internal-rag-dev"

# Azureにログイン
az login

# サブスクリプション設定
az account set --subscription "<your-subscription-id>"

# Azure OpenAI エンドポイント取得
$OPENAI_ENDPOINT = az cognitiveservices account show `
    --resource-group $RESOURCE_GROUP `
    --name "<your-openai-resource-name>" `
    --query "properties.endpoint" -o tsv

Write-Host "Azure OpenAI Endpoint: $OPENAI_ENDPOINT"

# AI Search エンドポイント取得
$SEARCH_ENDPOINT = "https://<your-search-service>.search.windows.net"
Write-Host "AI Search Endpoint: $SEARCH_ENDPOINT"

# App Service 名前取得
$WEBAPP_NAME = az webapp list `
    --resource-group $RESOURCE_GROUP `
    --query "[0].name" -o tsv

Write-Host "App Service Name: $WEBAPP_NAME"

# Key Vault 名前取得
$KEYVAULT_NAME = az keyvault list `
    --resource-group $RESOURCE_GROUP `
    --query "[0].name" -o tsv

Write-Host "Key Vault Name: $KEYVAULT_NAME"
```

### 3. 環境変数ファイルの作成

ローカル開発用の環境変数ファイルを作成します。

```powershell
# .env.sampleをコピー
Copy-Item .env.sample .env

# .envファイルを編集
code .env
```

`.env` ファイルの内容を以下のように設定:

```bash
# Azure OpenAI 設定
AZURE_OPENAI_ENDPOINT=https://your-openai-resource.openai.azure.com/
AZURE_OPENAI_DEPLOYMENT=gpt-4

# Azure AI Search 設定
AZURE_SEARCH_ENDPOINT=https://your-search-service.search.windows.net
AZURE_SEARCH_INDEX=documents-index
AZURE_SEARCH_KEY=  # ローカル開発時のみ(本番はManaged Identity使用)

# アプリケーション設定
FLASK_ENV=development
```

> ⚠️ **注意**: `.env` ファイルは `.gitignore` に含まれており、Gitにコミットされません。

### 4. Python仮想環境のセットアップ

```powershell
# 仮想環境を作成
python -m venv venv

# 仮想環境を有効化
.\venv\Scripts\Activate.ps1

# 依存関係をインストール
pip install --upgrade pip
pip install -r requirements.txt

# インストール確認
pip list
```

### 5. Azure接続テスト

Managed Identityを使用してAzureリソースへの接続をテストします。

```powershell
# テストスクリプトを実行
python scripts/test-azure-connection.py
```

> 📝 **Note**: ローカル開発では `az login` で認証した資格情報が使用されます。App Service上では Managed Identity が使用されます。

### 6. GitHub Secretsの設定

[Step 8のドキュメント](https://github.com/matakaha/internal_rag_Application_deployment_step_by_step/blob/main/bicep/step08-github-actions/README.md#2-github-secretsの設定)で設定したSecretsに加えて、アプリケーション固有の設定を追加します。

#### 必要なSecrets

| Secret名 | 説明 | 取得方法 |
|---------|------|---------|
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAIエンドポイント | 上記で取得した値 |
| `AZURE_OPENAI_DEPLOYMENT` | デプロイメント名 | `gpt-4` など |
| `AZURE_SEARCH_ENDPOINT` | AI Searchエンドポイント | 上記で取得した値 |
| `AZURE_SEARCH_INDEX` | インデックス名 | Step 3で作成する名前 |

#### GitHub CLIで設定

```powershell
# リポジトリディレクトリで実行
gh secret set AZURE_OPENAI_ENDPOINT -b "$OPENAI_ENDPOINT"
gh secret set AZURE_OPENAI_DEPLOYMENT -b "gpt-4"
gh secret set AZURE_SEARCH_ENDPOINT -b "$SEARCH_ENDPOINT"
gh secret set AZURE_SEARCH_INDEX -b "documents-index"
```

#### GitHub Webで設定

1. GitHubリポジトリページを開く
2. `Settings` → `Secrets and variables` → `Actions` を選択
3. `New repository secret` をクリック
4. 各Secretを追加

### 7. App Service設定の更新

App Serviceに環境変数を設定します。

```powershell
# App Serviceに環境変数を設定
az webapp config appsettings set `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --settings `
        AZURE_OPENAI_ENDPOINT="$OPENAI_ENDPOINT" `
        AZURE_OPENAI_DEPLOYMENT="gpt-4" `
        AZURE_SEARCH_ENDPOINT="$SEARCH_ENDPOINT" `
        AZURE_SEARCH_INDEX="documents-index"

# 設定確認
az webapp config appsettings list `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --output table
```

### 8. Managed Identityの権限設定

App ServiceのManaged IdentityにAzureリソースへのアクセス権限を付与します。

```powershell
# App ServiceのManaged Identity(プリンシパルID)を取得
$PRINCIPAL_ID = az webapp identity show `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --query principalId -o tsv

# Azure OpenAIへのアクセス権限を付与
$OPENAI_RESOURCE_ID = az cognitiveservices account show `
    --resource-group $RESOURCE_GROUP `
    --name "<your-openai-resource-name>" `
    --query id -o tsv

az role assignment create `
    --assignee $PRINCIPAL_ID `
    --role "Cognitive Services OpenAI User" `
    --scope $OPENAI_RESOURCE_ID

# AI Searchへのアクセス権限を付与
$SEARCH_RESOURCE_ID = az search service show `
    --resource-group $RESOURCE_GROUP `
    --name "<your-search-service>" `
    --query id -o tsv

az role assignment create `
    --assignee $PRINCIPAL_ID `
    --role "Search Index Data Reader" `
    --scope $SEARCH_RESOURCE_ID

az role assignment create `
    --assignee $PRINCIPAL_ID `
    --role "Search Service Contributor" `
    --scope $SEARCH_RESOURCE_ID
```

## 確認事項

以下をすべて確認してください:

- ✅ GitHubリポジトリがフォーク/作成されている
- ✅ ローカルにクローンされている
- ✅ Python仮想環境が作成されている
- ✅ 依存関係がインストールされている
- ✅ `.env` ファイルが作成され、設定されている
- ✅ Azureリソース情報が収集されている
- ✅ GitHub Secretsが設定されている
- ✅ App Serviceの環境変数が設定されている
- ✅ Managed Identityの権限が付与されている

## トラブルシューティング

### Python仮想環境が作成できない

**症状**: `python -m venv venv` がエラーになる

**対処法**:
```powershell
# Pythonのバージョン確認
python --version

# 3.11以上であることを確認
# 古い場合は最新版をインストール
```

### Azure CLIコマンドが失敗する

**症状**: `az` コマンドがエラーになる

**対処法**:
```powershell
# ログイン状態を確認
az account show

# 再ログイン
az login

# サブスクリプションを明示的に指定
az account set --subscription "<subscription-id>"
```

### Managed Identity権限付与に失敗

**症状**: ロール割り当てコマンドがエラーになる

**対処法**:
- Azure Portal で自分のアカウントが「所有者」または「ユーザーアクセス管理者」ロールを持っているか確認
- リソースグループレベルで権限を確認

## 次のステップ

環境準備が完了したら、次は **[Step 2: データ準備](step02-data-preparation.md)** に進みましょう。

デジタル庁のオープンデータをダウンロードし、Blob Storageにアップロードします。
