"""
Azure接続テストスクリプト
Managed Identityを使用してAzure OpenAIとAI Searchへの接続をテスト
"""
import os
import sys
from azure.identity import DefaultAzureCredential, AzureCliCredential
from openai import AzureOpenAI
from azure.search.documents import SearchClient
from azure.core.credentials import AzureKeyCredential

def test_azure_openai():
    """Azure OpenAI接続テスト"""
    print("\n=== Testing Azure OpenAI Connection ===")
    
    endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
    deployment = os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4")
    
    if not endpoint:
        print("❌ AZURE_OPENAI_ENDPOINT environment variable not set")
        return False
    
    print(f"Endpoint: {endpoint}")
    print(f"Deployment: {deployment}")
    
    try:
        # ローカル開発ではAzure CLI認証、本番ではManaged Identity
        credential = AzureCliCredential()
        
        client = AzureOpenAI(
            azure_endpoint=endpoint,
            azure_ad_token_provider=lambda: credential.get_token("https://cognitiveservices.azure.com/.default").token,
            api_version="2024-02-01"
        )
        
        # 簡単なテストリクエスト
        response = client.chat.completions.create(
            model=deployment,
            messages=[
                {"role": "user", "content": "Hello"}
            ],
            max_tokens=10
        )
        
        print("✅ Azure OpenAI connection successful!")
        print(f"Response: {response.choices[0].message.content}")
        return True
        
    except Exception as e:
        print(f"❌ Azure OpenAI connection failed: {e}")
        return False


def test_azure_search():
    """Azure AI Search接続テスト"""
    print("\n=== Testing Azure AI Search Connection ===")
    
    endpoint = os.getenv("AZURE_SEARCH_ENDPOINT")
    index_name = os.getenv("AZURE_SEARCH_INDEX", "redlist-index")
    search_key = os.getenv("AZURE_SEARCH_KEY")
    
    if not endpoint:
        print("❌ AZURE_SEARCH_ENDPOINT environment variable not set")
        return False
    
    print(f"Endpoint: {endpoint}")
    print(f"Index: {index_name}")
    
    try:
        # キーがあればキー認証、なければManaged Identity
        if search_key:
            credential = AzureKeyCredential(search_key)
            print("Using API Key authentication")
        else:
            credential = AzureCliCredential()
            print("Using Managed Identity authentication")
        
        client = SearchClient(
            endpoint=endpoint,
            index_name=index_name,
            credential=credential
        )
        
        # インデックス統計を取得
        # Note: この操作には適切な権限が必要
        results = client.search(
            search_text="test",
            top=1
        )
        
        # 結果を消費して接続を確認
        result_count = 0
        for _ in results:
            result_count += 1
            break
        
        print("✅ Azure AI Search connection successful!")
        return True
        
    except Exception as e:
        print(f"❌ Azure AI Search connection failed: {e}")
        print("\nNote: Ensure the index exists and you have proper permissions")
        return False


def main():
    """メイン関数"""
    print("=" * 50)
    print("Azure Connection Test")
    print("=" * 50)
    
    # .envファイルがあれば読み込み
    try:
        from dotenv import load_dotenv
        load_dotenv()
        print("✅ Loaded .env file")
    except ImportError:
        print("ℹ️  python-dotenv not installed, using environment variables only")
    
    # テスト実行
    openai_ok = test_azure_openai()
    search_ok = test_azure_search()
    
    # 結果サマリー
    print("\n" + "=" * 50)
    print("Test Summary")
    print("=" * 50)
    print(f"Azure OpenAI: {'✅ PASS' if openai_ok else '❌ FAIL'}")
    print(f"Azure AI Search: {'✅ PASS' if search_ok else '❌ FAIL'}")
    
    if openai_ok and search_ok:
        print("\n🎉 All tests passed!")
        sys.exit(0)
    else:
        print("\n⚠️  Some tests failed. Please check your configuration.")
        sys.exit(1)


if __name__ == "__main__":
    main()
