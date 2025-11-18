/**
 * 閉域RAGチャットアプリケーション
 * Azure App Service上で動作する、閉域網でセキュアなRAGシステム (Node.js版)
 */

const express = require('express');
const path = require('path');
const { DefaultAzureCredential } = require('@azure/identity');
const { AzureOpenAI } = require('openai');
const { SearchClient, AzureKeyCredential } = require('@azure/search-documents');

const app = express();
const port = process.env.PORT || 8000;

// ミドルウェア
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// 環境変数から設定を取得
const AZURE_OPENAI_ENDPOINT = process.env.AZURE_OPENAI_ENDPOINT;
const AZURE_OPENAI_DEPLOYMENT = process.env.AZURE_OPENAI_DEPLOYMENT || 'gpt-4';
const AZURE_SEARCH_ENDPOINT = process.env.AZURE_SEARCH_ENDPOINT;
const AZURE_SEARCH_INDEX = process.env.AZURE_SEARCH_INDEX || 'redlist-index';
const AZURE_SEARCH_KEY = process.env.AZURE_SEARCH_KEY;

// Azure認証情報
const credential = new DefaultAzureCredential();

// Azure OpenAI クライアント初期化
let openaiClient;
async function getOpenAIClient() {
    if (!openaiClient) {
        const tokenProvider = async () => {
            const token = await credential.getToken('https://cognitiveservices.azure.com/.default');
            return token.token;
        };

        openaiClient = new AzureOpenAI({
            endpoint: AZURE_OPENAI_ENDPOINT,
            azureADTokenProvider: tokenProvider,
            apiVersion: '2024-02-01'
        });
    }
    return openaiClient;
}

// Azure AI Search クライアント初期化
const searchCredential = AZURE_SEARCH_KEY 
    ? new AzureKeyCredential(AZURE_SEARCH_KEY) 
    : credential;

const searchClient = new SearchClient(
    AZURE_SEARCH_ENDPOINT,
    AZURE_SEARCH_INDEX,
    searchCredential
);

/**
 * Azure AI Searchでドキュメントを検索
 * @param {string} query - 検索クエリ
 * @param {number} topK - 取得する上位k件
 * @returns {Promise<Array>} - 検索結果のリスト
 */
async function searchDocuments(query, topK = 3) {
    try {
        const searchResults = await searchClient.search(query, {
            top: topK,
            select: ['content', 'title', 'url']
        });

        const documents = [];
        for await (const result of searchResults.results) {
            documents.push({
                content: result.document.content || '',
                title: result.document.title || '',
                url: result.document.url || '',
                score: result.score || 0
            });
        }

        return documents;
    } catch (error) {
        console.error('Search error:', error);
        return [];
    }
}

/**
 * RAGを使用してレスポンスを生成
 * @param {string} userMessage - ユーザーのメッセージ
 * @param {Array} contextDocuments - コンテキストとなるドキュメント
 * @returns {Promise<string>} - 生成されたレスポンス
 */
async function generateResponse(userMessage, contextDocuments) {
    // コンテキストを構築
    const context = contextDocuments
        .map(doc => `【${doc.title}】\n${doc.content}\n出典: ${doc.url}`)
        .join('\n\n');

    // プロンプト構築
    const systemMessage = `あなたは親切なアシスタントです。
提供されたコンテキスト情報を基に、ユーザーの質問に正確に答えてください。
コンテキストに情報がない場合は、その旨を伝えてください。
回答の際は、参照した情報の出典も明記してください。`;

    const userPrompt = `コンテキスト:
${context}

質問: ${userMessage}

上記のコンテキストを参考に、質問に答えてください。`;

    try {
        const client = await getOpenAIClient();
        const response = await client.chat.completions.create({
            model: AZURE_OPENAI_DEPLOYMENT,
            messages: [
                { role: 'system', content: systemMessage },
                { role: 'user', content: userPrompt }
            ],
            temperature: 0.7,
            max_tokens: 800
        });

        return response.choices[0].message.content;
    } catch (error) {
        console.error('OpenAI error:', error);
        return `申し訳ございません。エラーが発生しました: ${error.message}`;
    }
}

// ルート定義

/**
 * メインページ
 */
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

/**
 * チャットAPIエンドポイント
 */
app.post('/api/chat', async (req, res) => {
    try {
        const { message: userMessage } = req.body;

        if (!userMessage) {
            return res.status(400).json({ error: 'メッセージが空です' });
        }

        // ドキュメント検索
        const documents = await searchDocuments(userMessage);

        // レスポンス生成
        const response = await generateResponse(userMessage, documents);

        res.json({
            response: response,
            sources: documents.map(doc => ({
                title: doc.title,
                url: doc.url
            }))
        });
    } catch (error) {
        console.error('Chat error:', error);
        res.status(500).json({ error: error.message });
    }
});

/**
 * ヘルスチェックエンドポイント
 */
app.get('/health', (req, res) => {
    res.json({ status: 'healthy' });
});

// サーバー起動
app.listen(port, '0.0.0.0', () => {
    console.log(`Server is running on http://0.0.0.0:${port}`);
});
