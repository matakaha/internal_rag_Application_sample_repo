"""
閉域RAGチャットアプリケーション
Azure App Service上で動作する、閉域網でセキュアなRAGシステム
"""
import os
from flask import Flask, render_template, request, jsonify
from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential
from azure.search.documents import SearchClient
from azure.core.credentials import AzureKeyCredential

app = Flask(__name__)

# 環境変数から設定を取得
AZURE_OPENAI_ENDPOINT = os.getenv("AZURE_OPENAI_ENDPOINT")
AZURE_OPENAI_DEPLOYMENT = os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4")
AZURE_SEARCH_ENDPOINT = os.getenv("AZURE_SEARCH_ENDPOINT")
AZURE_SEARCH_INDEX = os.getenv("AZURE_SEARCH_INDEX", "redlist-index")
AZURE_SEARCH_KEY = os.getenv("AZURE_SEARCH_KEY")

# Azure OpenAI クライアント初期化
credential = DefaultAzureCredential()
openai_client = AzureOpenAI(
    azure_endpoint=AZURE_OPENAI_ENDPOINT,
    azure_ad_token_provider=lambda: credential.get_token("https://cognitiveservices.azure.com/.default").token,
    api_version="2024-02-01"
)

# Azure AI Search クライアント初期化
search_credential = AzureKeyCredential(AZURE_SEARCH_KEY) if AZURE_SEARCH_KEY else credential
search_client = SearchClient(
    endpoint=AZURE_SEARCH_ENDPOINT,
    index_name=AZURE_SEARCH_INDEX,
    credential=search_credential
)


def search_documents(query: str, top_k: int = 3) -> list:
    """
    Azure AI Searchでドキュメントを検索
    
    Args:
        query: 検索クエリ
        top_k: 取得する上位k件
        
    Returns:
        検索結果のリスト
    """
    try:
        results = search_client.search(
            search_text=query,
            top=top_k,
            select=["content", "title", "url"]
        )
        
        documents = []
        for result in results:
            documents.append({
                "content": result.get("content", ""),
                "title": result.get("title", ""),
                "url": result.get("url", ""),
                "score": result.get("@search.score", 0)
            })
        
        return documents
    except Exception as e:
        print(f"Search error: {e}")
        return []


def generate_response(user_message: str, context_documents: list) -> str:
    """
    RAGを使用してレスポンスを生成
    
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
        response = openai_client.chat.completions.create(
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
        print(f"OpenAI error: {e}")
        return f"申し訳ございません。エラーが発生しました: {str(e)}"


@app.route('/')
def index():
    """メインページ"""
    return render_template('index.html')


@app.route('/api/chat', methods=['POST'])
def chat():
    """チャットAPIエンドポイント"""
    try:
        data = request.json
        user_message = data.get('message', '')
        
        if not user_message:
            return jsonify({'error': 'メッセージが空です'}), 400
        
        # ドキュメント検索
        documents = search_documents(user_message)
        
        # レスポンス生成
        response = generate_response(user_message, documents)
        
        return jsonify({
            'response': response,
            'sources': [
                {'title': doc['title'], 'url': doc['url']}
                for doc in documents
            ]
        })
    
    except Exception as e:
        print(f"Chat error: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/health')
def health():
    """ヘルスチェックエンドポイント"""
    return jsonify({'status': 'healthy'})


if __name__ == '__main__':
    # 開発環境では Flask サーバーを起動
    # 本番環境では Gunicorn などを使用
    app.run(host='0.0.0.0', port=8000, debug=False)
