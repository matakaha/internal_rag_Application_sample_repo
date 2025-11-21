# Runner イメージの再ビルド手順

## 概要
Docker サポートを追加した GitHub Runner イメージを ACR にビルド・プッシュします。

## 前提条件
- ACR: `acrinternalragdev` が存在すること
- Azure CLI でログイン済みであること
- カレントディレクトリ: `internal_rag_Application_sample_repo`

## 手順

### 1. .dockerignore ファイルを一時的に置き換え

```powershell
# Web App用の .dockerignore をバックアップ
Copy-Item .dockerignore .dockerignore.webapp

# Runner用の .dockerignore に置き換え
Copy-Item .dockerignore.runner .dockerignore
```

### 2. ACR のパブリックアクセスを一時的に有効化

```powershell
# パブリックアクセスとネットワークルールを有効化
az acr update --name acrinternalragdev --public-network-enabled true --default-action Allow

# 設定が反映されるまで待機
Start-Sleep -Seconds 30
```

### 3. Runner イメージをビルド

```powershell
# ACR Tasks でビルド
az acr build `
  --registry acrinternalragdev `
  --image github-runner:latest `
  --file Dockerfile.runner `
  .
```

**所要時間**: 約 4-5 分

### 4. ACR のパブリックアクセスを無効化

```powershell
# パブリックアクセスとネットワークルールを無効化（セキュリティ強化）
az acr update --name acrinternalragdev --public-network-enabled false --default-action Deny
```

### 5. .dockerignore ファイルを元に戻す

```powershell
# Web App用の .dockerignore に戻す
Copy-Item .dockerignore.webapp .dockerignore

# バックアップファイルを削除
Remove-Item .dockerignore.webapp
```

### 6. イメージの確認

```powershell
# パブリックアクセスを一時的に有効化（確認のため）
az acr update --name acrinternalragdev --public-network-enabled true

# イメージのタグを確認
az acr repository show-tags `
  --name acrinternalragdev `
  --repository github-runner `
  --output table

# パブリックアクセスを無効化
az acr update --name acrinternalragdev --public-network-enabled false
```

期待される出力:
```
Result
-------
latest
```

## 次のステップ

Runner イメージの更新が完了したら、Web App のコンテナデプロイをコミット:

```powershell
git add Dockerfile .dockerignore .dockerignore.runner Dockerfile.runner start.sh .github/workflows/deploy.yml
git commit -m "Add Docker support to GitHub Runner and containerize Web App"
git push origin main
```

## トラブルシューティング

### エラー: COPY failed: file not found in build context

**原因**: `.dockerignore` で必要なファイルが除外されている

**対処法**: `.dockerignore.runner` が正しく適用されているか確認

### エラー: denied: client with IP is not allowed access

**原因**: ACR のパブリックアクセスが無効

**対処法**: 手順2を再実行し、待機時間を延長（60秒程度）

### ビルドが遅い

**原因**: ソースコードのサイズが大きい

**対処法**: `.dockerignore.runner` で不要なファイルを追加除外
