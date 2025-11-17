# 閉域RAGアプリケーション サンプルリポジトリ

[![Deploy to Azure Functions](https://github.com/matakaha/internal_rag_Application_sample_repo/workflows/Deploy%20to%20Azure%20Functions/badge.svg)](https://github.com/matakaha/internal_rag_Application_sample_repo/actions)

このリポジトリは、Azure閉域ネットワーク上で動作するRAG（Retrieval-Augmented Generation）チャットアプリケーションのサンプルです。初学者向けの教育用リポジトリとして、ステップバイステップで学習できるように構成されています。

## 📚 概要

このリポジトリは以下の2つのリポジトリを完了した後で実施することを想定しています:

1. **[internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step)** - 閉域RAG環境の構築
2. **[internal_rag_Application_deployment_step_by_step](https://github.com/matakaha/internal_rag_Application_deployment_step_by_step)** - GitHub Actionsを使用したCI/CD環境の構築

### 特徴

- ✅ **閉域ネットワーク対応**: Private Endpointを使用した完全閉域構成
- ✅ **Pythonベース**: Azure Functions (Python v2) + Azure OpenAI + Azure AI Searchによるサーバーレス実装
- ✅ **Flex Consumption**: コスト効率的なFlexible Consumptionプラン対応
- ✅ **CI/CD統合**: GitHub Actionsによる自動デプロイ
- ✅ **教育向け**: ステップバイステップで理解できる構成
- ✅ **実践的**: 環境省レッドリスト(絶滅危惧種データ)を活用したRAGシステム

## 🏗️ アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│          Azure Virtual Network (10.0.0.0/16)               │
│                                                             │
│  ┌──────────────────┐     ┌──────────────────┐            │
│  │   Azure OpenAI   │     │  AI Search       │            │
│  │   (Private EP)   │     │  (Private EP)    │            │
│  └────────┬─────────┘     └────────┬─────────┘            │
│           │                        │                       │
│           └────────┬───────────────┘                       │
│                    │                                       │
│         ┌──────────▼─────────────┐                        │
│         │  Azure Functions       │                        │
│         │  (Flex Consumption)    │                        │
│         │  (vNet統合)            │                        │
│         │                        │                        │
│         │  ┌──────────────────┐  │                        │
│         │  │ HTTP Trigger     │  │                        │
│         │  │ - GET  /         │  │                        │
│         │  │ - POST /api/chat │  │                        │
│         │  │ - GET  /health   │  │                        │
│         │  └──────────────────┘  │                        │
│         └────────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
                       │
                       │ GitHub Actions
                       │ (CI/CD Pipeline)
                       ▼
              ┌─────────────────┐
              │  GitHub         │
              │  Repository     │
              └─────────────────┘
```

### アーキテクチャの利点

- **サーバーレス**: 使用量に応じた自動スケーリング、アイドル時のコスト削減
- **Flex Consumption**: 従量課金でコスト効率的、高速コールドスタート
- **完全閉域**: Private Endpointによるセキュアな通信
- **Python v2モデル**: 最新のAzure Functions プログラミングモデル

## 📁 ディレクトリ構造

```
internal_rag_Application_sample_repo/
├── .github/
│   └── workflows/
│       ├── deploy.yml              # GitHub Actionsワークフロー(App Service用・旧)
│       └── deploy-functions.yml    # Azure Functions向けワークフロー
├── scripts/
│   ├── setup-runner.ps1            # Self-hosted Runner起動スクリプト
│   ├── cleanup-runner.ps1          # Runnerクリーンアップスクリプト
│   ├── create-index.ps1            # AI Searchインデックス作成
│   ├── create-datasource.ps1       # データソース作成
│   └── create-indexer.ps1          # インデクサー作成
├── src/                            # 旧アーキテクチャ(App Service)
│   ├── app.py                      # Flaskアプリケーション
│   └── templates/
│       └── index.html              # チャットUI
├── static/                         # Functions用静的ファイル
│   └── index.html                  # チャットUI(Functions向け)
├── docs/
│   ├── step01-setup-environment.md # Step 1: 環境準備
│   ├── step02-data-preparation.md  # Step 2: データ準備
│   ├── step03-indexing.md          # Step 3: AI Searchインデックス作成
│   ├── step04-deploy-app.md        # Step 4: アプリケーションデプロイ
│   └── step05-testing.md           # Step 5: テストと運用
├── function_app.py                 # Azure Functions アプリケーション(v2)
├── host.json                       # Functions ホスト設定
├── local.settings.json             # ローカル開発設定
├── .funcignore                     # デプロイ除外ファイル
├── .env.sample                     # 環境変数サンプル
├── .gitignore
├── requirements.txt                # Python依存関係
├── LICENSE
└── README.md                       # このファイル
```

## 🚀 クイックスタート

### 前提条件

以下のリポジトリを完了していること:

1. **[internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step)**
   - Virtual Network
   - Azure OpenAI (Private Endpoint)
   - Azure AI Search (Private Endpoint)
   - Azure Storage Account
   - Azure Functions (Flex Consumption, vNet統合)

2. **[internal_rag_Application_deployment_step_by_step](https://github.com/matakaha/internal_rag_Application_deployment_step_by_step)**
   - Key Vault
   - Self-hosted Runner用Subnet
   - GitHub Actions設定
   - Azure Container Registry (カスタムGitHub Runnerイメージ)

### 必要なツール

- Azure CLI (`az --version`)
- Azure Functions Core Tools v4 (`func --version`)
- Python 3.11以上
- Git
- GitHub アカウント

## 📖 学習ステップ

このリポジトリでは、以下の5つのステップで閉域RAGアプリケーションを構築します:

### [Step 1: 環境準備](docs/step01-setup-environment.md)

- GitHubリポジトリのフォーク/クローン
- 環境変数の設定
- Azure CLIでの接続確認

### [Step 2: データ準備](docs/step02-data-preparation.md)

- e-Govデータポータルのレッドリストダウンロード
- Blob Storageへのアップロード
- データ形式の確認

データソース: [e-Govデータポータル - レッドリスト/レッドデータブック](https://data.e-gov.go.jp/data/dataset/env_20140904_0456)

### [Step 3: AI Searchインデックス作成](docs/step03-indexing.md)

- Azure CLIを使用したインデックス定義
- Blob Storageからのインデクシング
- ベクトル検索の設定

### [Step 4: アプリケーションデプロイ](docs/step04-deploy-app.md)

- GitHub Secretsの設定
- アプリケーション設定の構成
- GitHub Actionsによる自動デプロイ

### [Step 5: テストと運用](docs/step05-testing.md)

- アプリケーションの動作確認
- RAG機能のテスト
- トラブルシューティング

## 🔧 ローカル開発

### 環境構築

```powershell
# リポジトリのクローン
git clone https://github.com/matakaha/internal_rag_Application_sample_repo.git
cd internal_rag_Application_sample_repo

# 仮想環境の作成
python -m venv .venv
.\.venv\Scripts\Activate.ps1

# 依存関係のインストール
pip install -r requirements.txt

# Azure Functions Core Toolsのインストール(未インストールの場合)
# https://learn.microsoft.com/ja-jp/azure/azure-functions/functions-run-local

# local.settings.jsonを編集してAzureリソース情報を設定
# または.envファイルを使用
cp .env.sample .env
```

### ローカル実行

```powershell
# Azure Functionsローカルランタイムで起動
func start

# または
python -m azure.functions.worker
```

ブラウザで `http://localhost:7071` にアクセス

### ローカルデバッグ

VS Codeでのデバッグ設定例 (`.vscode/launch.json`):

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

## 🔐 セキュリティ

### 認証・認可

- **Managed Identity**: App ServiceからAzure OpenAI/AI Searchへのアクセス
- **Private Endpoint**: すべてのAzureリソースは閉域網内
- **Key Vault**: シークレット管理

### ネットワークセキュリティ

- vNet統合によるプライベートネットワークアクセス
- NSGによる通信制御
- Private DNS Zonesによる名前解決

## 📊 使用技術

### フロントエンド
- HTML/CSS/JavaScript (Vanilla)

### バックエンド
- Python 3.11
- Azure Functions (Python v2 Programming Model)
- Azure Functions Extension Bundle 4.x

### Azure サービス
- Azure Functions (Flex Consumption Plan)
- Azure OpenAI Service
- Azure AI Search
- Azure Blob Storage
- Azure Key Vault
- Azure Virtual Network
- Azure Application Insights (監視)

### CI/CD
- GitHub Actions
- Azure Container Instances (Self-hosted Runner)

## 💰 コスト見積もり

月額概算コスト: ¥8,000〜18,000

| サービス | 構成 | 月額概算 |
|---------|------|---------|
| Azure Functions | Flex Consumption | ¥1,000〜3,000 |
| Azure OpenAI | GPT-4 従量課金 | ¥3,000〜10,000 |
| AI Search | Basic | ¥7,000 |
| Storage Account | Standard | ¥500 |
| Application Insights | 従量課金 | ¥500 |
| その他(vNet, DNS等) | - | ¥500 |

> 💡 **Flex Consumptionの利点**: 
> - アイドル時はほぼコストゼロ
> - 実行時間とメモリ使用量に応じた従量課金
> - App Service (Basic B1: ¥5,000/月)と比較して最大60%のコスト削減

> 💡 **ヒント**: 学習終了後はリソースグループを削除してコストを節約しましょう!

## 🛠️ トラブルシューティング

### よくある問題

#### 1. デプロイに失敗する

**症状**: GitHub Actionsでデプロイが失敗

**確認事項**:
- Key Vaultにシークレットが正しく格納されているか
- GitHub Secretsが正しく設定されているか
- Self-hosted RunnerがvNet内で起動できているか

#### 2. アプリが起動しない

**症状**: App Serviceにアクセスできない

**確認事項**:
- App Serviceのログを確認
- 環境変数が正しく設定されているか
- Managed Identityの権限が付与されているか

#### 3. RAGが動作しない

**症状**: チャットで回答が返ってこない

**確認事項**:
- AI Searchのインデックスが作成されているか
- Azure OpenAIへの接続が成功しているか
- Private Endpoint経由でアクセスできているか

詳細は [Step 5: テストと運用](docs/step05-testing.md#トラブルシューティング) を参照してください。

## 🤝 コントリビューション

改善提案やバグ報告は Issue または Pull Request でお願いします。

### 開発ガイドライン

1. 初学者にもわかりやすいコードとコメント
2. ステップバイステップで理解できるドキュメント
3. セキュリティベストプラクティスの遵守
4. 閉域ネットワーク環境での動作保証

## 📄 ライセンス

MIT License - 詳細は [LICENSE](LICENSE) を参照してください。

## 🔗 関連リンク

### 前提リポジトリ
- [internal_rag_step_by_step](https://github.com/matakaha/internal_rag_step_by_step) - 閉域RAG環境構築
- [internal_rag_Application_deployment_step_by_step](https://github.com/matakaha/internal_rag_Application_deployment_step_by_step) - CI/CD構築

### Azure ドキュメント
- [Azure App Service](https://learn.microsoft.com/ja-jp/azure/app-service/)
- [Azure OpenAI Service](https://learn.microsoft.com/ja-jp/azure/ai-services/openai/)
- [Azure AI Search](https://learn.microsoft.com/ja-jp/azure/search/)
- [GitHub Actions for Azure](https://learn.microsoft.com/ja-jp/azure/developer/github/github-actions)

### データソース
- [e-Govデータポータル - レッドリスト/レッドデータブック](https://data.e-gov.go.jp/data/dataset/env_20140904_0456)

---

**Made with ❤️ for learning Azure RAG systems**
