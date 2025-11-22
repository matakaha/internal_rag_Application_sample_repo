# Step 4: アプリケーションデプロイ

このステップでは、GitHub Actionsを使用してPythonチャットアプリケーションをAzure Functions (AppServicePlan)にデプロイします。

> 📝 **初学者向け: CI/CDとは？**
> 
> **CI/CD**は、コードを自動的にテストしてデプロイする仕組みです。
> 
> **CI (Continuous Integration) = 継続的インテグレーション**:
> - コードをGitHubにプッシュすると自動的にビルド・テスト
> - 問題があればすぐに気づける
> 
> **CD (Continuous Deployment) = 継続的デプロイ**:
> - テストが通ったら自動的にAzureにデプロイ
> - 手作業なしで本番環境に反映
> 
> **GitHub Actionsとは？**:
> - GitHubが提供する無料のCI/CDツール
> - YAMLファイルでワークフロー(作業手順)を定義
> - コードをプッシュするだけで自動実行
> 
> **このプロジェクトのワークフロー**:
> ```
> 1. コードをGitHubにpush
>    ↓
> 2. GitHub Actionsが自動起動
>    ↓
> 3. Self-hosted Runnerを起動 (閉域環境用)
>    ↓
> 4. 依存パッケージをインストール
>    ↓
> 5. Azure Functionsにデプロイ
>    ↓
> 6. Runnerを削除 (コスト削減)
> ```
> 
> **Self-hosted Runnerとは？**:
> - GitHub Actionsを実行するための「作業マシン」
> - 通常はGitHubが用意したマシンを使うが、閉域環境では使えない
> - このプロジェクトでは、Azure Container Instancesで動的に起動
> - vNet内で実行されるため、Private Endpointにアクセス可能

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
    - 詳細は **[付録: GitHub Runner用ACRイメージのセットアップ](appendix-acr-runner-setup.md)** を参照
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

> 💡 **ヒント**: ワークフローには、閉域ネットワーク環境でも動作するように自動診断機能が組み込まれています。詳細は後述の「上級者向け: ワークフロー詳細解説」を参照してください。

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

### デプロイが400/401エラーで失敗する(SCMエンドポイントブロック)

**症状**: デプロイステップで以下のようなエラーが発生:
```
ERROR: An error occurred during deployment. Status Code: 400
Please visit https://app-name.scm.azurewebsites.net
```
または
```
Error: Failed to deploy web package to App Service. Conflict (STATUS CODE: 401)
```

**原因**: 閉域ネットワーク環境で、NSGやファイアウォールがSCMエンドポイント(`*.scm.azurewebsites.net`)へのアクセスをブロックしています。

**対処法**:

1. **ワークフローの診断ログを確認**:
   ```powershell
   # GitHub Actionsログで"Diagnose Network and Authentication"ステップを確認
   # SCM_RESPONSE が "000" または "timeout" の場合、SCMエンドポイントがブロックされています
   ```

2. **ARM API デプロイメソッドが自動選択されているか確認**:
   - ワークフローには自動診断機能が組み込まれています
   - SCMエンドポイントがブロックされている場合、ARM API経由のデプロイに自動切り替わります
   - ログで`deploy_method=arm`が設定されていることを確認してください

3. **手動でARM APIデプロイを確認**:
   ```powershell
   # Functions用リソースIDを取得
   $functionResourceId = az functionapp show `
       --resource-group rg-internal-rag-dev `
       --name func-internal-rag-dev `
       --query id -o tsv
   
   # ARM APIエンドポイントの疎通確認(Self-hosted Runnerから)
   curl -v "https://management.azure.com${functionResourceId}?api-version=2022-03-01"
   ```

4. **NSG設定の確認**:
   ```powershell
   # Container Instances用NSGを確認
   az network nsg show `
       --resource-group rg-internal-rag-dev `
       --name nsg-container-instances-dev
   
   # 443番ポートのアウトバウンドルールを確認
   # management.azure.com (AzureCloud service tag)へのアクセスが許可されているか確認
   ```

**補足**: ARM APIデプロイは`management.azure.com`を使用するため、SCMエンドポイントへのアクセスが不要です。Federated Identityで取得したBearer Tokenで認証します。

### Python依存パッケージインストールエラー(PYTHONNOUSERSITE)

**症状**: Functionsデプロイのビルドステップで以下のエラー:
```
Can not perform a '--user' install. User site-packages are disabled.
```

**原因**: GitHub Runnerイメージに設定された`PYTHONNOUSERSITE=1`環境変数が、pipのユーザーローカルインストールをブロックしています。

**対処法**:

ワークフローで以下の手順が実装されているか確認:

```yaml
- name: Install dependencies
  run: |
    # PYTHONNOUSERSITE環境変数を一時的に解除
    unset PYTHONNOUSERSITE
    unset PIP_NO_USER
    
    # venv環境でインストール
    python -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt

- name: Package Function App
  run: |
    # venvのパッケージを.python_packagesにコピー
    mkdir -p .python_packages/lib/site-packages
    cp -r venv/lib/python*/site-packages/* .python_packages/lib/site-packages/
    zip -r function-app.zip . -x "*.git*" -x "*venv/*"
```

**確認ポイント**:
1. `unset PYTHONNOUSERSITE`が実行されているか
2. venv内でパッケージがインストールされているか
3. `.python_packages/lib/site-packages/`にパッケージがコピーされているか
4. ZIPアーカイブに`.python_packages`が含まれているか

**デバッグコマンド**(Self-hosted Runnerから):
```bash
# venv内のパッケージ確認
source venv/bin/activate
pip list

# .python_packages構造確認
ls -la .python_packages/lib/site-packages/

# ZIPアーカイブ内容確認
unzip -l function-app.zip | grep python_packages
```

## 上級者向け: ワークフロー詳細解説

> ⚠️ **このセクションについて**: 以下の内容は、ワークフローの内部動作を深く理解したい方、またはカスタマイズが必要な方向けです。基本的な使い方だけであれば読み飛ばしても問題ありません。

### ネットワーク診断と適応的デプロイ戦略

#### 概要: なぜ2つのデプロイ方法が必要なのか

通常、Azure Web AppsやFunctionsへのデプロイは「SCMエンドポイント」(`*.scm.azurewebsites.net`)を使用します。しかし、完全閉域ネットワーク環境では、セキュリティポリシーによりこのエンドポイントがブロックされることがあります。

そこで、このワークフローには**環境を自動判別し、適切なデプロイ方法を選択する機能**が組み込まれています。

#### デプロイ方法の比較

| 方式 | エンドポイント | 認証方式 | 利用シーン |
|------|---------------|---------|----------|
| **SCM方式** | `*.scm.azurewebsites.net` | Publishing Credentials | 標準的な環境 |
| **ARM API方式** | `management.azure.com` | Federated Identity (Bearer Token) | 完全閉域環境(SCMブロック時) |

#### 自動診断の仕組み

ワークフローは以下の手順で環境を診断します:

```yaml
- name: Diagnose Network and Authentication
  id: diagnose
  run: |
    # 1. SCMエンドポイントに接続テスト
    SCM_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "$SCM_URL" 2>&1 || echo "000")
    
    # 2. HTTPステータスコードで判定
    if [ "$SCM_RESPONSE" = "401" ] || [ "$SCM_RESPONSE" = "403" ]; then
      # 401/403 = エンドポイント到達可能(認証エラーだが接続はOK)
      echo "deploy_method=scm" >> $GITHUB_OUTPUT
    else
      # 000/timeout = エンドポイント到達不可(ブロックされている)
      echo "deploy_method=arm" >> $GITHUB_OUTPUT
    fi
```

**判定ロジック**:
- **HTTP 401/403**: エンドポイントには到達できている(認証が必要なだけ) → SCM方式を使用
- **HTTP 000/timeout**: エンドポイントに到達できない(NSG/Firewallでブロック) → ARM API方式を使用

#### SCM方式のデプロイ

SCMエンドポイントが利用可能な場合、Publishing Credentialsを使用してZIPデプロイを実行します。

```yaml
- name: Deploy to Azure Functions (SCM method)
  if: steps.diagnose.outputs.deploy_method == 'scm'
  run: |
    # Publishing Credentialsで認証
    curl -X POST -u "$USERNAME:$PASSWORD" \
      --data-binary @function-app.zip \
      "https://$FUNCTIONAPP_NAME.scm.azurewebsites.net/api/zipdeploy"
```

**特徴**:
- ✅ シンプルで高速
- ✅ 従来の標準的な方法
- ❌ SCMエンドポイントへのアクセスが必要

#### ARM API方式のデプロイ

SCMエンドポイントがブロックされている場合、Azure Resource Manager APIを使用してデプロイします。

```yaml
- name: Deploy to Azure Functions (ARM API method)
  if: steps.diagnose.outputs.deploy_method == 'arm'
  run: |
    # 1. Federated Identityでアクセストークン取得
    ACCESS_TOKEN=$(az account get-access-token \
      --resource https://management.azure.com \
      --query accessToken -o tsv)
    
    # 2. ZIPファイルをBase64エンコード
    ZIP_BASE64=$(base64 -w 0 function-app.zip)
    
    # 3. OneDeploy APIにリクエスト
    echo "{\"properties\":{\"type\":\"zip\",\"packageUri\":\"data:application/zip;base64,${ZIP_BASE64}\"}}" > deploy-payload.json
    
    curl -X PUT -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      -d @deploy-payload.json \
      "https://management.azure.com${FUNCTION_RESOURCE_ID}/extensions/onedeploy?api-version=2022-03-01"
```

**特徴**:
- ✅ SCMエンドポイント不要
- ✅ `management.azure.com`は443番ポート(HTTPS)で閉域環境でも利用可能
- ✅ Federated Identityで安全に認証
- ⚠️ ZIPファイルをBase64エンコードするため、やや処理時間がかかる

#### なぜARM APIは閉域環境でも動作するのか

1. **エンドポイントの違い**:
   - SCM: `*.scm.azurewebsites.net` (多くの閉域環境でブロック対象)
   - ARM API: `management.azure.com` (Azureの基盤API、通常は許可されている)

2. **通信経路**:
   - NSGで443番ポート(HTTPS)のアウトバウンドが許可されていれば、ARM APIにアクセス可能
   - Azure管理操作の基盤APIなので、ブロックされることは稀

3. **認証方式**:
   - Federated Identity(OIDC)で取得したBearer Tokenを使用
   - シークレット管理が不要で、セキュアな認証が可能

### Python依存パッケージのインストール詳細

#### PYTHONNOUSERSITE環境変数とは

GitHub Runnerイメージには`PYTHONNOUSERSITE=1`という環境変数が設定されています。

**目的**: ユーザーローカルディレクトリ(`~/.local/lib/python*/site-packages`)へのpipインストールを無効化し、システム全体のパッケージのみを使用します。

**理由**: Azure CLIとその依存パッケージの競合を防ぐためです。ユーザーローカルとシステムで異なるバージョンのパッケージが混在すると、Azure CLIが正常に動作しないことがあります。

#### Functions デプロイ時の課題

通常、`pip install -r requirements.txt`を実行すると、`PYTHONNOUSERSITE=1`の影響で以下のエラーが発生します:

```
Can not perform a '--user' install. User site-packages are disabled.
```

#### 解決策: venvを使った分離

ワークフローでは、以下の手順で依存パッケージをインストールします:

```yaml
- name: Install dependencies
  run: |
    # 1. 環境変数を一時的に解除
    unset PYTHONNOUSERSITE
    unset PIP_NO_USER
    
    # 2. venv環境を作成
    python -m venv venv
    
    # 3. venv環境内でパッケージインストール
    source venv/bin/activate
    python -m pip install --upgrade pip
    pip install -r requirements.txt
```

**ポイント**:
- `unset`で環境変数を一時的に解除(このステップ内のみ有効)
- venv環境内では`PYTHONNOUSERSITE`の影響を受けない
- 次のステップでは元の環境変数が復元される

#### Azure Functions用のパッケージング

Azure Functionsは特定のディレクトリ構造を期待しています:

```yaml
- name: Package Function App
  run: |
    # 1. .python_packagesディレクトリを作成
    mkdir -p .python_packages/lib/site-packages
    
    # 2. venvからパッケージをコピー
    cp -r venv/lib/python*/site-packages/* .python_packages/lib/site-packages/
    
    # 3. ZIPアーカイブ作成(venvは除外)
    zip -r function-app.zip . -x "*.git*" -x "*venv/*" -x "*__pycache__/*" -x "*.pyc"
```

**Azure Functionsの動作**:
- デプロイ後、Functionsランタイムは`.python_packages/lib/site-packages/`を自動的にPython pathに追加
- アプリケーションコードから`import`で直接利用可能
- Azure側でのビルド不要(閉域環境で必須)

#### ディレクトリ構造の例

```
function-app.zip
├── function_app.py
├── host.json
├── requirements.txt
└── .python_packages/
    └── lib/
        └── site-packages/
            ├── azure/
            ├── openai/
            ├── flask/
            └── ...(その他のパッケージ)
```

### まとめ: なぜこれらの工夫が必要か

完全閉域ネットワーク環境では、以下の制約があります:

1. **外部エンドポイントへのアクセス制限**
   - SCMエンドポイント、npmレジストリ、PyPIなどがブロックされる
   - → ARM API、事前ビルド、venv分離で対応

2. **セキュリティポリシー**
   - インターネット経由のパッケージダウンロード禁止
   - → Self-hosted Runner上で全て事前準備

3. **認証とアクセス制御**
   - Private Endpointで保護されたリソース
   - → Federated Identity、Managed Identityで安全に認証

これらの工夫により、**完全閉域環境でも安全かつ確実にCI/CDパイプラインを実現**しています。

## 次のステップ

アプリケーションデプロイが完了したら、次は **[Step 5: テストと運用](step05-testing.md)** に進みましょう。

アプリケーションの動作確認、パフォーマンステスト、監視設定を行います。
