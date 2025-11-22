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
- Azure Functions (AppServicePlan B1共有、vNet統合済み)
- App Service Plan (B1) - フロントエンド/バックエンド共有

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

# Azure Functions Core Toolsバージョン確認
func --version
# 必要: 4.x以上
# 未インストールの場合:
# winget install Microsoft.Azure.FunctionsCoreTools

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

# Azure Functions 名前取得
$FUNCTIONAPP_NAME = az functionapp list `
    --resource-group $RESOURCE_GROUP `
    --query "[0].name" -o tsv

Write-Host "Azure Functions Name: $FUNCTIONAPP_NAME"

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

# Azure Functions 設定
AZURE_FUNCTIONAPP_NAME=func-internal-rag-dev
AZURE_FUNCTIONAPP_URL=https://func-internal-rag-dev.azurewebsites.net

# Key Vault 設定
AZURE_KEYVAULT_NAME=kv-internal-rag-dev
AZURE_KEYVAULT_URI=https://kv-internal-rag-dev.vault.azure.net/

# AI Foundry 設定
AI_FOUNDRY_HUB_NAME=aih-internal-rag-dev
AI_FOUNDRY_PROJECT_NAME=aip-internal-rag-dev

# Virtual Network 設定
AZURE_VNET_NAME=vnet-internal-rag-dev

# アプリケーション設定
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
# pip install azure-functions openai azure-identity azure-search-documents azure-core python-dotenv pandas

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

az role assignment create `
    --assignee $USER_OBJECT_ID `
    --role "Search Service Contributor" `
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Search/searchServices/$AZURE_SEARCH_SERVICE_NAME"

# Storage Accountへのアクセス権限を付与
Write-Host "Granting Storage Account access..." -ForegroundColor Yellow
az role assignment create `
    --assignee $USER_OBJECT_ID `
    --role "Storage Blob Data Contributor" `
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$AZURE_STORAGE_ACCOUNT_NAME"

Write-Host "✓ Local user permissions granted" -ForegroundColor Green
```

> 📝 **Note**: ローカル開発では `az login` で認証した資格情報が使用されます。Azure Functions上では Managed Identity が使用されます。

> ⚠️ **Managed Identity 権限の反映について**:
> - ロール割り当て後、権限が反映されるまで **1〜5分程度** かかる場合があります
> - この間、接続テストで `Forbidden (403)` エラーが発生する可能性があります
> - 権限反映を待っている間は、一時的に **API キー認証** を使用できます(後述)

### 6. Azure接続テスト

Managed Identityを使用してAzureリソースへの接続をテストします。

> 📝 **初学者向け: Managed Identityとは？**
> 
> **Managed Identity**は、Azureが自動的に管理してくれる「アプリケーション専用の身分証明書」です。
> 
> **従来の方法 (APIキー)**:
> - パスワードのような秘密の文字列をコードに書く
> - 定期的に更新が必要
> - 漏洩すると悪用される危険性
> 
> **Managed Identityの利点**:
> - ✅ Azureが自動的に作成・管理
> - ✅ パスワードを覚える必要なし
> - ✅ 自動的に期限が更新される
> - ✅ コードに秘密情報を書かなくて済む
> 
> **例え話**: 
> - APIキー = 合い言葉を覚えて毎回言う
> - Managed Identity = 顔認証で自動的に本人確認
> 
> このプロジェクトでは、Azure FunctionsとApp ServiceがManaged Identityを使って、
> Azure OpenAIやAI Searchに安全にアクセスします。

```powershell
# テストスクリプトを実行
python scripts/test-azure-connection.py
```

#### 期待される出力

**成功時 (Azure OpenAI)**:
```
=== Testing Azure OpenAI Connection ===
Endpoint: https://aoai-internal-rag-dev.openai.azure.com/
Deployment: gpt-4o-mini
✅ Azure OpenAI connection successful!
Response: Hello! How can I assist you today?
```

**成功時 (AI Search - Step 3 でインデックス作成前)**:
```
=== Testing Azure AI Search Connection ===
Endpoint: https://srch-internal-rag-dev.search.windows.net
Index: redlist-index
Using Managed Identity authentication
✅ Azure AI Search connection successful!
ℹ️  Index 'redlist-index' does not exist yet (will be created in Step 03)
```

**成功時 (AI Search - インデックス作成後)**:
```
=== Testing Azure AI Search Connection ===
Endpoint: https://srch-internal-rag-dev.search.windows.net
Index: redlist-index
Using Managed Identity authentication
✅ Azure AI Search connection successful!
✅ Index 'redlist-index' exists
```

#### トラブルシューティング

##### Managed Identity 権限エラー (403 Forbidden)

**症状**: 
```
❌ Authentication successful but insufficient permissions: Operation returned an invalid status 'Forbidden'
   Required role: 'Search Service Contributor' or 'Search Index Data Reader'
```

**原因**: 
- ロール割り当て直後で、権限がまだ反映されていない(1〜5分かかる場合があります)

**対処法 1: 権限の反映を待つ**
```powershell
# 数分待ってから再実行
Start-Sleep -Seconds 120
python scripts/test-azure-connection.py
```

**対処法 2: API キー認証を一時的に使用**

権限が反映されるまでの間、API キーを使用して接続テストを行うことができます:

```powershell
# AI Search の API キーを取得
$searchKey = az search admin-key show `
    --service-name srch-internal-rag-dev `
    --resource-group rg-internal-rag-dev `
    --query primaryKey -o tsv

# .env ファイルに一時的に追加
Add-Content .env "`n# Temporary API Key for testing (remove after Managed Identity is active)"
Add-Content .env "AZURE_SEARCH_KEY=$searchKey"

# テストを再実行
python scripts/test-azure-connection.py
```

> 💡 **重要**: API キーは一時的なテスト用です。本番環境では必ず Managed Identity を使用してください。
> 
> Managed Identity の権限が反映されたら、`.env` ファイルから `AZURE_SEARCH_KEY` の行を削除することを推奨します:
> ```powershell
> # API キーの行を削除
> (Get-Content .env) | Where-Object { $_ -notmatch "AZURE_SEARCH_KEY" } | Set-Content .env
> ```

##### Private Endpoint による接続制限

> ⚠️ **Private Endpoint環境での制限**: 
> - **VPN接続なし**: Azure AI SearchやAzure OpenAIがPrivate Endpointのみでアクセス可能に構成されている場合、ローカル環境からの接続テストは失敗します
> - **VPN接続あり**: vNetに接続できる場合、Azure OpenAIは接続可能ですが、AI SearchはPrivate DNS解決の設定により失敗する可能性があります
> - **AI Searchインデックス未作成**: Step 3でインデックスを作成するまで、AI Searchは存在しないインデックスへのアクセスとなります(正常動作)
> 
> 💡 **初学者向け: Private Endpointとは？**
> 
> **Private Endpoint**は、Azureサービスを「社内ネットワークの一部」のように扱う仕組みです。
> 
> **通常のアクセス**: 
> - インターネット経由で誰でもアクセス可能
> - セキュリティリスクが高い
> 
> **Private Endpointを使った場合**:
> - vNet(仮想ネットワーク)内からのみアクセス可能
> - インターネットから完全に遮断
> - 会社の内線電話のようなイメージ
> 
> **なぜローカルからアクセスできないのか？**
> - あなたのパソコンはvNetの「外側」にいる
> - Private Endpointは「内側」からしかアクセスできない
> - VPN接続すればvNetの「内側」に入れる
> 
> このプロジェクトでは、すべてのAzureリソースがPrivate Endpointで保護されており、
> Azure FunctionsやApp ServiceはvNet内に統合されているため、安全にアクセスできます。

**Private Endpoint環境の場合**:
- Azure AI Search: `publicNetworkAccess` が `Disabled` の場合、VPN接続またはAzure Functions経由でのみアクセス可能
- この構成はセキュリティ上推奨される設定です
- Azure FunctionsはvNet統合されているため、デプロイ後は正常に動作します
- AI Searchの完全な動作確認はStep 3 (インデックス作成後) またはAzure Functionsデプロイ後に行います

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

### 8. Azure Functions設定の更新

Azure Functionsに環境変数を設定します。`.env` ファイルから値を読み込んで一括設定できます。

> 📝 **Note**: 開発環境ではAppServicePlan B1を使用し、本番環境ではPremium Plan (EP1以上)を推奨します。

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

# Azure Functionsに環境変数を設定
az functionapp config appsettings set `
    --resource-group $RESOURCE_GROUP `
    --name $AZURE_FUNCTIONAPP_NAME `
    --settings `
        AZURE_OPENAI_ENDPOINT="$AZURE_OPENAI_ENDPOINT" `
        AZURE_OPENAI_DEPLOYMENT="$AZURE_OPENAI_DEPLOYMENT" `
        AZURE_SEARCH_ENDPOINT="$AZURE_SEARCH_ENDPOINT" `
        AZURE_SEARCH_INDEX="$AZURE_SEARCH_INDEX" `
        AZURE_STORAGE_ACCOUNT_NAME="$AZURE_STORAGE_ACCOUNT_NAME" `
        AZURE_STORAGE_CONTAINER="$AZURE_STORAGE_CONTAINER"

# 設定確認
az functionapp config appsettings list `
    --resource-group $RESOURCE_GROUP `
    --name $AZURE_FUNCTIONAPP_NAME `
    --output table
```

#### 手動で設定する場合

```powershell
# Azure Functionsに環境変数を設定
az functionapp config appsettings set `
    --resource-group $RESOURCE_GROUP `
    --name $AZURE_FUNCTIONAPP_NAME `
    --settings `
        AZURE_OPENAI_ENDPOINT="$OPENAI_ENDPOINT" `
        AZURE_OPENAI_DEPLOYMENT="gpt-4" `
        AZURE_SEARCH_ENDPOINT="$SEARCH_ENDPOINT" `
        AZURE_SEARCH_INDEX="redlist-index"

# 設定確認
az functionapp config appsettings list `
    --resource-group $RESOURCE_GROUP `
    --name $AZURE_FUNCTIONAPP_NAME `
    --output table
```

### 9. Azure Functions Managed Identityの権限設定

Azure FunctionsのManaged IdentityにAzureリソースへのアクセス権限を付与します。

> 📝 **Note**: この手順はStep 5で設定したローカル開発用の権限とは別に、Azure Functions (本番環境) で実行されるアプリケーションがAzureリソースにアクセスするための権限です。

```powershell
# .envファイルから環境変数を読み込む(まだの場合)
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^#][^=]+)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        Set-Variable -Name $name -Value $value -Scope Script
    }
}

# Azure FunctionsのManaged Identity(プリンシパルID)を取得
$PRINCIPAL_ID = az functionapp identity show `
    --resource-group $RESOURCE_GROUP `
    --name $AZURE_FUNCTIONAPP_NAME `
    --query principalId -o tsv

Write-Host "Azure Functions Managed Identity: $PRINCIPAL_ID" -ForegroundColor Green

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
Write-Host "`nAzure Functions ロール割り当て:" -ForegroundColor Cyan
az role assignment list --all --query "[?principalId=='$PRINCIPAL_ID'].{Role:roleDefinitionName, Scope:scope}" -o table

Write-Host "`nAI Search ロール割り当て:" -ForegroundColor Cyan
az role assignment list --all --query "[?principalId=='$SEARCH_PRINCIPAL_ID'].{Role:roleDefinitionName, Scope:scope}" -o table
```

### 10. GitHub Runnerイメージの作成・更新

このプロジェクトでは、GitHub ActionsでセルフホストランナーをAzure Container Instancesで動的に実行します。ランナー用のカスタムDockerイメージをAzure Container Registry (ACR) にビルド・保存する必要があります。

#### 対象ファイル

- `Dockerfile.runner`: GitHub Runnerのコンテナイメージ定義
- `start.sh`: ランナー起動スクリプト(ネットワーク診断・デバッグログ含む)

#### 初回ビルド vs 再ビルド

| タイミング | 手順 | 説明 |
|-----------|------|------|
| **初回セットアップ時** | このドキュメントの手順に従う | Docker なしの基本 Runner イメージ |
| **Docker 追加後** | [rebuild-runner-image.md](rebuild-runner-image.md) を参照 | Web App コンテナビルド用に Docker を追加 |

> **Note**: Web App をコンテナ化してデプロイする場合は、Runner に Docker をインストールする必要があります。詳細は [rebuild-runner-image.md](rebuild-runner-image.md) を参照してください。

#### ACRビルドが必要なケース

以下の場合、ACRで新しいイメージをビルドする必要があります:

| シナリオ | ACRビルド必要 | 理由 |
|---------|-------------|------|
| `Dockerfile.runner`を修正 | ✅ 必要 | イメージの構成変更 |
| `start.sh`を修正 | ✅ 必要 | 起動スクリプトがイメージに含まれる |
| ベースイメージの更新 | ✅ 推奨 | セキュリティパッチ適用のため |
| GitHub Runner バージョンアップ | ✅ 推奨 | 最新機能・修正を反映 |
| ワークフローファイルのみ修正 | ❌ 不要 | イメージは変更なし |
| 環境変数のみ変更 | ❌ 不要 | ランタイムで設定される |

#### 初回ビルド手順

> **Note**: 初回セットアップ時は以下のコマンドを使用してください。Docker を追加した再ビルドの場合は [rebuild-runner-image.md](rebuild-runner-image.md) を参照してください。

> 📝 **NAT Gateway によるセキュアなビルド環境**:
> 
> この環境では、ACR は Private Endpoint のみでアクセス可能に構成されており、パブリックアクセスは無効化されています。
> ACR Tasks でのビルドは、vNet 内のビルドエージェントから実行され、以下の経路で通信します:
> - **ACR へのアクセス**: Private Endpoint 経由 (vNet 内部通信)
> - **インターネットへのアクセス**: NAT Gateway 経由 (ベースイメージのダウンロードなど)
> 
> この構成により、ACR へのアクセスを閉域網内に限定しつつ、必要なインターネットリソースへのアクセスが可能になります。

**1. ACR 名の取得**

```powershell
# .envファイルから環境変数を読み込む(まだの場合)
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^#][^=]+)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        Set-Variable -Name $name -Value $value -Scope Script
    }
}

# ACR名を取得(リソースグループ内のACRを検索)
$ACR_NAME = az acr list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv
Write-Host "ACR Name: $ACR_NAME" -ForegroundColor Green
```

**2. 必要なベースイメージのインポート (完全閉域環境)**

> 📝 **完全閉域環境でのベースイメージ管理**
> 
> 完全閉域環境では、DockerHubなどの外部レジストリにアクセスできないため、必要なベースイメージを事前にACRにインポートする必要があります。
> 
> **インポートが必要なイメージ**:
> - `node:18-alpine`: Web Appフロントエンド用
> - `myoung34/github-runner:latest`: GitHub Runner基盤 (Dockerfile.runnerで使用)
> 
> `az acr import` コマンドは、Azure側でイメージをプルしてACRに格納するため、ローカル環境にDockerがインストールされていなくても実行可能です。

```powershell
# Node.js Alpine イメージをインポート (Web App用)
Write-Host "Importing node:18-alpine..." -ForegroundColor Yellow
az acr import `
  --name $ACR_NAME `
  --source docker.io/library/node:18-alpine `
  --image node:18-alpine

# GitHub Runner ベースイメージをインポート
Write-Host "Importing GitHub Runner base image..." -ForegroundColor Yellow
az acr import `
  --name $ACR_NAME `
  --source docker.io/myoung34/github-runner:latest `
  --image myoung34/github-runner:latest

# インポート完了確認
Write-Host "`n✓ Base images imported successfully" -ForegroundColor Green
az acr repository list --name $ACR_NAME --output table
```

> 💡 **ヒント**: インポートは一度実行すれば、イメージはACRに永続化されます。再実行の必要はありません。

**3. GitHub Runnerイメージのビルド**

> ⚠️ **Private Endpoint構成のACRでのビルドエラー**
> 
> ACRがPrivate Endpointのみで構成されている場合、`az acr build`コマンドは以下のエラーで失敗します:
> 
> ```
> failed to login: failed to set docker credentials: Error response from daemon: 
> Get "https://acrinternalragdev.azurecr.io/v2/": denied: 
> client with IP 'x.x.x.x' is not allowed access.
> ```
> 
> **原因**: ACR Tasksのビルドエージェントは、デフォルトでAzure管理のパブリックIP環境で実行されるため、Private EndpointのみのACRにアクセスできません。
> 
> **解決策は2つあります**:

<details>
<summary><b>解決策1: vNet統合ビルドエージェントを使用 (完全閉域・推奨)ですが、東日本リージョンでは利用できません（解決策2にて検証ください）</b></summary>

vNet内にビルドエージェント専用のAgent Poolを作成し、Private Endpoint経由でACRにアクセスします。

**メリット**:
- ✅ 完全閉域でセキュア
- ✅ Private Endpointのみでビルド可能

**デメリット**:
- ❌ 追加コスト: $144/月 (S1常時稼働) または $0.20/時間 (オンデマンド)
- ❌ Agent Pool作成に3〜5分の待ち時間
- ❌ 運用が複雑

**手順**:

```powershell
# Step 1: サブネットIDを取得
$SUBNET_ID = az network vnet subnet show `
  --resource-group rg-internal-rag-dev `
  --vnet-name vnet-internal-rag-dev `
  --name snet-compute `
  --query id -o tsv

# Step 2: vNet統合Agent Poolを作成
az acr agentpool create `
  --registry $ACR_NAME `
  --resource-group $RESOURCE_GROUP `
  --name vnetpool `
  --tier S1 `
  --subnet-id $SUBNET_ID

# Step 3: Agent Pool作成完了を待つ(3〜5分)
while ($true) {
    $status = az acr agentpool show `
      --registry $ACR_NAME `
      --name vnetpool `
      --query "provisioningState" -o tsv
    if ($status -eq "Succeeded") { 
        Write-Host "✓ Agent Pool ready!" -ForegroundColor Green
        break 
    }
    Write-Host "Status: $status - waiting..." -ForegroundColor Gray
    Start-Sleep -Seconds 10
}

# Step 4: Agent Poolを使用してビルド
az acr build `
  --registry $ACR_NAME `
  --resource-group $RESOURCE_GROUP `
  --agent-pool vnetpool `
  --image github-runner:latest `
  --image github-runner:v1.0.0 `
  --file Dockerfile.runner `
  .

# Step 5 (オプション): ビルド完了後、Agent Poolを削除してコスト削減
az acr agentpool delete --registry $ACR_NAME --name vnetpool --yes
```

**コスト最適化のヒント**:
- オンデマンド運用: ビルド前に作成、ビルド後に削除 → 約$0.03〜$0.10/ビルド
- 常時稼働: Agent Poolを維持 → $144/月 (運用が簡単)

</details>

<details>
<summary><b>解決策2: ビルドエージェントIPを一時的に許可 (開発環境推奨)</b></summary>

ACRのファイアウォールルールに、ビルドエージェントの実際のIPアドレスを一時的に追加します。

**メリット**:
- ✅ 追加コスト$0
- ✅ シンプルで分かりやすい
- ✅ 待ち時間なし

**デメリット**:
- ⚠️ ビルド中のみパブリックアクセスが有効(特定IP許可)
- ⚠️ ビルドエージェントIPが変わる可能性

**セキュリティ評価**:
- 許可IP: 特定の1つのみ (Azure管理IP)
- 公開期間: 5〜10分 (ビルド中のみ)
- リスク: **開発環境としては許容範囲**

**手順**:

```powershell
# Step 1: パブリックアクセスを一時的に有効化
Write-Host "Enabling public access temporarily..." -ForegroundColor Yellow
az acr update --name $ACR_NAME --public-network-enabled true

# Step 2: ビルドエージェントIPを許可リストに追加
# 
# １度 Step 3: ビルド実行のコマンドを実施して、エラーメッセージを取得し、エラーメッセージに表示されたIPを使用します。おそらくIP１つではエラーが解消しないと思います。自己責任にはなりますが、CIDRでレンジ指定を推奨します
$BUILD_AGENT_IP = "4.216.205.70"  # エラーメッセージから取得（レンジで指定する場合：4.216.205.0/24とする）
az acr network-rule add --name $ACR_NAME --ip-address $BUILD_AGENT_IP
Write-Host "✓ Added build agent IP: $BUILD_AGENT_IP" -ForegroundColor Green

# Step 3: ビルド実行
az acr build `
  --registry $ACR_NAME `
  --resource-group $RESOURCE_GROUP `
  --image github-runner:latest `
  --image github-runner:v1.0.0 `
  --file Dockerfile.runner `
  .

# Step 4: パブリックアクセスを無効化
Write-Host "Disabling public access..." -ForegroundColor Yellow
az acr update --name $ACR_NAME --public-network-enabled false
Write-Host "✓ ACR secured again" -ForegroundColor Green
```

> 💡 **ヒント**: エラーメッセージに表示されるビルドエージェントIPは実行毎に異なる場合があります。その場合は、Step 2のIPアドレスを更新してください。実行中に複数のIPを利用している場合もありますので、状況にあわせてIPをCIDR指定ください。

</details>

---

**通常のビルド手順 (ACRがパブリックアクセス可能な場合)**:

```powershell
# 基本的なビルド (latestタグのみ)
az acr build `
  --registry $ACR_NAME `
  --resource-group $RESOURCE_GROUP `
  --image github-runner:latest `
  --file Dockerfile.runner `
  .

# バージョンタグ付きビルド (推奨)
az acr build `
  --registry $ACR_NAME `
  --resource-group $RESOURCE_GROUP `
  --image github-runner:latest `
  --image github-runner:v1.0.0 `
  --file Dockerfile.runner `
  .
```

> **重要**: カレントディレクトリがリポジトリルート(`internal_rag_Application_sample_repo`)であることを確認してください

#### ビルド状況の確認

```powershell
# ビルド履歴の確認(最新3件)
az acr task list-runs `
  --registry $ACR_NAME `
  --top 3 `
  -o table

# 特定のビルドIDのステータス監視
$buildId = "ce7"  # 実際のビルドIDに置き換え
while ($true) {
    $status = az acr task list-runs `
      --registry $ACR_NAME `
      --run-id $buildId `
      --query "[0].status" `
      -o tsv
    Write-Host "Status: $status ($(Get-Date -Format 'HH:mm:ss'))"
    if ($status -eq "Succeeded" -or $status -eq "Failed") { break }
    Start-Sleep -Seconds 10
}

# イメージタグの確認
az acr repository show-tags `
  --name $ACR_NAME `
  --repository github-runner `
  --orderby time_desc `
  --top 5 `
  -o table
```

#### ベストプラクティス

1. **バージョンタグの運用**: 
   - `latest`タグのみではなく、`v1.2.0`などのセマンティックバージョニングを併用
   - ロールバック時に特定バージョンを指定可能

2. **ビルド前の動作確認**:
   - ローカルでDockerイメージをビルドして動作確認
   - `docker build -f Dockerfile.runner -t test-runner .`

3. **定期的な更新**:
   - ベースイメージ(`mcr.microsoft.com/cbl-mariner/base/core:2.0`)のセキュリティパッチ適用
   - GitHub Runnerの最新バージョンへの更新(`RUNNER_VERSION`環境変数)

## 確認事項

以下をすべて確認してください:

- ✅ GitHubリポジトリがフォーク/作成されている
- ✅ ローカルにクローンされている
- ✅ Python仮想環境が作成されている
- ✅ 依存関係がインストールされている
- ✅ `.env` ファイルが作成され、設定されている
- ✅ Azureリソース情報が収集されている
- ✅ ローカル開発用の権限が付与されている
- ✅ Azure接続テストが成功している
- ✅ GitHub Secretsが設定されている
- ✅ Azure Functionsの環境変数が設定されている
- ✅ Azure Functions Managed Identityの権限が付与されている
- ✅ **GitHub RunnerイメージがACRにビルドされている**

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

### GitHub Runnerイメージのビルドが失敗する

#### ケース1: Private Endpoint構成のACRでアクセス拒否エラー

**症状**: 
```
failed to login: Error response from daemon: 
Get "https://acrinternalragdev.azurecr.io/v2/": denied: 
client with IP 'x.x.x.x' is not allowed access.
```

**原因**: ACRがPrivate Endpointのみで構成されており、ビルドエージェント(Azure管理のパブリックIP環境)からアクセスできない

**対処法**: Step 10の「イメージのビルド」セクションにある**解決策1または解決策2**を参照してください

#### ケース2: その他のビルドエラー

**症状**: `az acr build` コマンドがエラーで終了

**対処法**:
```powershell
# ビルドログの確認
az acr task logs --registry $ACR_NAME --run-id <build-id>

# よくあるエラー:
# - "unknown instruction: SET" → Dockerfileの構文エラー(heredoc非対応)
# - "Can't detect current OS type" → installdependencies.sh実行エラー(CBL Mariner非対応)
# - "permission denied" → COPY/CHOWNの権限問題
```

### GitHub Runnerイメージがプルできない

**症状**: Container Instancesでイメージプルに失敗

**対処法**:
- ACRでPrivate Endpointが有効化されているか確認
- Container InstancesでUser Assigned Managed Identityが設定されているか確認(`--acr-identity`パラメータ)
- NSGでHTTPS(443)のアウトバウンドが許可されているか確認

## 次のステップ

環境準備が完了したら、次は **[Step 2: データ準備](step02-data-preparation.md)** に進みましょう。

e-Govデータポータルのレッドリスト(絶滅危惧種データ)をダウンロードし、Blob Storageにアップロードします。
