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

#### 自動収集スクリプトの実行(推奨)

```powershell
# リソース情報を自動取得し、.envファイルを生成
.\scripts\get-azure-resources.ps1

# 特定のリソースグループを指定する場合
.\scripts\get-azure-resources.ps1 -ResourceGroup "rg-internal-rag-dev"

# サブスクリプションIDも指定する場合
.\scripts\get-azure-resources.ps1 -ResourceGroup "rg-internal-rag-dev" -SubscriptionId "your-subscription-id"
```

このスクリプトは以下を実行します:
- ✅ Azure OpenAI リソース名とエンドポイントを取得
- ✅ デプロイメント一覧を表示し、推奨デプロイメント名を自動選択
- ✅ AI Search サービス名とエンドポイントを取得
- ✅ Storage Account名を取得
- ✅ App Service名とURLを取得
- ✅ Key Vault名とURIを取得
- ✅ AI Foundry Hub/Project名を取得
- ✅ Virtual Network名を取得
- ✅ `.env` ファイルを自動生成

#### 手動で収集する場合

```powershell
# リソースグループ名を設定
$RESOURCE_GROUP = "rg-internal-rag-dev"

# Azureにログイン
az login

# サブスクリプション設定
az account set --subscription "<your-subscription-id>"

# Azure OpenAI リソース名を取得
$OPENAI_NAME = az cognitiveservices account list `
    --resource-group $RESOURCE_GROUP `
    --query "[?kind=='OpenAI'].name" -o tsv

# Azure OpenAI エンドポイント取得
$OPENAI_ENDPOINT = az cognitiveservices account show `
    --resource-group $RESOURCE_GROUP `
    --name $OPENAI_NAME `
    --query "properties.endpoint" -o tsv

Write-Host "Azure OpenAI Name: $OPENAI_NAME"
Write-Host "Azure OpenAI Endpoint: $OPENAI_ENDPOINT"

# デプロイメント一覧を表示
az cognitiveservices account deployment list `
    --resource-group $RESOURCE_GROUP `
    --name $OPENAI_NAME `
    --query "[].{Name:name, Model:properties.model.name}" -o table

# AI Search サービス名取得
$SEARCH_NAME = az search service list `
    --resource-group $RESOURCE_GROUP `
    --query "[0].name" -o tsv

$SEARCH_ENDPOINT = "https://$SEARCH_NAME.search.windows.net"
Write-Host "AI Search Name: $SEARCH_NAME"
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

#### Azure OpenAIのカスタムドメイン設定

Azure OpenAIでManaged Identity認証を使用するには、カスタムドメインの設定が必要です。

```powershell
# カスタムドメインを設定
az cognitiveservices account update `
    --resource-group "rg-internal-rag-dev" `
    --name "aoai-internal-rag-dev" `
    --custom-domain "aoai-internal-rag-dev"

# 設定確認
az cognitiveservices account show `
    --resource-group "rg-internal-rag-dev" `
    --name "aoai-internal-rag-dev" `
    --query "{endpoint:properties.endpoint, customDomain:properties.customSubDomainName}" -o json
```

> 💡 **重要**: カスタムドメインが設定されていない場合、リージョンエンドポイント (`https://japaneast.api.cognitive.microsoft.com/`) のみが利用可能で、Managed Identity認証が使用できません。

#### 自動生成された.envファイルの確認

`get-azure-resources.ps1` スクリプトを実行すると、`.env` ファイルが自動的に生成されます。

```powershell
# .envファイルの内容を確認
Get-Content .env

# VS Codeで編集
code .env
```

生成される `.env` ファイルの例:

```bash
# Azure リソース情報
# 生成日時: 2025-11-16 10:00:00
# リソースグループ: rg-internal-rag-dev

# Azure OpenAI 設定
AZURE_OPENAI_RESOURCE_NAME=oai-internal-rag-dev
AZURE_OPENAI_ENDPOINT=https://oai-internal-rag-dev.openai.azure.com/
AZURE_OPENAI_DEPLOYMENT=gpt-4

# Azure AI Search 設定
AZURE_SEARCH_SERVICE_NAME=srch-internal-rag-dev
AZURE_SEARCH_ENDPOINT=https://srch-internal-rag-dev.search.windows.net
AZURE_SEARCH_INDEX=redlist-index

# Azure Storage 設定
AZURE_STORAGE_ACCOUNT_NAME=stinternalragdev
AZURE_STORAGE_CONTAINER=redlist-data

# App Service 設定
AZURE_WEBAPP_NAME=app-internal-rag-dev
AZURE_WEBAPP_URL=https://app-internal-rag-dev.azurewebsites.net

# Key Vault 設定
AZURE_KEYVAULT_NAME=kv-internal-rag-dev
AZURE_KEYVAULT_URI=https://kv-internal-rag-dev.vault.azure.net/

# AI Foundry 設定
AI_FOUNDRY_HUB_NAME=aih-internal-rag-dev
AI_FOUNDRY_PROJECT_NAME=aip-internal-rag-dev

# Virtual Network 設定
AZURE_VNET_NAME=vnet-internal-rag-dev

# アプリケーション設定
FLASK_ENV=development
RESOURCE_GROUP=rg-internal-rag-dev
```

#### 手動で作成する場合

```powershell
# .env.sampleをコピー
Copy-Item .env.sample .env

# .envファイルを編集
code .env
```

> ⚠️ **注意**: `.env` ファイルは `.gitignore` に含まれており、Gitにコミットされません。

> 💡 **ヒント**: `<your-openai-resource-name>` は `AZURE_OPENAI_RESOURCE_NAME` の値です。AI Foundryを使用している場合、AI Foundry Projectに接続されたAzure OpenAIリソースの名前になります。

### 4. Python仮想環境のセットアップ

```powershell
# 仮想環境を作成
python -m venv venv

# 仮想環境を有効化
.\venv\Scripts\Activate.ps1

# 依存関係をインストール
pip install --upgrade pip

# ビルド済みバイナリのみを使用してインストール (Windows環境推奨)
pip install --only-binary :all: -r requirements.txt

# または、個別にインストール
# pip install flask gunicorn openai azure-identity azure-search-documents azure-core python-dotenv pandas

# インストール確認
pip list
```

> 💡 **Windows環境での注意**: C/C++コンパイラがインストールされていない場合、numpy/pandasのビルドに失敗します。`--only-binary :all:` オプションを使用することで、ビルド済みバイナリのみをインストールし、ビルドエラーを回避できます。

### 5. ローカル開発用の権限設定

ローカル開発環境で Azure リソースにアクセスするため、自分のユーザーアカウントに必要な権限を付与します。

```powershell
# .envファイルから環境変数を読み込む
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^#][^=]+)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        Set-Variable -Name $name -Value $value -Scope Script
    }
}

# 現在のユーザーのオブジェクトIDを取得
$USER_OBJECT_ID = az ad signed-in-user show --query id -o tsv
Write-Host "User Object ID: $USER_OBJECT_ID" -ForegroundColor Green

# サブスクリプションIDを取得
$SUBSCRIPTION_ID = az account show --query id -o tsv

# Azure OpenAIへのアクセス権限を付与
Write-Host "Granting Azure OpenAI access..." -ForegroundColor Yellow
az role assignment create `
    --assignee $USER_OBJECT_ID `
    --role "Cognitive Services OpenAI User" `
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$AZURE_OPENAI_RESOURCE_NAME"

# AI Searchへのアクセス権限を付与
Write-Host "Granting AI Search access..." -ForegroundColor Yellow
az role assignment create `
    --assignee $USER_OBJECT_ID `
    --role "Search Index Data Reader" `
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Search/searchServices/$AZURE_SEARCH_SERVICE_NAME"

# Storage Accountへのアクセス権限を付与
Write-Host "Granting Storage Account access..." -ForegroundColor Yellow
az role assignment create `
    --assignee $USER_OBJECT_ID `
    --role "Storage Blob Data Contributor" `
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$AZURE_STORAGE_ACCOUNT_NAME"

Write-Host "✓ Local user permissions granted" -ForegroundColor Green
```

> 📝 **Note**: ローカル開発では `az login` で認証した資格情報が使用されます。App Service上では Managed Identity が使用されます。

### 6. Azure接続テスト

Managed Identityを使用してAzureリソースへの接続をテストします。

```powershell
# テストスクリプトを実行
python scripts/test-azure-connection.py
```

> ⚠️ **Private Endpoint環境での制限**: 
> - **VPN接続なし**: Azure AI SearchやAzure OpenAIがPrivate Endpointのみでアクセス可能に構成されている場合、ローカル環境からの接続テストは失敗します
> - **VPN接続あり**: vNetに接続できる場合、Azure OpenAIは接続可能ですが、AI SearchはPrivate DNS解決の設定により失敗する可能性があります
> - **AI Searchインデックス未作成**: Step 3でインデックスを作成するまで、AI Search接続テストは失敗します(正常動作)

期待される出力 (Azure OpenAI):
```
=== Testing Azure OpenAI Connection ===
Endpoint: https://aoai-internal-rag-dev.openai.azure.com/
Deployment: gpt-4o-mini
✅ Azure OpenAI connection successful!
Response: Hello! How can I assist you today?
```

期待される出力 (AI Search - インデックス作成後):
```
=== Testing Azure AI Search Connection ===
Endpoint: https://srch-internal-rag-dev.search.windows.net
Index: redlist-index
✅ Azure AI Search connection successful!
```

**Private Endpoint環境の場合**:
- Azure AI Search: `publicNetworkAccess` が `Disabled` の場合、VPN接続またはApp Service経由でのみアクセス可能
- この構成はセキュリティ上推奨される設定です
- App ServiceはvNet統合されているため、デプロイ後は正常に動作します
- AI Searchの完全な動作確認はStep 3 (インデックス作成後) またはApp Serviceデプロイ後に行います

### 7. GitHub Secretsの設定

[Step 8のドキュメント](https://github.com/matakaha/internal_rag_Application_deployment_step_by_step/blob/main/bicep/step08-github-actions/README.md#2-github-secretsの設定)で設定したSecretsに加えて、アプリケーション固有の設定を追加します。

#### 必要なSecrets

| Secret名 | 説明 | 取得方法 |
|---------|------|---------|
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAIエンドポイント | `.env`ファイルの`AZURE_OPENAI_ENDPOINT` |
| `AZURE_OPENAI_DEPLOYMENT` | デプロイメント名 | `.env`ファイルの`AZURE_OPENAI_DEPLOYMENT` |
| `AZURE_SEARCH_ENDPOINT` | AI Searchエンドポイント | `.env`ファイルの`AZURE_SEARCH_ENDPOINT` |
| `AZURE_SEARCH_INDEX` | インデックス名 | `.env`ファイルの`AZURE_SEARCH_INDEX` |

#### GitHub CLIで設定(推奨)

`get-azure-resources.ps1` で生成された `.env` ファイルから値を読み込んで設定:

```powershell
# .envファイルから環境変数を読み込む
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^#][^=]+)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        Set-Variable -Name $name -Value $value -Scope Script
    }
}

# GitHub Secretsに設定
gh secret set AZURE_OPENAI_ENDPOINT -b "$AZURE_OPENAI_ENDPOINT"
gh secret set AZURE_OPENAI_DEPLOYMENT -b "$AZURE_OPENAI_DEPLOYMENT"
gh secret set AZURE_SEARCH_ENDPOINT -b "$AZURE_SEARCH_ENDPOINT"
gh secret set AZURE_SEARCH_INDEX -b "$AZURE_SEARCH_INDEX"

# 設定確認
gh secret list
```

#### 手動で設定する場合

```powershell
# リポジトリディレクトリで実行
gh secret set AZURE_OPENAI_ENDPOINT -b "https://your-openai.openai.azure.com/"
gh secret set AZURE_OPENAI_DEPLOYMENT -b "gpt-4"
gh secret set AZURE_SEARCH_ENDPOINT -b "https://your-search.search.windows.net"
gh secret set AZURE_SEARCH_INDEX -b "redlist-index"
```

#### GitHub Webで設定

1. GitHubリポジトリページを開く
2. `Settings` → `Secrets and variables` → `Actions` を選択
3. `New repository secret` をクリック
4. 各Secretを追加

### 8. App Service設定の更新

App Serviceに環境変数を設定します。`.env` ファイルから値を読み込んで一括設定できます。

#### 自動設定スクリプト(推奨)

```powershell
# .envファイルから環境変数を読み込む
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^#][^=]+)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        Set-Variable -Name $name -Value $value -Scope Script
    }
}

# App Serviceに環境変数を設定
az webapp config appsettings set `
    --resource-group $RESOURCE_GROUP `
    --name $AZURE_WEBAPP_NAME `
    --settings `
        AZURE_OPENAI_ENDPOINT="$AZURE_OPENAI_ENDPOINT" `
        AZURE_OPENAI_DEPLOYMENT="$AZURE_OPENAI_DEPLOYMENT" `
        AZURE_SEARCH_ENDPOINT="$AZURE_SEARCH_ENDPOINT" `
        AZURE_SEARCH_INDEX="$AZURE_SEARCH_INDEX" `
        AZURE_STORAGE_ACCOUNT_NAME="$AZURE_STORAGE_ACCOUNT_NAME" `
        AZURE_STORAGE_CONTAINER="$AZURE_STORAGE_CONTAINER"

# 設定確認
az webapp config appsettings list `
    --resource-group $RESOURCE_GROUP `
    --name $AZURE_WEBAPP_NAME `
    --output table
```

#### 手動で設定する場合

```powershell
# App Serviceに環境変数を設定
az webapp config appsettings set `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --settings `
        AZURE_OPENAI_ENDPOINT="$OPENAI_ENDPOINT" `
        AZURE_OPENAI_DEPLOYMENT="gpt-4" `
        AZURE_SEARCH_ENDPOINT="$SEARCH_ENDPOINT" `
        AZURE_SEARCH_INDEX="redlist-index"

# 設定確認
az webapp config appsettings list `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --output table
```

### 9. App Service Managed Identityの権限設定

App ServiceのManaged IdentityにAzureリソースへのアクセス権限を付与します。

> 📝 **Note**: この手順はStep 5で設定したローカル開発用の権限とは別に、App Service (本番環境) で実行されるアプリケーションがAzureリソースにアクセスするための権限です。

```powershell
# .envファイルから環境変数を読み込む(まだの場合)
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^#][^=]+)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        Set-Variable -Name $name -Value $value -Scope Script
    }
}

# App ServiceのManaged Identity(プリンシパルID)を取得
$PRINCIPAL_ID = az webapp identity show `
    --resource-group $RESOURCE_GROUP `
    --name $AZURE_WEBAPP_NAME `
    --query principalId -o tsv

Write-Host "App Service Managed Identity: $PRINCIPAL_ID" -ForegroundColor Green

# Azure OpenAIへのアクセス権限を付与
$OPENAI_RESOURCE_ID = az cognitiveservices account show `
    --resource-group $RESOURCE_GROUP `
    --name $AZURE_OPENAI_RESOURCE_NAME `
    --query id -o tsv

az role assignment create `
    --assignee $PRINCIPAL_ID `
    --role "Cognitive Services OpenAI User" `
    --scope $OPENAI_RESOURCE_ID

Write-Host "✓ Azure OpenAI アクセス権限を付与しました" -ForegroundColor Green

# AI Searchへのアクセス権限を付与
$SEARCH_RESOURCE_ID = az search service show `
    --resource-group $RESOURCE_GROUP `
    --name $AZURE_SEARCH_SERVICE_NAME `
    --query id -o tsv

az role assignment create `
    --assignee $PRINCIPAL_ID `
    --role "Search Index Data Reader" `
    --scope $SEARCH_RESOURCE_ID

az role assignment create `
    --assignee $PRINCIPAL_ID `
    --role "Search Service Contributor" `
    --scope $SEARCH_RESOURCE_ID

Write-Host "✓ AI Search アクセス権限を付与しました" -ForegroundColor Green

# Storage Accountへのアクセス権限を付与
$STORAGE_RESOURCE_ID = az storage account show `
    --resource-group $RESOURCE_GROUP `
    --name $AZURE_STORAGE_ACCOUNT_NAME `
    --query id -o tsv

az role assignment create `
    --assignee $PRINCIPAL_ID `
    --role "Storage Blob Data Contributor" `
    --scope $STORAGE_RESOURCE_ID

Write-Host "✓ Storage Account アクセス権限を付与しました" -ForegroundColor Green

# AI SearchのManaged Identityを有効化
Write-Host "`nEnabling AI Search Managed Identity..." -ForegroundColor Yellow

# AI SearchにシステムマネージドIDを設定
az search service update `
    --resource-group $RESOURCE_GROUP `
    --name $AZURE_SEARCH_SERVICE_NAME `
    --identity-type SystemAssigned

# AI SearchのManaged Identity(プリンシパルID)を取得
$SEARCH_PRINCIPAL_ID = az search service show `
    --resource-group $RESOURCE_GROUP `
    --name $AZURE_SEARCH_SERVICE_NAME `
    --query identity.principalId -o tsv

Write-Host "AI Search Managed Identity: $SEARCH_PRINCIPAL_ID" -ForegroundColor Green

# AI Search → Storage Accountへのアクセス権限を付与
az role assignment create `
    --assignee $SEARCH_PRINCIPAL_ID `
    --role "Storage Blob Data Reader" `
    --scope $STORAGE_RESOURCE_ID

Write-Host "✓ AI Search → Storage Account アクセス権限を付与しました" -ForegroundColor Green

# 権限の確認
Write-Host "`nApp Service ロール割り当て:" -ForegroundColor Cyan
az role assignment list --all --query "[?principalId=='$PRINCIPAL_ID'].{Role:roleDefinitionName, Scope:scope}" -o table

Write-Host "`nAI Search ロール割り当て:" -ForegroundColor Cyan
az role assignment list --all --query "[?principalId=='$SEARCH_PRINCIPAL_ID'].{Role:roleDefinitionName, Scope:scope}" -o table
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

e-Govデータポータルのレッドリスト(絶滅危惧種データ)をダウンロードし、Blob Storageにアップロードします。
