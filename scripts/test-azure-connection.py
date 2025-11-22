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
        
        # トークン取得用の関数
        def get_token():
            return credential.get_token("https://cognitiveservices.azure.com/.default").token
        
        client = AzureOpenAI(
            azure_endpoint=endpoint,
            azure_ad_token_provider=get_token,
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
        import traceback
        traceback.print_exc()
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
        
        # 認証のテストのみ(インデックスが存在しない場合もあるため)
        # SearchServiceClientを使用してサービスレベルの接続を確認
        from azure.search.documents.indexes import SearchIndexClient
        
        index_client = SearchIndexClient(
            endpoint=endpoint,
            credential=credential
        )
        
        # インデックス一覧を取得して接続と認証を確認
        try:
            index_names = [idx.name for idx in index_client.list_indexes()]
            print(f"✅ Azure AI Search connection successful!")
            
            if index_name in index_names:
                print(f"✅ Index '{index_name}' exists")
            else:
                print(f"ℹ️  Index '{index_name}' does not exist yet (will be created in Step 03)")
                if index_names:
                    print(f"   Existing indexes: {', '.join(index_names)}")
            
            return True
        except Exception as list_error:
            # インデックス一覧の取得に失敗した場合でも、エラー内容を確認
            error_msg = str(list_error)
            if "Forbidden" in error_msg or "403" in error_msg:
                print(f"❌ Authentication successful but insufficient permissions: {list_error}")
                print("   Required role: 'Search Service Contributor' or 'Search Index Data Reader'")
                return False
            else:
                # その他のエラーの場合
                raise
        
    except Exception as e:
        print(f"❌ Azure AI Search connection failed: {e}")
        print("\nNote: Ensure you have proper permissions to access the search service")
        import traceback
        traceback.print_exc()
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
