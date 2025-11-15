# Step 3: AI Searchインデックス作成

このステップでは、Azure CLIを使用してAI Searchのインデックスを作成し、Blob Storageのデータをインデクシングします。

## 📚 学習目標

このステップを完了すると、以下ができるようになります:

- Azure AI Searchインデックスの作成
- データソースの構成
- インデクサーの作成と実行
- ベクトル検索の設定
- インデックスの動作確認

## 前提条件

- Step 1, 2が完了していること
- Blob Storageにデータがアップロード済みであること
- AI Search サービスが作成済みであること

## インデックス作成手順

### 1. AI Search接続情報の取得

```powershell
# 環境変数を設定
$RESOURCE_GROUP = "rg-internal-rag-dev"
$SEARCH_SERVICE = "<your-search-service-name>"

# AI Search管理キーを取得(設定用)
$SEARCH_ADMIN_KEY = az search admin-key show `
    --resource-group $RESOURCE_GROUP `
    --service-name $SEARCH_SERVICE `
    --query primaryKey -o tsv

# エンドポイントURL
$SEARCH_ENDPOINT = "https://$SEARCH_SERVICE.search.windows.net"

Write-Host "Search Endpoint: $SEARCH_ENDPOINT"
```

### 2. インデックススキーマの作成

`scripts/create-index.ps1`:

```powershell
# AI Searchインデックス作成スクリプト

param(
    [Parameter(Mandatory=$true)]
    [string]$SearchService,
    
    [Parameter(Mandatory=$true)]
    [string]$SearchAdminKey,
    
    [string]$IndexName = "redlist-index"
)

$searchEndpoint = "https://$SearchService.search.windows.net"
$apiVersion = "2023-11-01"

# インデックススキーマを定義
$indexSchema = @{
    name = $IndexName
    fields = @(
        @{
            name = "id"
            type = "Edm.String"
            key = $true
            searchable = $false
        },
        @{
            name = "title"
            type = "Edm.String"
            searchable = $true
            filterable = $true
            sortable = $true
            analyzer = "ja.lucene"
        },
        @{
            name = "content"
            type = "Edm.String"
            searchable = $true
            analyzer = "ja.lucene"
        },
        @{
            name = "category"
            type = "Edm.String"
            searchable = $true
            filterable = $true
            facetable = $true
        },
        @{
            name = "rank"
            type = "Edm.String"
            searchable = $false
            filterable = $true
            facetable = $true
        },
        @{
            name = "scientific_name"
            type = "Edm.String"
            searchable = $true
            filterable = $true
            sortable = $true
        },
        @{
            name = "japanese_name"
            type = "Edm.String"
            searchable = $true
            filterable = $true
            sortable = $true
            analyzer = "ja.lucene"
        },
        @{
            name = "family"
            type = "Edm.String"
            searchable = $true
            filterable = $true
            facetable = $true
            analyzer = "ja.lucene"
        },
        @{
            name = "url"
            type = "Edm.String"
            searchable = $false
        }
    )
    semantic = @{
        configurations = @(
            @{
                name = "semantic-config"
                prioritizedFields = @{
                    titleField = @{
                        fieldName = "title"
                    }
                    prioritizedContentFields = @(
                        @{
                            fieldName = "content"
                        }
                    )
                    prioritizedKeywordsFields = @(
                        @{
                            fieldName = "category"
                        },
                        @{
                            fieldName = "rank"
                        }
                    )
                }
            }
        )
    }
}

# インデックスを作成
$headers = @{
    "Content-Type" = "application/json"
    "api-key" = $SearchAdminKey
}

$uri = "$searchEndpoint/indexes/$IndexName`?api-version=$apiVersion"
$body = $indexSchema | ConvertTo-Json -Depth 10

Write-Host "Creating index: $IndexName"

try {
    $response = Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body $body
    Write-Host "Index created successfully!" -ForegroundColor Green
    $response | ConvertTo-Json -Depth 5
} catch {
    Write-Error "Failed to create index: $_"
    Write-Error $_.Exception.Response
}
```

実行:

```powershell
.\scripts\create-index.ps1 `
    -SearchService $SEARCH_SERVICE `
    -SearchAdminKey $SEARCH_ADMIN_KEY `
    -IndexName "redlist-index"
```

### 3. データソースの作成

Blob Storageをデータソースとして登録します。

`scripts/create-datasource.ps1`:

```powershell
# AI Searchデータソース作成スクリプト

param(
    [Parameter(Mandatory=$true)]
    [string]$SearchService,
    
    [Parameter(Mandatory=$true)]
    [string]$SearchAdminKey,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountKey,
    
    [string]$ContainerName = "rag-documents",
    [string]$DataSourceName = "blob-datasource"
)

$searchEndpoint = "https://$SearchService.search.windows.net"
$apiVersion = "2023-11-01"

# データソース定義
$dataSource = @{
    name = $DataSourceName
    type = "azureblob"
    credentials = @{
        connectionString = "DefaultEndpointsProtocol=https;AccountName=$StorageAccountName;AccountKey=$StorageAccountKey;EndpointSuffix=core.windows.net"
    }
    container = @{
        name = $ContainerName
        query = ""
    }
    dataChangeDetectionPolicy = @{
        "@odata.type" = "#Microsoft.Azure.Search.HighWaterMarkChangeDetectionPolicy"
        highWaterMarkColumnName = "_ts"
    }
}

# データソースを作成
$headers = @{
    "Content-Type" = "application/json"
    "api-key" = $SearchAdminKey
}

$uri = "$searchEndpoint/datasources/$DataSourceName`?api-version=$apiVersion"
$body = $dataSource | ConvertTo-Json -Depth 10

Write-Host "Creating data source: $DataSourceName"

try {
    $response = Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body $body
    Write-Host "Data source created successfully!" -ForegroundColor Green
    $response | ConvertTo-Json -Depth 5
} catch {
    Write-Error "Failed to create data source: $_"
}
```

Storage Accountキーを取得して実行:

```powershell
# Storage Account キーを取得
$STORAGE_ACCOUNT = "<your-storage-account-name>"
$STORAGE_KEY = az storage account keys list `
    --resource-group $RESOURCE_GROUP `
    --account-name $STORAGE_ACCOUNT `
    --query "[0].value" -o tsv

# データソースを作成
.\scripts\create-datasource.ps1 `
    -SearchService $SEARCH_SERVICE `
    -SearchAdminKey $SEARCH_ADMIN_KEY `
    -StorageAccountName $STORAGE_ACCOUNT `
    -StorageAccountKey $STORAGE_KEY `
    -ContainerName "rag-documents"
```

### 4. インデクサーの作成

データソースからインデックスにデータを取り込むインデクサーを作成します。

`scripts/create-indexer.ps1`:

```powershell
# AI Searchインデクサー作成スクリプト

param(
    [Parameter(Mandatory=$true)]
    [string]$SearchService,
    
    [Parameter(Mandatory=$true)]
    [string]$SearchAdminKey,
    
    [string]$IndexerName = "blob-indexer",
    [string]$DataSourceName = "blob-datasource",
    [string]$IndexName = "redlist-index"
)

$searchEndpoint = "https://$SearchService.search.windows.net"
$apiVersion = "2023-11-01"

# インデクサー定義
$indexer = @{
    name = $IndexerName
    dataSourceName = $DataSourceName
    targetIndexName = $IndexName
    schedule = @{
        interval = "PT2H"  # 2時間ごと
    }
    parameters = @{
        batchSize = 50
        maxFailedItems = 10
        maxFailedItemsPerBatch = 5
        configuration = @{
            dataToExtract = "contentAndMetadata"
            parsingMode = "jsonLines"
        }
    }
    fieldMappings = @(
        @{
            sourceFieldName = "id"
            targetFieldName = "id"
        },
        @{
            sourceFieldName = "title"
            targetFieldName = "title"
        },
        @{
            sourceFieldName = "content"
            targetFieldName = "content"
        },
        @{
            sourceFieldName = "category"
            targetFieldName = "category"
        },
        @{
            sourceFieldName = "rank"
            targetFieldName = "rank"
        },
        @{
            sourceFieldName = "scientific_name"
            targetFieldName = "scientific_name"
        },
        @{
            sourceFieldName = "japanese_name"
            targetFieldName = "japanese_name"
        },
        @{
            sourceFieldName = "family"
            targetFieldName = "family"
        },
        @{
            sourceFieldName = "url"
            targetFieldName = "url"
        }
    )
}

# インデクサーを作成
$headers = @{
    "Content-Type" = "application/json"
    "api-key" = $SearchAdminKey
}

$uri = "$searchEndpoint/indexers/$IndexerName`?api-version=$apiVersion"
$body = $indexer | ConvertTo-Json -Depth 10

Write-Host "Creating indexer: $IndexerName"

try {
    $response = Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body $body
    Write-Host "Indexer created successfully!" -ForegroundColor Green
    $response | ConvertTo-Json -Depth 5
} catch {
    Write-Error "Failed to create indexer: $_"
}
```

実行:

```powershell
.\scripts\create-indexer.ps1 `
    -SearchService $SEARCH_SERVICE `
    -SearchAdminKey $SEARCH_ADMIN_KEY
```

### 5. インデクサーの実行

```powershell
# インデクサーを手動実行
$IndexerName = "blob-indexer"
$uri = "$SEARCH_ENDPOINT/indexers/$IndexerName/run?api-version=2023-11-01"
$headers = @{
    "api-key" = $SEARCH_ADMIN_KEY
}

Invoke-RestMethod -Uri $uri -Method Post -Headers $headers

Write-Host "Indexer started. Waiting for completion..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# インデクサーのステータス確認
$statusUri = "$SEARCH_ENDPOINT/indexers/$IndexerName/status?api-version=2023-11-01"
$status = Invoke-RestMethod -Uri $statusUri -Headers $headers

$status.lastResult | Format-List
```

### 6. インデックスの確認

```powershell
# インデックス統計を取得
$statsUri = "$SEARCH_ENDPOINT/indexes/redlist-index/stats?api-version=2023-11-01"
$headers = @{
    "api-key" = $SEARCH_ADMIN_KEY
}

$stats = Invoke-RestMethod -Uri $statsUri -Headers $headers
Write-Host "`nIndex Statistics:" -ForegroundColor Cyan
$stats | Format-List

# ドキュメント数を確認
Write-Host "`nDocument Count: $($stats.documentCount)" -ForegroundColor Green
```

### 7. 検索テスト

インデックスが正しく作成されたか、検索テストを実施します。

```powershell
# シンプルな検索テスト
$searchUri = "$SEARCH_ENDPOINT/indexes/redlist-index/docs/search?api-version=2023-11-01"
$headers = @{
    "Content-Type" = "application/json"
    "api-key" = $SEARCH_ADMIN_KEY
}

$searchQuery = @{
    search = "イリオモテヤマネコ"
    top = 3
    select = "title,content,url"
} | ConvertTo-Json

$results = Invoke-RestMethod -Uri $searchUri -Method Post -Headers $headers -Body $searchQuery

Write-Host "`nSearch Results:" -ForegroundColor Cyan
$results.value | ForEach-Object {
    Write-Host "`nTitle: $($_.title)" -ForegroundColor Yellow
    Write-Host "Content: $($_.content.Substring(0, [Math]::Min(100, $_.content.Length)))..."
    Write-Host "URL: $($_.url)"
    Write-Host "---"
}
```

## Azure CLIを使用した簡易作成

上記のREST APIの代わりに、Azure CLIでも作成できます。

```powershell
# インデックスを作成(JSON定義ファイルを使用)
az search index create `
    --resource-group $RESOURCE_GROUP `
    --service-name $SEARCH_SERVICE `
    --name redlist-index `
    --fields "@data/schema/index-schema.json"

# データソースを作成
az search data-source create `
    --resource-group $RESOURCE_GROUP `
    --service-name $SEARCH_SERVICE `
    --name blob-datasource `
    --type azureblob `
    --connection-string "DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT;AccountKey=$STORAGE_KEY" `
    --container rag-documents

# インデクサーを作成
az search indexer create `
    --resource-group $RESOURCE_GROUP `
    --service-name $SEARCH_SERVICE `
    --name blob-indexer `
    --data-source-name blob-datasource `
    --target-index-name redlist-index

# インデクサーを実行
az search indexer run `
    --resource-group $RESOURCE_GROUP `
    --service-name $SEARCH_SERVICE `
    --name blob-indexer
```

## 確認事項

以下をすべて確認してください:

- ✅ AI Searchインデックスが作成されている
- ✅ データソースが作成されている
- ✅ インデクサーが作成されている
- ✅ インデクサーが正常に実行されている
- ✅ ドキュメントがインデックスに登録されている
- ✅ 検索テストが成功している

## トラブルシューティング

### インデクサー実行に失敗する

**症状**: インデクサーのステータスがエラー

**対処法**:
```powershell
# エラー詳細を確認
$statusUri = "$SEARCH_ENDPOINT/indexers/blob-indexer/status?api-version=2023-11-01"
$status = Invoke-RestMethod -Uri $statusUri -Headers @{"api-key" = $SEARCH_ADMIN_KEY}

$status.lastResult.errors | Format-List

# よくある原因:
# 1. Blob StorageのアクセスキーMicrosoft Azure Search を許可していない
# 2. JSONLフォーマットが不正
# 3. フィールドマッピングが間違っている
```

### ドキュメント数が0

**症状**: インデックスは作成されたがドキュメントが0件

**対処法**:
- Blob Storageにファイルが存在するか確認
- インデクサーのparsingModeが`jsonLines`になっているか確認
- Blob Storageへのアクセス権限を確認

### 検索結果が返らない

**症状**: 検索クエリを実行しても結果が0件

**対処法**:
- インデックスにドキュメントが登録されているか確認
- 検索フィールドが`searchable: true`になっているか確認
- 検索クエリのスペルミスを確認

## 次のステップ

AI Searchインデックス作成が完了したら、次は **[Step 4: アプリケーションデプロイ](step04-deploy-app.md)** に進みましょう。

GitHubを使用してアプリケーションをAzure App Serviceにデプロイします。
