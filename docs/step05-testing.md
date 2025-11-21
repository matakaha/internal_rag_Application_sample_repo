# Step 5: テストと運用

このステップでは、デプロイしたRAGアプリケーションのテスト、パフォーマンス確認、運用方法について学びます。

## 📚 学習目標

このステップを完了すると、以下ができるようになります:

- アプリケーションの機能テスト
- RAG機能の品質確認
- パフォーマンス監視
- ログ分析
- トラブルシューティング
- 継続的な改善

## 前提条件

- Step 1〜4が完了していること
- アプリケーションがデプロイ済みであること
- ブラウザでアプリケーションにアクセスできること

## テスト手順

### 1. 基本機能テスト

#### UI表示確認

```powershell
# Web Apps (Node.jsフロントエンド)のURLを取得
$RESOURCE_GROUP = "rg-internal-rag-dev"
$WEBAPP_NAME = "app-internal-rag-dev"  # あなたのWeb App名に変更

$webappUrl = az webapp show `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --query defaultHostName -o tsv

Write-Host "Web Application URL: https://$webappUrl"
Write-Host "ブラウザで開きます..."
Start-Process "https://$webappUrl"

# または環境変数から取得する場合
# .envファイルから値を読み込む
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^#][^=]+)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        Set-Variable -Name $name -Value $value -Scope Script
    }
}
Start-Process "https://$($env:WEBAPP_NAME).azurewebsites.net"
```

> 📝 **Note**: Web AppはExpress.jsで`src/public/index.html`を配信しています。ルーURL(`https://app-name.azurewebsites.net/`)でチャットUIが表示されます。

**デフォルト画面が表示される場合の確認事項**:

```powershell
# 1. Web Appの状態を確認
az webapp show `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --query "{name:name, state:state, hostNames:hostNames}" `
    -o json

# 2. アプリケーションログを確認
az webapp log tail `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME

# 3. Node.jsプロセスが起動しているか確認
# ログに"Listening on port 8000"または"Server started"などのメッセージがあるか確認

# 4. 環境変数が設定されているか確認
az webapp config appsettings list `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --query "[?name=='AZURE_OPENAI_ENDPOINT' || name=='AZURE_SEARCH_ENDPOINT'].{name:name, value:value}" `
    -o table
```

**問題がある場合の対処法**:

```powershell
# Web Appを再起動
az webapp restart `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME

# 再起動後にログを確認
az webapp log tail `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME
```

確認項目:
- ✅ ページが正常に表示される
- ✅ チャットUIが表示される
- ✅ 入力フォームが表示される
- ✅ デザインが正しく適用されている

#### チャット機能テスト

以下のメッセージを送信して動作確認:

1. **基本的な質問**
   ```
   イリオモテヤマネコは絶滅危惧種ですか?
   ```
   - 応答が返ってくること
   - 参照ソースが表示されること

2. **具体的な質問**
   ```
   ライチョウの生息地はどこですか?
   ```
   - 関連性の高い回答が返ること
   - 複数の参照ソースが表示されること

3. **データにない質問**
   ```
   明日の天気は?
   ```
   - 「情報がない」旨の回答が返ること

### 2. API機能テスト

PowerShellでAPIを直接テストします。

```powershell
# ヘルスチェック
$healthResponse = Invoke-RestMethod -Uri "https://$webappUrl/health"
Write-Host "Health Status: $($healthResponse.status)"

# チャットAPIテスト
$chatEndpoint = "https://$webappUrl/api/chat"
$headers = @{
    "Content-Type" = "application/json"
}

$body = @{
    message = "イリオモテヤマネコについて教えてください"
} | ConvertTo-Json

try {
    Write-Host "チャットAPIテスト中..." -ForegroundColor Yellow
    $response = Invoke-RestMethod -Uri $chatEndpoint -Method Post -Headers $headers -Body $body -TimeoutSec 60
    
    Write-Host "`n=== Chat API Response ===" -ForegroundColor Cyan
    Write-Host "Response: $($response.response)"
    Write-Host "`nSources:" -ForegroundColor Yellow
    $response.sources | ForEach-Object {
        Write-Host "  - $($_.title): $($_.url)"
    }
    Write-Host "`n✅ APIテスト成功" -ForegroundColor Green
} catch {
    Write-Error "API Test Failed: $_"
    Write-Host "エラー詳細: $($_.Exception.Message)" -ForegroundColor Red
    
    # デバッグ情報を取得
    Write-Host "`nデバッグ: Web Appログを確認します..." -ForegroundColor Yellow
    az webapp log tail --resource-group $RESOURCE_GROUP --name $WEBAPP_NAME --filter Error
}
```

> 📝 **Note**: チャットAPIはAzure OpenAIとAI Searchにアクセスするため、初回実行時は認証に時間がかかる場合があります(30秒〜60秒程度)。

### 3. RAG品質テスト

RAGシステムの品質を評価します。

#### テストケース作成

`tests/test-cases.json`:

```json
[
  {
    "id": 1,
    "question": "イリオモテヤマネコは絶滅危惧種ですか?",
    "expected_keywords": ["絶滅危惧", "CR", "ネコ科"],
    "should_have_sources": true
  },
  {
    "id": 2,
    "question": "ライチョウの生息地はどこですか?",
    "expected_keywords": ["高山", "アルプス", "生息"],
    "should_have_sources": true
  },
  {
    "id": 3,
    "question": "今日の気温は?",
    "expected_keywords": ["情報", "ない", "わかりません"],
    "should_have_sources": false
  }
]
```

#### テストスクリプト

`tests/test-rag-quality.ps1`:

```powershell
# RAG品質テストスクリプト

param(
    [Parameter(Mandatory=$true)]
    [string]$WebAppUrl
)

$testCases = Get-Content "tests/test-cases.json" | ConvertFrom-Json
$chatEndpoint = "https://$WebAppUrl/api/chat"
$headers = @{"Content-Type" = "application/json"}

$results = @()

foreach ($test in $testCases) {
    Write-Host "`n=== Test Case $($test.id) ===" -ForegroundColor Cyan
    Write-Host "Question: $($test.question)"
    
    $body = @{message = $test.question} | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri $chatEndpoint -Method Post -Headers $headers -Body $body -TimeoutSec 60
        
        # キーワードチェック
        $keywordsFound = 0
        foreach ($keyword in $test.expected_keywords) {
            if ($response.response -match $keyword) {
                $keywordsFound++
            }
        }
        
        # ソースチェック
        $hasSourcesCorrect = ($response.sources.Count -gt 0) -eq $test.should_have_sources
        
        # 結果
        $passed = ($keywordsFound -gt 0) -and $hasSourcesCorrect
        
        $results += @{
            id = $test.id
            question = $test.question
            passed = $passed
            keywords_found = $keywordsFound
            sources_count = $response.sources.Count
        }
        
        if ($passed) {
            Write-Host "✅ PASSED" -ForegroundColor Green
        } else {
            Write-Host "❌ FAILED" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "❌ ERROR: $_" -ForegroundColor Red
        $results += @{
            id = $test.id
            question = $test.question
            passed = $false
            error = $_.Exception.Message
        }
    }
}

# サマリー
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
$totalTests = $results.Count
$passedTests = ($results | Where-Object { $_.passed }).Count
$passRate = [math]::Round(($passedTests / $totalTests) * 100, 2)

Write-Host "Total Tests: $totalTests"
Write-Host "Passed: $passedTests" -ForegroundColor Green
Write-Host "Failed: $($totalTests - $passedTests)" -ForegroundColor Red
Write-Host "Pass Rate: $passRate%"
```

実行:

```powershell
# Web AppのURLを取得
$webappUrl = az webapp show `
    --resource-group rg-internal-rag-dev `
    --name app-internal-rag-dev `
    --query defaultHostName -o tsv

# テスト実行
.\tests\test-rag-quality.ps1 -WebAppUrl $webappUrl
```

### 4. パフォーマンステスト

#### レスポンスタイム測定

```powershell
# レスポンスタイム測定スクリプト
$chatEndpoint = "https://$webappUrl/api/chat"
$headers = @{"Content-Type" = "application/json"}
$body = @{message = "イリオモテヤマネコについて教えてください"} | ConvertTo-Json

$responseTimes = @()

Write-Host "パフォーマンステスト開始 (10回実行)..." -ForegroundColor Cyan

for ($i = 1; $i -le 10; $i++) {
    Write-Host "Request $i..." -NoNewline
    
    $startTime = Get-Date
    try {
        $response = Invoke-RestMethod -Uri $chatEndpoint -Method Post -Headers $headers -Body $body -TimeoutSec 60
        $endTime = Get-Date
        
        $responseTime = ($endTime - $startTime).TotalMilliseconds
        $responseTimes += $responseTime
        
        Write-Host " $([math]::Round($responseTime, 2))ms" -ForegroundColor Yellow
    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)"
    }
    
    # 連続リクエストを避けるため少し待機
    Start-Sleep -Seconds 2
}

# 統計
if ($responseTimes.Count -gt 0) {
    Write-Host "`n=== Performance Statistics ===" -ForegroundColor Cyan
    Write-Host "Average: $([math]::Round(($responseTimes | Measure-Object -Average).Average, 2))ms"
    Write-Host "Min: $([math]::Round(($responseTimes | Measure-Object -Minimum).Minimum, 2))ms"
    Write-Host "Max: $([math]::Round(($responseTimes | Measure-Object -Maximum).Maximum, 2))ms"
    
    # 分析
    $avgTime = ($responseTimes | Measure-Object -Average).Average
    if ($avgTime -lt 3000) {
        Write-Host "✅ パフォーマンス良好 (3秒未満)" -ForegroundColor Green
    } elseif ($avgTime -lt 10000) {
        Write-Host "⚠️ パフォーマンス注意 (3〜10秒)" -ForegroundColor Yellow
    } else {
        Write-Host "❌ パフォーマンス改善が必要 (10秒以上)" -ForegroundColor Red
    }
} else {
    Write-Host "❌ 全てのリクエストが失敗しました" -ForegroundColor Red
}
```

#### 負荷テスト(オプション)

Azure Load Testingを使用した本格的な負荷テスト。

```powershell
# Azure Load Testingリソースが必要
# 詳細は公式ドキュメント参照
# https://learn.microsoft.com/ja-jp/azure/load-testing/
```

### 5. ログ分析

#### Application Insightsログ

```powershell
# Application Insightsリソースが構成されている場合

# クエリ実行
az monitor app-insights query `
    --app "<app-insights-name>" `
    --analytics-query "requests | where timestamp > ago(1h) | summarize count() by resultCode" `
    --output table
```

#### Azure Functionsログ

```powershell
# ログストリーミング
az functionapp log tail `
    --resource-group $RESOURCE_GROUP `
    --name $FUNCTIONAPP_NAME

# Application Insightsでログ確認
az monitor app-insights query `
    --app $FUNCTIONAPP_NAME `
    --analytics-query "traces | where timestamp > ago(1h) | order by timestamp desc" `
    --offset 1h
```

# 解凍
Expand-Archive -Path app-logs.zip -DestinationPath logs/ -Force

# エラーログを検索
Get-ChildItem -Path logs/ -Recurse -Filter *.txt | ForEach-Object {
    $content = Get-Content $_.FullName
    if ($content -match "ERROR|Exception|Failed") {
        Write-Host "`n=== Errors in $($_.Name) ===" -ForegroundColor Red
        $content | Select-String -Pattern "ERROR|Exception|Failed" | ForEach-Object {
            Write-Host $_.Line
        }
    }
}
```

### 6. 監視設定

#### Azure Monitorアラート設定

```powershell
# Azure Functionsのメトリックスでアラートを作成

# 実行時間が長い場合のアラート
az monitor metrics alert create `
    --name "long-execution-alert" `
    --resource-group $RESOURCE_GROUP `
    --scopes "/subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTIONAPP_NAME" `
    --condition "avg FunctionExecutionUnits > 1000" `
    --window-size 5m `
    --evaluation-frequency 1m `
    --action ""

# CPU使用率が80%を超えたらアラート
az monitor metrics alert create `
    --name "high-cpu-alert" `
    --resource-group $RESOURCE_GROUP `
    --scopes "/subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$WEBAPP_NAME" `
    --condition "avg Percentage CPU > 80" `
    --window-size 5m `
    --evaluation-frequency 1m `
    --action ""

# HTTPエラー率が高い場合のアラート
az monitor metrics alert create `
    --name "http-error-alert" `
    --resource-group $RESOURCE_GROUP `
    --scopes "/subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$WEBAPP_NAME" `
    --condition "avg Http5xx > 10" `
    --window-size 5m `
    --evaluation-frequency 1m `
    --action ""
```

#### ログクエリの保存

よく使うログクエリを保存しておきます。

**エラーログ抽出**:
```kusto
traces
| where timestamp > ago(1h)
| where severityLevel >= 3  // Error以上
| project timestamp, message, severityLevel
| order by timestamp desc
```

**レスポンスタイム分析**:
```kusto
requests
| where timestamp > ago(1h)
| summarize 
    avg(duration), 
    percentile(duration, 50), 
    percentile(duration, 95), 
    percentile(duration, 99) 
    by bin(timestamp, 5m)
| render timechart
```

## 運用ガイド

### 日常運用

#### 毎日のチェック項目

```powershell
# ヘルスチェック
$health = Invoke-RestMethod -Uri "https://$appUrl/health"
if ($health.status -ne "healthy") {
    Write-Warning "Application is not healthy!"
}

# エラーログ確認
az webapp log tail --resource-group $RESOURCE_GROUP --name $WEBAPP_NAME --filter Error

# メトリクス確認
az monitor metrics list `
    --resource "/subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$WEBAPP_NAME" `
    --metric "Http5xx" `
    --start-time (Get-Date).AddHours(-24) `
    --interval PT1H `
    --output table
```

### データの更新

レッドリストのデータが更新された場合の手順:

1. 新しいCSVをダウンロード
2. データを前処理
3. Blob Storageにアップロード
4. インデクサーを手動実行

```powershell
# インデクサーを実行
$SEARCH_SERVICE = "<your-search-service>"
$SEARCH_ADMIN_KEY = "<admin-key>"
$SEARCH_ENDPOINT = "https://$SEARCH_SERVICE.search.windows.net"

$uri = "$SEARCH_ENDPOINT/indexers/blob-indexer/run?api-version=2023-11-01"
$headers = @{"api-key" = $SEARCH_ADMIN_KEY}

Invoke-RestMethod -Uri $uri -Method Post -Headers $headers
Write-Host "Indexer started. Please check status after a few minutes."
```

### バックアップ

```powershell
# App Service設定のバックアップ
az webapp config appsettings list `
    --resource-group $RESOURCE_GROUP `
    --name $WEBAPP_NAME `
    --output json > backup/app-settings-$(Get-Date -Format 'yyyyMMdd').json

# インデックススキーマのバックアップ
$indexUri = "$SEARCH_ENDPOINT/indexes/redlist-index?api-version=2023-11-01"
$indexSchema = Invoke-RestMethod -Uri $indexUri -Headers @{"api-key" = $SEARCH_ADMIN_KEY}
$indexSchema | ConvertTo-Json -Depth 10 > backup/index-schema-$(Get-Date -Format 'yyyyMMdd').json
```

## トラブルシューティング

### 一般的な問題と解決策

#### 問題1: アプリが応答しない

**症状**: ブラウザでタイムアウトする

**診断**:
```powershell
# App Serviceの状態確認
az webapp show --resource-group $RESOURCE_GROUP --name $WEBAPP_NAME --query state

# プロセスが動作しているか確認
az webapp ssh --resource-group $RESOURCE_GROUP --name $WEBAPP_NAME
# SSH内で: ps aux | grep gunicorn
```

**対処法**:
```powershell
# App Serviceを再起動
az webapp restart --resource-group $RESOURCE_GROUP --name $WEBAPP_NAME
```

#### 問題2: RAG応答が不正確

**症状**: 質問に対する回答の精度が低い

**診断**:
- AI Searchの検索結果を確認
- Azure OpenAIのプロンプトを確認
- インデックスのドキュメント数を確認

**対処法**:
1. データの質を改善
2. インデックスを再作成
3. プロンプトを調整

#### 問題3: パフォーマンスが遅い

**症状**: レスポンスに時間がかかる

**診断**:
```powershell
# App Service Planのスケールを確認
az appservice plan show `
    --resource-group $RESOURCE_GROUP `
    --name "<app-service-plan-name>" `
    --query sku
```

**対処法**:
```powershell
# スケールアップ
az appservice plan update `
    --resource-group $RESOURCE_GROUP `
    --name "<app-service-plan-name>" `
    --sku P1V2

# またはスケールアウト
az appservice plan update `
    --resource-group $RESOURCE_GROUP `
    --name "<app-service-plan-name>" `
    --number-of-workers 3
```

## 改善のポイント

### RAG精度向上

1. **データの充実**
   - より多くのドキュメントを追加
   - データの質を向上

2. **プロンプト最適化**
   - システムメッセージの改善
   - Few-shot learningの活用

3. **ベクトル検索の導入**
   - Embeddingモデルの使用
   - ハイブリッド検索の実装

### パフォーマンス向上

1. **キャッシュの導入**
   - Azure Redis Cacheの使用
   - よくある質問の応答をキャッシュ

2. **非同期処理**
   - 長時間処理の非同期化
   - WebSocketsの導入

## 確認事項

以下をすべて確認してください:

- ✅ 基本機能テストが完了している
- ✅ RAG品質テストが完了している
- ✅ パフォーマンステストが完了している
- ✅ ログ分析ができている
- ✅ 監視設定が構成されている
- ✅ 運用手順を理解している
- ✅ トラブルシューティング方法を理解している

## まとめ

おめでとうございます!🎉

閉域RAGアプリケーションの構築、デプロイ、テスト、運用まで、すべてのステップを完了しました。

### 学習した内容

1. **環境準備** - Azure リソースとGitHubの設定
2. **データ準備** - オープンデータの取得と前処理
3. **インデックス作成** - AI Searchの構築
4. **アプリデプロイ** - GitHub Actionsを使用したCI/CD
5. **テストと運用** - 品質確認と継続的改善

### 次のステップ

さらに学習を進める場合:

- **機能拡張**: チャット履歴保存、ユーザー認証など
- **スケーラビリティ**: Azure Container Appsへの移行
- **高度なRAG**: Agent-basedアーキテクチャの実装
- **マルチモーダル**: 画像・音声への対応

### リソース

- [Azure OpenAI ドキュメント](https://learn.microsoft.com/ja-jp/azure/ai-services/openai/)
- [Azure AI Search ドキュメント](https://learn.microsoft.com/ja-jp/azure/search/)
- [RAG ベストプラクティス](https://learn.microsoft.com/ja-jp/azure/architecture/ai-ml/guide/rag/rag-solution-design-and-evaluation-guide)

---

**Happy Learning! 🚀**
