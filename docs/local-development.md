# Azure Functions ローカル開発ガイド

このガイドでは、Azure Functionsアプリケーションをローカル環境で開発・テストする手順を説明します。

> 📝 **Note**: 開発環境ではAppServicePlan B1、本番環境ではPremium Plan (EP1以上)を推奨します。

## 前提条件

### 必要なツール

1. **Python 3.11以上**
   ```powershell
   python --version  # 3.11以上であることを確認
   ```

2. **Azure Functions Core Tools v4**
   ```powershell
   # インストール確認
   func --version  # 4.x.x であることを確認
   
   # 未インストールの場合
   winget install Microsoft.Azure.FunctionsCoreTools
   # または
   npm install -g azure-functions-core-tools@4
   ```

3. **Azure CLI**
   ```powershell
   az --version
   az login
   ```

## ローカル環境のセットアップ

### 1. リポジトリのクローン

```powershell
git clone https://github.com/matakaha/internal_rag_Application_sample_repo.git
cd internal_rag_Application_sample_repo
```

### 2. Python仮想環境の作成

```powershell
# 仮想環境を作成
python -m venv .venv

# 仮想環境をアクティベート
.\.venv\Scripts\Activate.ps1

# 依存関係をインストール
pip install -r requirements.txt
```

### 3. ローカル設定ファイルの編集

`local.settings.json` を編集してAzureリソース情報を設定します:

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AzureWebJobsFeatureFlags": "EnableWorkerIndexing",
    
    "AZURE_OPENAI_ENDPOINT": "https://your-openai-resource.openai.azure.com/",
    "AZURE_OPENAI_DEPLOYMENT": "gpt-4",
    "AZURE_SEARCH_ENDPOINT": "https://your-search-resource.search.windows.net",
    "AZURE_SEARCH_INDEX": "redlist-index",
    "AZURE_SEARCH_KEY": ""
  }
}
```

**重要**: 
- 本番環境ではManaged Identityを使用しますが、ローカル開発では`AZURE_SEARCH_KEY`を設定するか、`az login`で認証します
- OpenAIは`DefaultAzureCredential`で認証されるため、`az login`が必要です

### 4. Azure認証

```powershell
# Azureにログイン
az login

# 使用するサブスクリプションを設定
az account set --subscription <subscription-id>
```

## ローカル実行

### Functions Runtimeの起動

```powershell
# Azure Functions ローカルランタイムを起動
func start

# または詳細ログ付き
func start --verbose
```

### アクセス

ブラウザで以下のURLにアクセス:

- **フロントエンド**: `http://localhost:7071/`
- **チャットAPI**: `http://localhost:7071/api/chat` (POST)
- **ヘルスチェック**: `http://localhost:7071/health`

### ログ確認

コンソールに表示されるログで動作を確認できます:

```
Azure Functions Core Tools
Core Tools Version:       4.x.x
Function Runtime Version: 4.x.x

Functions:

        index: [GET] http://localhost:7071/

        chat: [POST] http://localhost:7071/api/chat

        health: [GET] http://localhost:7071/health

For detailed output, run func with --verbose flag.
[2025-11-17T10:00:00.000Z] Worker process started and initialized.
```

## デバッグ

### VS Codeでのデバッグ

1. VS Codeを開く
   ```powershell
   code .
   ```

2. `.vscode/launch.json` を作成:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Attach to Python Functions",
      "type": "python",
      "request": "attach",
      "port": 9091,
      "preLaunchTask": "func: host start"
    }
  ]
}
```

3. `.vscode/tasks.json` を作成:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "func: host start",
      "type": "shell",
      "command": "func start",
      "isBackground": true,
      "problemMatcher": "$func-python-watch"
    }
  ]
}
```

4. F5キーを押してデバッグ開始

### ブレークポイント

`function_app.py` の任意の行にブレークポイントを設定できます:

```python
@app.route(route="api/chat", methods=["POST"])
def chat(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Chat API invoked')  # ← ここにブレークポイント
    
    # ... 以下省略
```

## テスト

### curl/PowerShellでのテスト

```powershell
# ヘルスチェック
Invoke-RestMethod -Uri "http://localhost:7071/health"

# チャットAPIテスト
$body = @{
    message = "ニホンウナギについて教えてください"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:7071/api/chat" `
    -Method POST `
    -ContentType "application/json" `
    -Body $body
```

### ブラウザでのテスト

1. `http://localhost:7071/` にアクセス
2. チャット欄にメッセージを入力
3. レスポンスと参照ソースを確認

## トラブルシューティング

### エラー: "Azure Functions Core Tools not found"

**解決策**:
```powershell
winget install Microsoft.Azure.FunctionsCoreTools
# または
npm install -g azure-functions-core-tools@4
```

### エラー: "Unable to load azure.functions module"

**解決策**:
```powershell
# 仮想環境が有効化されているか確認
.\.venv\Scripts\Activate.ps1

# azure-functionsを再インストール
pip install --upgrade azure-functions
```

### エラー: "Authentication failed"

**解決策**:
```powershell
# Azure CLI で再ログイン
az login
az account show

# または local.settings.json にAPIキーを設定
```

### エラー: "Cannot find module 'index.html'"

**解決策**:
```powershell
# static/index.html が存在するか確認
ls static/index.html

# 存在しない場合は、Functionsの静的ファイルとして使用可能
# (フロントエンドはNode.js/Expressで別途起動)
```

### ポート競合エラー

**解決策**:
```powershell
# カスタムポートで起動
func start --port 7072
```

## ホットリロード

ファイルを編集すると自動的にリロードされます:

```
[2025-11-17T10:05:00.000Z] File changed: function_app.py
[2025-11-17T10:05:01.000Z] Reloading function metadata...
```

## 次のステップ

ローカルでの動作確認が完了したら:

1. **Azureへデプロイ**: [Step 4: デプロイ](../docs/step04-deploy-app.md)
2. **CI/CD設定**: GitHub Actions ワークフローの実行
3. **監視設定**: Application Insights の確認

## 参考リンク

- [Azure Functions Python開発者ガイド](https://learn.microsoft.com/ja-jp/azure/azure-functions/functions-reference-python)
- [Azure Functions Core Tools](https://learn.microsoft.com/ja-jp/azure/azure-functions/functions-run-local)
- [Azure Functions v2プログラミングモデル](https://learn.microsoft.com/ja-jp/azure/azure-functions/functions-reference-python?tabs=asgi%2Capplication-level)
