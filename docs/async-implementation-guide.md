# 非同期実装ガイド

## 概要

このドキュメントでは、Azure Functions向けRAGアプリケーションの非同期実装について説明します。初学者向けに、非同期処理の基本概念と実装のポイントを解説します。

## なぜ非同期処理が必要か？

### 同期処理の問題点

```python
# 同期処理の例（改善前）
def chat(req):
    documents = search_documents(query)      # ⏳ 検索完了まで待機
    response = generate_response(documents)  # ⏳ 生成完了まで待機
    return response
```

**問題点:**
- 検索が完了するまで次の処理に進めない
- LLM呼び出しが完了するまで待機が必要
- 合計レスポンスタイム = 検索時間 + LLM生成時間

### 非同期処理の利点

```python
# 非同期処理の例（改善後）
async def chat(req):
    documents = await search_documents(query)      # 🚀 他の処理と並行可能
    response = await generate_response(documents)  # 🚀 効率的に実行
    return response
```

**利点:**
- I/O待機中に他の処理を実行可能
- Azure Functions内部で効率的にリソースを利用
- 複数リクエストの同時処理が改善

## 実装のポイント

### 1. 非同期関数の定義

通常の関数定義の前に`async`キーワードを追加します。

```python
# 同期版
def search_documents(query: str):
    client = get_search_client()
    results = client.search(query)
    return results

# 非同期版
async def search_documents(query: str):
    client = await get_search_client()
    results = client.search(query)
    # async for で非同期イテレーション
    async for result in results:
        # 処理
        pass
```

### 2. `await`キーワードの使用

非同期関数を呼び出す際は`await`を使用します。

```python
# ❌ 間違い
documents = search_documents(query)  # これはコルーチンオブジェクトを返す

# ✅ 正しい
documents = await search_documents(query)  # 実際に実行して結果を取得
```

### 3. 非同期クライアントの使用

Azure SDKとOpenAI SDKの非同期版を使用します。

```python
# 同期版クライアント
from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential
from azure.search.documents import SearchClient

# 非同期版クライアント
from openai import AsyncAzureOpenAI
from azure.identity.aio import DefaultAzureCredential
from azure.search.documents.aio import SearchClient
```

### 4. クライアントの再利用

クライアントはグローバル変数で保持し、再利用します（初期化コストの削減）。

```python
# グローバル変数
openai_client = None

async def get_openai_client():
    """シングルトンパターンでクライアントを取得"""
    global openai_client
    if openai_client is None:
        # 初回のみクライアントを作成
        openai_client = AsyncAzureOpenAI(...)
    return openai_client
```

## コードの読み方（初学者向け）

### `async`と`await`の関係

```python
async def chat(req: func.HttpRequest) -> func.HttpResponse:
    # この関数は「非同期関数」です
    # async をつけると、内部で await が使えます
    
    # await は「ここで待ちます」という意味
    documents = await search_documents(query)
    # ↑ search_documents の完了を待ってから次に進む
    
    response = await generate_response(documents)
    # ↑ generate_response の完了を待ってから次に進む
    
    return response
```

### `async for`の使い方

```python
async def search_documents(query: str):
    results = client.search(query)
    
    # 通常の for ではなく async for を使用
    documents = []
    async for result in results:
        # 検索結果を1件ずつ非同期に取得
        documents.append(result)
    
    return documents
```

## よくある質問

### Q1: いつ`async`をつけるべきですか？

**A:** 以下の場合に`async`をつけます：
- 内部で`await`を使う関数
- I/O操作（ネットワーク、ファイル）を含む関数
- Azure SDK、OpenAI SDKの非同期クライアントを使う関数

### Q2: `await`を忘れるとどうなりますか？

**A:** コルーチンオブジェクトが返され、実際の処理が実行されません。

```python
# ❌ await を忘れた場合
documents = search_documents(query)
# documents は <coroutine object> になり、実際の検索結果が得られない

# ✅ 正しい使い方
documents = await search_documents(query)
# documents は実際の検索結果（リスト）
```

### Q3: すべてを非同期にする必要がありますか？

**A:** いいえ、I/O操作以外は通常の同期関数でOKです。

```python
# これは同期のままでOK（計算処理）
def build_context(documents: list) -> str:
    return "\n\n".join([doc['content'] for doc in documents])

# これは非同期にすべき（ネットワークI/O）
async def search_documents(query: str) -> list:
    results = await client.search(query)
    return results
```

## パフォーマンスの比較

### 同期版の実行時間

```
検索: 500ms
↓ 待機
LLM生成: 2000ms
↓
合計: 2500ms
```

### 非同期版の実行時間

```
検索: 500ms (内部で効率的に処理)
↓
LLM生成: 2000ms (内部で効率的に処理)
↓
合計: 約2500ms (単一リクエスト時)

※ ただし、複数の同時リクエスト処理時に大きな差が出る
```

**重要:** 非同期の真価は**複数リクエストの同時処理**で発揮されます。

## まとめ

- ✅ `async`/`await`で非同期関数を定義・呼び出し
- ✅ Azure SDK、OpenAI SDKの非同期版クライアントを使用
- ✅ クライアントは再利用してパフォーマンス向上
- ✅ I/O操作は非同期、計算処理は同期のまま
- ✅ 初学者は「await = 待つ」と理解すればOK

## 参考リンク

- [Python asyncio 公式ドキュメント](https://docs.python.org/ja/3/library/asyncio.html)
- [Azure Functions Python 非同期サポート](https://learn.microsoft.com/ja-jp/azure/azure-functions/functions-reference-python)
- [OpenAI Python SDK - Async usage](https://github.com/openai/openai-python#async-usage)
