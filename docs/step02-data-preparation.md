# Step 2: データ準備

このステップでは、RAGシステムで使用するデータを準備します。デジタル庁のオープンデータをダウンロードし、Azure Blob Storageにアップロードします。

## 📚 学習目標

このステップを完了すると、以下ができるようになります:

- デジタル庁のオープンデータの取得方法
- CSVデータの確認と前処理
- Azure Blob Storageへのデータアップロード
- データ格納の確認

## データソース

デジタル庁が公開しているオープンデータを使用します:

**データセットURL**: https://www.digital.go.jp/resources/data_dataset

このサイトから、以下のようなデータセットが取得できます:
- デジタル庁の施策・プロジェクト情報
- 各種ガイドライン
- 統計データ
- FAQ

## データ準備手順

### 1. データセットの選択とダウンロード

#### デジタル庁サイトからCSVをダウンロード

1. ブラウザで https://www.digital.go.jp/resources/data_dataset にアクセス
2. 適切なデータセットを選択
3. CSV形式でダウンロード

**推奨データセット例**:
- `digital-agency-faq.csv` - デジタル庁FAQ
- `digital-agency-projects.csv` - プロジェクト情報
- `digital-agency-guidelines.csv` - ガイドライン

#### 手動ダウンロードの例

```powershell
# データ保存用ディレクトリを作成
New-Item -ItemType Directory -Force -Path ".\data\raw"

# ブラウザでダウンロードしたCSVを移動
# 例: ダウンロードフォルダから移動
Move-Item "$env:USERPROFILE\Downloads\digital-agency-faq.csv" ".\data\raw\"
```

> 📝 **Note**: データセットの具体的なURLは変更される可能性があります。デジタル庁の最新情報を確認してください。

### 2. データの確認と前処理

ダウンロードしたCSVファイルの内容を確認します。

```powershell
# CSVファイルの確認
Get-Content .\data\raw\digital-agency-faq.csv | Select-Object -First 10

# または、Pythonで確認
python
```

```python
import pandas as pd

# CSVファイルを読み込み
df = pd.read_csv('data/raw/digital-agency-faq.csv', encoding='utf-8')

# データの概要を表示
print(f"行数: {len(df)}")
print(f"列名: {df.columns.tolist()}")
print("\n最初の5行:")
print(df.head())

# 必要な列を確認
# 例: title, content, category, url などが含まれているか確認
```

#### データ形式の例

RAGに適したデータ形式:

```csv
id,title,content,category,url
1,"デジタル庁について","デジタル庁は、デジタル社会の実現に向けて...","組織","https://..."
2,"マイナンバーカードとは","マイナンバーカードは...","サービス","https://..."
```

#### データの前処理(必要に応じて)

```python
# 前処理スクリプト例
import pandas as pd
import json

# CSVを読み込み
df = pd.read_csv('data/raw/digital-agency-faq.csv', encoding='utf-8')

# 欠損値を削除
df = df.dropna(subset=['title', 'content'])

# 重複を削除
df = df.drop_duplicates(subset=['title'])

# RAG用に整形
df['combined_text'] = df['title'] + "\n\n" + df['content']

# JSON Lines形式で保存(AI Searchインデックス用)
output_data = []
for idx, row in df.iterrows():
    output_data.append({
        'id': str(row.get('id', idx)),
        'title': row['title'],
        'content': row['content'],
        'category': row.get('category', '未分類'),
        'url': row.get('url', ''),
        'combined_text': row['combined_text']
    })

# 処理済みディレクトリに保存
import os
os.makedirs('data/processed', exist_ok=True)

with open('data/processed/documents.jsonl', 'w', encoding='utf-8') as f:
    for item in output_data:
        f.write(json.dumps(item, ensure_ascii=False) + '\n')

print(f"処理完了: {len(output_data)}件のドキュメント")
```

### 3. Azure Blob Storageへのアップロード

#### Blob Storageの準備

```powershell
# 環境変数を設定
$RESOURCE_GROUP = "rg-internal-rag-dev"
$STORAGE_ACCOUNT = "<your-storage-account-name>"
$CONTAINER_NAME = "rag-documents"

# コンテナを作成(まだ存在しない場合)
az storage container create `
    --account-name $STORAGE_ACCOUNT `
    --name $CONTAINER_NAME `
    --auth-mode login

# 作成確認
az storage container show `
    --account-name $STORAGE_ACCOUNT `
    --name $CONTAINER_NAME `
    --auth-mode login
```

#### データファイルのアップロード

```powershell
# 処理済みJSONLファイルをアップロード
az storage blob upload `
    --account-name $STORAGE_ACCOUNT `
    --container-name $CONTAINER_NAME `
    --name "documents.jsonl" `
    --file "data/processed/documents.jsonl" `
    --auth-mode login `
    --overwrite

# アップロード確認
az storage blob list `
    --account-name $STORAGE_ACCOUNT `
    --container-name $CONTAINER_NAME `
    --auth-mode login `
    --output table
```

#### 複数ファイルのアップロード

```powershell
# dataディレクトリ内のすべてのJSONLファイルをアップロード
Get-ChildItem -Path "data/processed" -Filter "*.jsonl" | ForEach-Object {
    $fileName = $_.Name
    Write-Host "Uploading $fileName..."
    
    az storage blob upload `
        --account-name $STORAGE_ACCOUNT `
        --container-name $CONTAINER_NAME `
        --name $fileName `
        --file $_.FullName `
        --auth-mode login `
        --overwrite
}

Write-Host "アップロード完了"
```

### 4. データの検証

アップロードされたデータを確認します。

```powershell
# Blobの一覧を表示
az storage blob list `
    --account-name $STORAGE_ACCOUNT `
    --container-name $CONTAINER_NAME `
    --auth-mode login `
    --query "[].{Name:name, Size:properties.contentLength, LastModified:properties.lastModified}" `
    --output table

# 特定のBlobをダウンロードして確認
az storage blob download `
    --account-name $STORAGE_ACCOUNT `
    --container-name $CONTAINER_NAME `
    --name "documents.jsonl" `
    --file "verify-download.jsonl" `
    --auth-mode login

# ダウンロードしたファイルを確認
Get-Content verify-download.jsonl | Select-Object -First 5
```

### 5. データスキーマの定義

AI Searchでインデックスを作成するために、データスキーマを定義します。

`data/schema/index-schema.json`:

```json
{
  "name": "documents-index",
  "fields": [
    {
      "name": "id",
      "type": "Edm.String",
      "key": true,
      "searchable": false
    },
    {
      "name": "title",
      "type": "Edm.String",
      "searchable": true,
      "filterable": true,
      "sortable": true
    },
    {
      "name": "content",
      "type": "Edm.String",
      "searchable": true
    },
    {
      "name": "category",
      "type": "Edm.String",
      "filterable": true,
      "facetable": true
    },
    {
      "name": "url",
      "type": "Edm.String",
      "searchable": false
    },
    {
      "name": "combined_text",
      "type": "Edm.String",
      "searchable": true
    },
    {
      "name": "content_vector",
      "type": "Collection(Edm.Single)",
      "searchable": true,
      "dimensions": 1536,
      "vectorSearchProfile": "vector-profile"
    }
  ],
  "vectorSearch": {
    "profiles": [
      {
        "name": "vector-profile",
        "algorithm": "hnsw-config"
      }
    ],
    "algorithms": [
      {
        "name": "hnsw-config",
        "kind": "hnsw",
        "hnswParameters": {
          "m": 4,
          "efConstruction": 400,
          "efSearch": 500,
          "metric": "cosine"
        }
      }
    ]
  },
  "semantic": {
    "configurations": [
      {
        "name": "semantic-config",
        "prioritizedFields": {
          "titleField": {
            "fieldName": "title"
          },
          "contentFields": [
            {
              "fieldName": "content"
            }
          ]
        }
      }
    ]
  }
}
```

## サンプルデータの作成(データソースが利用できない場合)

デジタル庁のデータが取得できない場合は、サンプルデータを作成できます。

```python
import json

sample_data = [
    {
        "id": "1",
        "title": "デジタル庁について",
        "content": "デジタル庁は、デジタル社会の形成に関する司令塔として、未来志向のDX（デジタル・トランスフォーメーション）を大胆に推進し、デジタル時代の官民のインフラを今後5年で一気呵成に作り上げることを目指します。",
        "category": "組織",
        "url": "https://www.digital.go.jp/",
        "combined_text": "デジタル庁について\n\nデジタル庁は、デジタル社会の形成に関する司令塔として、未来志向のDX（デジタル・トランスフォーメーション）を大胆に推進し、デジタル時代の官民のインフラを今後5年で一気呵成に作り上げることを目指します。"
    },
    {
        "id": "2",
        "title": "マイナンバーカードとは",
        "content": "マイナンバーカードは、マイナンバー(個人番号)が記載された顔写真付きのカードです。本人確認のための身分証明書として利用できるほか、様々な行政サービスを受けることができます。",
        "category": "サービス",
        "url": "https://www.digital.go.jp/policies/mynumber/",
        "combined_text": "マイナンバーカードとは\n\nマイナンバーカードは、マイナンバー(個人番号)が記載された顔写真付きのカードです。本人確認のための身分証明書として利用できるほか、様々な行政サービスを受けることができます。"
    },
    # 更に追加...
]

# サンプルデータをJSONL形式で保存
import os
os.makedirs('data/processed', exist_ok=True)

with open('data/processed/sample-documents.jsonl', 'w', encoding='utf-8') as f:
    for item in sample_data:
        f.write(json.dumps(item, ensure_ascii=False) + '\n')

print(f"サンプルデータ作成完了: {len(sample_data)}件")
```

## 確認事項

以下をすべて確認してください:

- ✅ デジタル庁のデータをダウンロードした
- ✅ データの前処理を実施した
- ✅ JSONL形式に変換した
- ✅ Blob Storageコンテナを作成した
- ✅ データファイルをアップロードした
- ✅ アップロードを確認した
- ✅ データスキーマを定義した

## トラブルシューティング

### CSVの文字コードが正しくない

**症状**: Pandasで読み込み時に文字化けする

**対処法**:
```python
# 異なるエンコーディングを試す
df = pd.read_csv('data.csv', encoding='shift-jis')
# または
df = pd.read_csv('data.csv', encoding='cp932')
```

### Blob Storageアップロードに失敗

**症状**: `az storage blob upload` がエラーになる

**対処法**:
```powershell
# ストレージアカウントへのアクセス権限を確認
az role assignment list `
    --assignee "<your-email>" `
    --scope "/subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"

# 「Storage Blob Data Contributor」ロールを付与
az role assignment create `
    --assignee "<your-email>" `
    --role "Storage Blob Data Contributor" `
    --scope "/subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"
```

### データサイズが大きすぎる

**症状**: ファイルサイズが大きくアップロードに時間がかかる

**対処法**:
- データを分割してアップロード
- 不要なカラムを削除
- 圧縮してアップロード

## 次のステップ

データ準備が完了したら、次は **[Step 3: AI Searchインデックス作成](step03-indexing.md)** に進みましょう。

Azure CLIを使用して、アップロードしたデータからAI Searchインデックスを作成します。
