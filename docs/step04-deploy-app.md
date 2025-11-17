# Step 4: アプリケーションデプロイ

このステップでは、GitHub Actionsを使用してPythonチャットアプリケーションをAzure App Serviceにデプロイします。

## 📚 学習目標

このステップを完了すると、以下ができるようになります:

- GitHub Actionsワークフローの理解
- Self-hosted Runnerを使用した閉域デプロイ
- App Service設定の構成
- CI/CDパイプラインの実行
- デプロイの確認とトラブルシューティング

## 前提条件

- Step 1, 2, 3が完了していること
- [internal_rag_Application_deployment_step_by_step](https://github.com/matakaha/internal_rag_Application_deployment_step_by_step)の[Step 03 (GitHub Actions)](https://github.com/matakaha/internal_rag_Application_deployment_step_by_step/tree/main/bicep/step03-github-actions)が完了していること
- GitHub Secretsが設定済みであること
- Key Vaultに必要なシークレットが格納されていること

## デプロイ手順

### 1. アプリケーション設定の確認

#### App Service設定の確認

```powershell
$RESOURCE_GROUP = "rg-internal-rag-dev"
$WEBAPP_NAME = "<your-webapp-name>"

# 現在の設定を確認
az webapp config appsettings list `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --output table
```

#### 必要な環境変数

| 変数名 | 説明 | 設定方法 |
|-------|------|---------|
| `AZURE_OPENAI_ENDPOINT` | OpenAIエンドポイント | Step 1で設定済み |
| `AZURE_OPENAI_DEPLOYMENT` | デプロイメント名 | Step 1で設定済み |
| `AZURE_SEARCH_ENDPOINT` | AI Searchエンドポイント | Step 1で設定済み |
| `AZURE_SEARCH_INDEX` | インデックス名 | Step 3で作成 |
| `SCM_DO_BUILD_DURING_DEPLOYMENT` | ビルド設定 | `true` |
| `WEBSITE_HTTPLOGGING_RETENTION_DAYS`(下記追加設定の結果として設定されますので、のちほど確認) | ログ保持日数 | `7` |

#### 追加設定

```powershell
# ビルド設定を有効化
az webapp config appsettings set `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --settings `
        SCM_DO_BUILD_DURING_DEPLOYMENT=true `
        WEBSITE_HTTPLOGGING_RETENTION_DAYS=7

# スタートアップコマンドを設定
az webapp config set `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --startup-file "gunicorn --bind=0.0.0.0:8000 --workers=4 --timeout=600 src.app:app"

# Pythonバージョンを設定(PowerShellの解析を停止するため --% を使用)
az webapp config set --resource-group $RESOURCE_GROUP --name $WEBAPP_NAME --% --linux-fx-version "PYTHON|3.11"
```

### 2. GitHub Secretsの確認

以下のSecretsが設定されているか確認します。

```powershell
# GitHub CLIで確認
gh secret list

# 必要なSecrets:
# - AZURE_CREDENTIALS
# - KEY_VAULT_NAME
# - GH_PAT
# - AZURE_OPENAI_ENDPOINT
# - AZURE_OPENAI_DEPLOYMENT
# - AZURE_SEARCH_ENDPOINT
# - AZURE_SEARCH_INDEX
```

不足がある場合は、Step 1を参照して設定してください。

### 3. ワークフローファイルの確認

`.github/workflows/deploy.yml` の内容を確認します。

主要な設定:

```yaml
env:
  RESOURCE_GROUP: 'rg-internal-rag-dev'
  WEBAPP_NAME: 'app-internal-rag-dev'  # ←あなたのApp Service名に変更
  CONTAINER_GROUP_NAME: 'aci-runner-${{ github.run_id }}'
  VNET_NAME: 'vnet-internal-rag-dev'
  SUBNET_NAME: 'snet-container-instances'
  LOCATION: 'japaneast'
```

必要に応じて、環境変数を自分の環境に合わせて編集します。

### 4. コードの準備とプッシュ

#### ローカルでテスト(オプション)

```powershell
# 仮想環境を有効化
.\venv\Scripts\Activate.ps1

# ローカルで起動テスト
python src/app.py

# ブラウザで http://localhost:8000 にアクセスして動作確認
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
3. `Deploy to Azure Web Apps` ワークフローを選択
4. `Run workflow` をクリック
5. `Run workflow` ボタンをクリック

### 6. デプロイの監視

#### GitHub Actionsログ

1. `Actions` タブでワークフローの実行を確認
2. 各ジョブの詳細ログを確認:
   - `setup-runner`: Self-hosted Runnerの起動
   - `build-and-deploy`: アプリケーションのビルドとデプロイ
   - `cleanup`: Runnerのクリーンアップ

#### App Serviceログ

```powershell
# リアルタイムログストリーミング
az webapp log tail `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME

# ログファイルをダウンロード
az webapp log download `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --log-file app-logs.zip

# ZIPファイルを解凍して確認
Expand-Archive -Path app-logs.zip -DestinationPath logs/
Get-Content logs/LogFiles/kudu/trace/*.txt
```

### 7. デプロイの確認

#### アプリケーションへのアクセス

```powershell
# App ServiceのURLを取得
$appUrl = az webapp show `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
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
- App Serviceにデプロイ

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
code src/app.py

# 変更をコミット
git add src/app.py
git commit -m "Update: チャット機能の改善"

# プッシュして自動デプロイ
git push origin main
```

### 環境変数の更新

```powershell
# App Service環境変数を更新
az webapp config appsettings set `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --settings `
        AZURE_OPENAI_DEPLOYMENT=gpt-4-turbo

# アプリを再起動
az webapp restart `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME
```

## 確認事項

以下をすべて確認してください:

- ✅ GitHub Secretsが正しく設定されている
- ✅ App Service環境変数が設定されている
- ✅ ワークフローファイルが正しく構成されている
- ✅ コードがGitHubにプッシュされている
- ✅ GitHub Actionsが正常に実行されている
- ✅ アプリケーションがデプロイされている
- ✅ アプリケーションが正常に動作している
- ✅ RAG機能が動作している

## トラブルシューティング

### ワークフローが失敗する

**症状**: GitHub Actionsワークフローがエラーで終了

**確認事項**:
1. GitHub Secretsが正しく設定されているか
2. Key Vaultにシークレットが格納されているか
3. Self-hosted Runnerが起動しているか
4. vNet設定が正しいか

**対処法**:
```powershell
# Key Vaultのシークレットを確認
az keyvault secret list --vault-name $KEYVAULT_NAME --output table

# Container Instancesの状態を確認
az container list --resource-group $RESOURCE_GROUP --output table
```

### アプリが起動しない

**症状**: デプロイは成功するがアプリにアクセスできない

**確認事項**:
1. App Serviceのログを確認
2. 環境変数が正しく設定されているか
3. Pythonバージョンが正しいか
4. スタートアップコマンドが正しいか

**対処法**:
```powershell
# ログを確認
az webapp log tail --resource-group $RESOURCE_GROUP --name $WEBAPP_NAME

# SSH接続して直接確認
az webapp ssh --resource-group $RESOURCE_GROUP --name $WEBAPP_NAME
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
