# Step 4: アプリケーションデプロイ

このステップでは、GitHub Actionsを使用してPythonチャットアプリケーションをAzure Functions (AppServicePlan)にデプロイします。

## 📚 学習目標

このステップを完了すると、以下ができるようになります:

- GitHub Actionsワークフローの理解
- Self-hosted Runnerを使用した閉域デプロイ
- Azure Functions設定の構成
- CI/CDパイプラインの実行
- デプロイの確認とトラブルシューティング

## 前提条件

- Step 1, 2, 3が完了していること
- [internal_rag_Application_deployment_step_by_step](https://github.com/matakaha/internal_rag_Application_deployment_step_by_step)の以下のステップが完了していること:
  - [Step 03 (GitHub Actions)](https://github.com/matakaha/internal_rag_Application_deployment_step_by_step/tree/main/bicep/step03-github-actions): GitHub Actions環境の構築
  - **Azure Container Registry (ACR) のセットアップ**: カスタムGitHub Runnerイメージ(`acrinternalragdev.azurecr.io/github-runner:latest`)が作成済みであること
- GitHub Secretsが設定済みであること
- Key Vaultに必要なシークレットが格納されていること

## デプロイ手順

### 1. アプリケーション設定の確認

#### Azure Functions設定の確認

```powershell
$RESOURCE_GROUP = "rg-internal-rag-dev"
$FUNCTIONAPP_NAME = "<your-functionapp-name>"

# 現在の設定を確認
az functionapp config appsettings list `
    --resource-group $RESOURCE_GROUP `
    --name $FUNCTIONAPP_NAME `
    --output table
```

#### 必要な環境変数

| 変数名 | 説明 | 設定方法 |
|-------|------|---------|
| `AZURE_OPENAI_ENDPOINT` | OpenAIエンドポイント | Step 1で設定済み |
| `AZURE_OPENAI_DEPLOYMENT` | デプロイメント名 | Step 1で設定済み |
| `AZURE_SEARCH_ENDPOINT` | AI Searchエンドポイント | Step 1で設定済み |
| `AZURE_SEARCH_INDEX` | インデックス名 | Step 3で作成 |
| `AzureWebJobsFeatureFlags` | Functions機能フラグ | `EnableWorkerIndexing` |
| `FUNCTIONS_WORKER_RUNTIME` | ランタイム | `python` |

#### 追加設定

```powershell
# Functions固有の設定
az functionapp config appsettings set `
    --resource-group $RESOURCE_GROUP `
    --name $FUNCTIONAPP_NAME `
    --settings `
        AzureWebJobsFeatureFlags=EnableWorkerIndexing `
        FUNCTIONS_WORKER_RUNTIME=python

# Pythonバージョンの確認
az functionapp show `
    --resource-group $RESOURCE_GROUP `
    --name $FUNCTIONAPP_NAME `
    --query "siteConfig.linuxFxVersion" -o tsv

# AppServicePlanの確認
az functionapp show `
    --resource-group $RESOURCE_GROUP `
    --name $FUNCTIONAPP_NAME `
    --query "appServicePlanId" -o tsv
```

> 📝 **Note**: 開発環境ではAppServicePlan B1をフロントエンドと共有、本番環境ではPremium Plan (EP1以上)を推奨します。

### 2. Federated Identity (OIDC) 認証の設定

GitHub ActionsからAzureへの認証には、Federated Identity (OIDC)を使用します。これにより、長期的なシークレットを管理する必要がなくなります。

#### 2.1. サービスプリンシパルの作成

```powershell
# Azure ADにアプリケーション登録を作成
$appName = "github-actions-oidc-internal-rag"
$app = az ad app create --display-name $appName | ConvertFrom-Json

# サービスプリンシパルを作成
az ad sp create --id $app.appId

# リソースグループへのContributor権限を付与
$subscriptionId = (az account show --query id -o tsv)
az role assignment create `
    --assignee $app.appId `
    --role Contributor `
    --scope "/subscriptions/$subscriptionId/resourceGroups/rg-internal-rag-dev"

Write-Host "Application (client) ID: $($app.appId)"
```

#### 2.2. Federated Credentialの設定

```powershell
# GitHubリポジトリ情報を設定
$githubOrg = "matakaha"  # あなたのGitHubユーザー名/組織名
$githubRepo = "internal_rag_Application_sample_repo"  # リポジトリ名

# Federated Credentialを一時JSONファイルとして作成
$credentialName = "github-actions-main"
$credentialPath = "federated-credential.json"
@{
    name = $credentialName
    issuer = "https://token.actions.githubusercontent.com"
    subject = "repo:$githubOrg/${githubRepo}:ref:refs/heads/main"
    audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json -Depth 10 | Out-File -FilePath $credentialPath -Encoding UTF8

# Federated credentialを作成
az ad app federated-credential create `
    --id $app.appId `
    --parameters "@$credentialPath"

Write-Host "Federated credential created successfully"

# 一時ファイルを削除
Remove-Item $credentialPath -ErrorAction SilentlyContinue
```

#### 2.3. Key Vaultアクセス権限の付与

サービスプリンシパルがKey Vaultからシークレットを読み取れるように権限を付与します。

```powershell
# Key Vault名を取得(環境に応じて変更)
$keyVaultName = "kv-gh-runner-dev"  # あなたのKey Vault名

# サービスプリンシパルにKey Vaultのシークレット読み取り権限を付与
az keyvault set-policy `
    --name $keyVaultName `
    --spn $app.appId `
    --secret-permissions get list

Write-Host "Key Vault access granted successfully"
```

#### 2.4. User Access Administrator権限の付与

ワークフロー内でContainer InstanceのManaged IdentityにACR Pull権限を動的に付与するため、サービスプリンシパルに`User Access Administrator`ロールを付与します。

```powershell
# サービスプリンシパルにUser Access Administratorロールを付与
az role assignment create `
    --assignee $app.appId `
    --role "User Access Administrator" `
    --scope "/subscriptions/$subscriptionId/resourceGroups/rg-internal-rag-dev"

Write-Host "User Access Administrator role granted successfully"
```

**重要**: この権限により、ワークフロー実行時に以下が可能になります:
- Container InstanceのManaged Identityを作成
- そのManaged IdentityにACR Pullロールを付与
- Private Endpoint保護されたACRからGitHub Runnerイメージを安全にpull(vNet内部通信)

> 📝 **Note**: この権限はリソースグループスコープに限定されており、他のIDに権限を付与する操作はこのリソースグループ内のリソースに対してのみ可能です。Container InstanceはPrivate Endpoint経由でACRにアクセスするため、ACRのパブリック公開は不要です。

#### 2.5. GitHub Secretsの設定

```powershell
# 必要な情報を取得
$tenantId = (az account show --query tenantId -o tsv)
$subscriptionId = (az account show --query id -o tsv)

# GitHub Secretsを設定
gh secret set AZURE_CLIENT_ID --body $app.appId
gh secret set AZURE_TENANT_ID --body $tenantId
gh secret set AZURE_SUBSCRIPTION_ID --body $subscriptionId
gh secret set KEY_VAULT_NAME --body "kv-gh-runner-dev"  # あなたのKey Vault名

# GitHub PAT(Personal Access Token)を設定
# 注: Key VaultはPrivate Endpointで保護されているため、GitHub-hostedランナーから
# アクセスできません。そのため、GH_PATは直接GitHub Secretsに設定します。
Write-Host "GitHub Personal Access Tokenを入力してください:"
gh secret set GH_PAT

# その他のSecretsも設定
gh secret set AZURE_OPENAI_ENDPOINT --body "https://your-openai.openai.azure.com/"
gh secret set AZURE_OPENAI_DEPLOYMENT --body "gpt-4"
gh secret set AZURE_SEARCH_ENDPOINT --body "https://your-search.search.windows.net"
gh secret set AZURE_SEARCH_INDEX --body "redlist-index"

# 設定確認
gh secret list
```

#### 2.6. 設定内容の確認

以下のコマンドでFederated Identity設定が正しく行われたか確認します:

```powershell
# サービスプリンシパルのObject IDを確認
$spObjectId = (az ad sp show --id $app.appId --query id -o tsv)
Write-Host "Service Principal Object ID: $spObjectId"

# Federated Credentialを確認
az ad app federated-credential list --id $app.appId --output table

# ロール割り当てを確認
az role assignment list --assignee $app.appId --output table

Write-Host "`n=== 確認完了 ==="
Write-Host "Application ID: $($app.appId)"
Write-Host "Tenant ID: $tenantId"
Write-Host "Subscription ID: $subscriptionId"
```

#### 2.7. GitHub Secretsの確認

以下のSecretsが設定されているか確認します:

```powershell
# GitHub CLIで確認
gh secret list

# 必要なSecrets:
# - AZURE_CLIENT_ID (Federated Identity用)
# - AZURE_TENANT_ID (Federated Identity用)
# - AZURE_SUBSCRIPTION_ID (Federated Identity用)
# - KEY_VAULT_NAME
# - GH_PAT (GitHub Personal Access Token - Runner登録用)
# - AZURE_OPENAI_ENDPOINT
# - AZURE_OPENAI_DEPLOYMENT
# - AZURE_SEARCH_ENDPOINT
# - AZURE_SEARCH_INDEX
```

### 3. ワークフローファイルの確認

`.github/workflows/deploy-functions.yml` の内容を確認します。

主要な設定:

```yaml
env:
  RESOURCE_GROUP: 'rg-internal-rag-dev'
  FUNCTIONAPP_NAME: 'func-internal-rag-dev'  # ←あなたのFunctions App名に変更
  CONTAINER_GROUP_NAME: 'aci-runner-${{ github.run_id }}'
  VNET_NAME: 'vnet-internal-rag-dev'
  SUBNET_NAME: 'snet-container-instances'
  LOCATION: 'japaneast'
  PYTHON_VERSION: '3.11'
```

**重要**: このワークフローは、Azure Container Registry (ACR)に格納されたカスタムGitHub Runnerイメージ(`acrinternalragdev.azurecr.io/github-runner:latest`)を使用します。このイメージには、GitHub Runnerと必要なツールがプリインストールされており、起動が高速で安定しています。

**ACR認証方式**: ワークフローでは、Container InstanceのManaged Identityを使用してACRにアクセスします。Container InstanceとACRのPrivate Endpointは同じvNet内にあるため、vNet内部通信で安全にイメージをpullできます。ACRのパブリック公開は不要です。

必要に応じて、環境変数を自分の環境に合わせて編集します。

### 4. コードの準備とプッシュ

#### ローカルでテスト(オプション)

```powershell
# 仮想環境を有効化
.\.venv\Scripts\Activate.ps1

# Azure Functions ローカルランタイムで起動
func start

# ブラウザで http://localhost:7071 にアクセスして動作確認
```

#### GitHubにプッシュ

```powershell
# 変更をコミット
git add .
git commit -m "Initial commit: RAG chat application"

# mainブランチにプッシュ
git push origin main
```

### 5. GitHub Actionsの実行

#### 自動実行

`main`ブランチにプッシュすると、GitHub Actionsが自動的に実行されます。

#### 手動実行

GitHubリポジトリページから手動でワークフローを実行することもできます。

1. GitHubリポジトリページを開く
2. `Actions` タブをクリック
3. `Deploy to Azure Functions` ワークフローを選択
4. `Run workflow` をクリック
5. `Run workflow` ボタンをクリック

### 6. デプロイの監視

#### GitHub Actionsログ

1. `Actions` タブでワークフローの実行を確認
2. 各ジョブの詳細ログを確認:
   - `setup-runner`: Self-hosted Runnerの起動
   - `build-and-deploy`: アプリケーションのビルドとデプロイ
   - `cleanup`: Runnerのクリーンアップ

#### Azure Functionsログ

```powershell
# リアルタイムログストリーミング
az functionapp log tail `
    --resource-group $RESOURCE_GROUP `
    --name $FUNCTIONAPP_NAME

# Application Insightsでログ確認
az monitor app-insights query `
    --app $FUNCTIONAPP_NAME `
    --analytics-query "traces | where timestamp > ago(1h) | order by timestamp desc" `
    --offset 1h
```

### 7. デプロイの確認

#### アプリケーションへのアクセス

```powershell
# Azure FunctionsのURLを取得
$appUrl = az functionapp show `
    --resource-group $RESOURCE_GROUP `
    --name $FUNCTIONAPP_NAME `
    --query defaultHostName -o tsv

Write-Host "Application URL: https://$appUrl"

# ブラウザで開く
Start-Process "https://$appUrl"
```

#### ヘルスチェック

```powershell
# ヘルスエンドポイントにアクセス
$healthUrl = "https://$appUrl/health"
$response = Invoke-RestMethod -Uri $healthUrl

if ($response.status -eq "healthy") {
    Write-Host "Application is healthy!" -ForegroundColor Green
} else {
    Write-Host "Application health check failed!" -ForegroundColor Red
}
```

#### チャット機能のテスト

ブラウザでアプリケーションを開き、以下をテストします:

1. チャットUIが表示されること
2. メッセージを送信できること
3. AIからの応答が返ってくること
4. 参照ソースが表示されること

### 8. CI/CDパイプラインの理解

#### ワークフローの3つのジョブ

**Job 1: setup-runner**
- Azure Container InstanceでSelf-hosted Runnerを起動
- vNet内のSubnetに配置
- GitHub Actionsに登録

**Job 2: build-and-deploy**
- Self-hosted Runner上で実行
- Private Endpoint経由でKey Vaultにアクセス
- Azure Functionsにデプロイ

**Job 3: cleanup**
- Runnerを削除
- Container Instanceを削除
- コスト最適化

#### セキュリティのポイント

✅ **閉域デプロイ**
- Self-hosted RunnerはvNet内で実行
- Private Endpoint経由でAzureリソースにアクセス
- インターネット経由のアクセスなし

✅ **シークレット管理**
- すべてのシークレットはKey Vaultで管理
- GitHub Secretsは最小限
- ログにシークレットを出力しない

## デプロイの更新

### アプリケーションコードの更新

```powershell
# コードを編集
code function_app.py

# 変更をコミット
git add function_app.py
git commit -m "Update: チャット機能の改善"

# プッシュして自動デプロイ
git push origin main
```

### 環境変数の更新

```powershell
# Azure Functions環境変数を更新
az functionapp config appsettings set `
    --resource-group $RESOURCE_GROUP `
    --name $FUNCTIONAPP_NAME `
    --settings `
        AZURE_OPENAI_DEPLOYMENT=gpt-4-turbo

# 関数アプリを再起動
az functionapp restart `
    --resource-group $RESOURCE_GROUP `
    --name $FUNCTIONAPP_NAME
```

## 確認事項

以下をすべて確認してください:

- ✅ Federated Identity (OIDC)が正しく設定されている
- ✅ GitHub Secrets (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID)が設定されている
- ✅ Azure Functions環境変数が設定されている
- ✅ ワークフローファイル(deploy-functions.yml)が正しく構成されている
- ✅ function_app.py、host.json、static/index.htmlが存在する
- ✅ コードがGitHubにプッシュされている
- ✅ GitHub Actionsが正常に実行されている
- ✅ Azure Functionsにデプロイされている
- ✅ アプリケーションが正常に動作している
- ✅ RAG機能が動作している

## トラブルシューティング

### ワークフローが失敗する

**症状**: GitHub Actionsワークフローがエラーで終了

**確認事項**:
1. GitHub Secretsが正しく設定されているか (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID)
2. Federated Credentialが正しく設定されているか
3. Key Vaultにシークレットが格納されているか
4. Self-hosted Runnerが起動しているか
5. vNet設定が正しいか

**対処法**:
```powershell
# GitHub Secretsを確認
gh secret list

# Federated Credentialを確認
$appId = "<your-app-id>"
az ad app federated-credential list --id $appId

# Key Vaultのシークレットを確認
az keyvault secret list --vault-name $KEYVAULT_NAME --output table

# Container Instancesの状態を確認
az container list --resource-group $RESOURCE_GROUP --output table
```

### アプリが起動しない

**症状**: デプロイは成功するがアプリにアクセスできない

**確認事項**:
1. Azure Functionsのログを確認
2. 環境変数が正しく設定されているか
3. host.jsonの設定が正しいか
4. function_app.pyにエラーがないか

**対処法**:
```powershell
# ログを確認
az functionapp log tail --resource-group $RESOURCE_GROUP --name $FUNCTIONAPP_NAME

# 関数の一覧を確認
az functionapp function list --resource-group $RESOURCE_GROUP --name $FUNCTIONAPP_NAME

# Application Insightsで詳細確認
az monitor app-insights query `
    --app $FUNCTIONAPP_NAME `
    --analytics-query "exceptions | where timestamp > ago(1h)"
```

### RAGが動作しない

**症状**: チャットは表示されるが応答が返らない

**確認事項**:
1. AI Searchインデックスが存在するか
2. Azure OpenAIへの接続が成功しているか
3. Managed Identityの権限が付与されているか

**対処法**:
```powershell
# ブラウザの開発者ツールでネットワークタブを確認
# /api/chatエンドポイントのエラーを確認

# App Serviceログでエラーメッセージを確認
```

## 次のステップ

アプリケーションデプロイが完了したら、次は **[Step 5: テストと運用](step05-testing.md)** に進みましょう。

アプリケーションの動作確認、パフォーマンステスト、監視設定を行います。
