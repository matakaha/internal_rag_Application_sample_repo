"""
Azure Functions閉域RAGチャットアプリケーション
Python v2プログラミングモデルを使用(非同期対応版)

開発環境: AppServicePlan B1 (フロントエンド/バックエンド共有)
本番環境: Premium Plan (EP1以上) 推奨
"""
import azure.functions as func
import logging
import os
import json
import asyncio
from openai import AsyncAzureOpenAI
from azure.identity.aio import DefaultAzureCredential
from azure.search.documents.aio import SearchClient
from azure.core.credentials import AzureKeyCredential

# Azure Functions アプリケーション初期化
app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

# 環境変数から設定を取得
AZURE_OPENAI_ENDPOINT = os.getenv("AZURE_OPENAI_ENDPOINT")
AZURE_OPENAI_DEPLOYMENT = os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4")
AZURE_SEARCH_ENDPOINT = os.getenv("AZURE_SEARCH_ENDPOINT")
AZURE_SEARCH_INDEX = os.getenv("AZURE_SEARCH_INDEX", "redlist-index")
AZURE_SEARCH_KEY = os.getenv("AZURE_SEARCH_KEY")

# Azure認証情報とクライアント（グローバルスコープで再利用）
credential = DefaultAzureCredential()
openai_client = None
search_client = None


async def get_openai_client():
    """
    OpenAIクライアントをシングルトンで取得（非同期版）
    初回呼び出し時のみクライアントを作成し、以降は再利用
    """
    global openai_client
    if openai_client is None:
        # Azure AD認証トークンを取得する関数
        async def get_azure_ad_token():
            token = await credential.get_token("https://cognitiveservices.azure.com/.default")
            return token.token
        
        openai_client = AsyncAzureOpenAI(
            azure_endpoint=AZURE_OPENAI_ENDPOINT,
            azure_ad_token_provider=get_azure_ad_token,
            api_version="2024-02-01"
        )
    return openai_client


async def get_search_client():
    """
    AI Searchクライアントをシングルトンで取得（非同期版）
    初回呼び出し時のみクライアントを作成し、以降は再利用
    """
    global search_client
    if search_client is None:
        # Key認証またはManaged Identity認証を選択
        search_credential = AzureKeyCredential(AZURE_SEARCH_KEY) if AZURE_SEARCH_KEY else credential
        search_client = SearchClient(
            endpoint=AZURE_SEARCH_ENDPOINT,
            index_name=AZURE_SEARCH_INDEX,
            credential=search_credential
        )
    return search_client


async def search_documents(query: str, top_k: int = 3) -> list:
    """
    Azure AI Searchでドキュメントを検索（非同期版）
    
    Args:
        query: 検索クエリ
        top_k: 取得する上位k件
        
    Returns:
        検索結果のリスト
    """
    try:
        # 検索クライアントを取得
        client = await get_search_client()
        
        # 検索を実行（非同期）
        results = client.search(
            search_text=query,
            top=top_k,
            select=["content", "title", "url"]
        )
        
        # 検索結果を収集
        documents = []
        async for result in results:
            documents.append({
                "content": result.get("content", ""),
                "title": result.get("title", ""),
                "url": result.get("url", ""),
                "score": result.get("@search.score", 0)
            })
        
        logging.info(f"Found {len(documents)} documents for query: {query[:50]}...")
        return documents
        
    except Exception as e:
        logging.error(f"Search error: {e}")
        return []


async def generate_response(user_message: str, context_documents: list) -> str:
    """
    RAGを使用してレスポンスを生成（非同期版）
    
    Args:
        user_message: ユーザーのメッセージ
        context_documents: コンテキストとなるドキュメント
        
    Returns:
        生成されたレスポンス
    """
    # コンテキストを構築
    context = "\n\n".join([
        f"【{doc['title']}】\n{doc['content']}\n出典: {doc['url']}"
        for doc in context_documents
    ])
    
    # プロンプト構築
    system_message = """あなたは親切なアシスタントです。
提供されたコンテキスト情報を基に、ユーザーの質問に正確に答えてください。
コンテキストに情報がない場合は、その旨を伝えてください。
回答の際は、参照した情報の出典も明記してください。"""
    
    user_prompt = f"""コンテキスト:
{context}

質問: {user_message}

上記のコンテキストを参考に、質問に答えてください。"""
    
    try:
        # OpenAIクライアントを取得
        client = await get_openai_client()
        
        # チャット補完を生成（非同期）
        response = await client.chat.completions.create(
            model=AZURE_OPENAI_DEPLOYMENT,
            messages=[
                {"role": "system", "content": system_message},
                {"role": "user", "content": user_prompt}
            ],
            temperature=0.7,
            max_tokens=800
        )
        
        return response.choices[0].message.content
        
    except Exception as e:
        logging.error(f"OpenAI error: {e}")
        return f"申し訳ございません。エラーが発生しました: {str(e)}"


@app.route(route="", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def index(req: func.HttpRequest) -> func.HttpResponse:
    """
    静的HTMLページを返す（ルートパス）
    """
    logging.info('Index page requested')
    
    try:
        # index.htmlファイルを読み込み
        html_path = os.path.join(os.path.dirname(__file__), 'static', 'index.html')
        with open(html_path, 'r', encoding='utf-8') as f:
            html_content = f.read()
        
        return func.HttpResponse(
            html_content,
            mimetype="text/html",
            status_code=200
        )
    except FileNotFoundError:
        logging.error('index.html not found')
        return func.HttpResponse(
            "Page not found",
            status_code=404
        )


@app.route(route="api/chat", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)
async def chat(req: func.HttpRequest) -> func.HttpResponse:
    """
    チャットAPIエンドポイント（非同期版）
    
    ユーザーのメッセージを受け取り、RAG（検索拡張生成）を使用して回答を生成します。
    処理フロー:
    1. ユーザーメッセージの検証
    2. AI Searchでドキュメント検索（非同期）
    3. OpenAIでレスポンス生成（非同期）
    4. 結果を返却
    """
    logging.info('Chat API invoked')
    
    try:
        # リクエストボディを解析
        req_body = req.get_json()
        user_message = req_body.get('message', '')
        
        # メッセージの検証
        if not user_message:
            return func.HttpResponse(
                json.dumps({'error': 'メッセージが空です'}, ensure_ascii=False),
                mimetype="application/json",
                status_code=400
            )
        
        logging.info(f"Processing message: {user_message[:50]}...")
        
        # ステップ1: ドキュメント検索（非同期）
        documents = await search_documents(user_message)
        
        # ステップ2: レスポンス生成（非同期）
        response = await generate_response(user_message, documents)
        
        # 結果を構築
        result = {
            'response': response,
            'sources': [
                {'title': doc['title'], 'url': doc['url']}
                for doc in documents
            ]
        }
        
        logging.info('Chat response generated successfully')
        
        return func.HttpResponse(
            json.dumps(result, ensure_ascii=False),
            mimetype="application/json",
            status_code=200
        )
    
    except ValueError as ve:
        logging.error(f"Invalid JSON: {ve}")
        return func.HttpResponse(
            json.dumps({'error': 'Invalid JSON format'}, ensure_ascii=False),
            mimetype="application/json",
            status_code=400
        )
    except Exception as e:
        logging.error(f"Chat error: {e}")
        return func.HttpResponse(
            json.dumps({'error': str(e)}, ensure_ascii=False),
            mimetype="application/json",
            status_code=500
        )


@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def health(req: func.HttpRequest) -> func.HttpResponse:
    """
    ヘルスチェックエンドポイント
    """
    logging.info('Health check invoked')
    
    return func.HttpResponse(
        json.dumps({'status': 'healthy'}, ensure_ascii=False),
        mimetype="application/json",
        status_code=200
    )
