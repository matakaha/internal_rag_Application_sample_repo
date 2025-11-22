/**
 * 閉域RAGチャットアプリケーション - フロントエンド
 * Azure App Service上で動作する静的ファイルサーバー
 * バックエンドAPIはAzure Functionsで提供
 */

const express = require('express');
const path = require('path');

const app = express();
const port = process.env.PORT || 8000;

// 静的ファイル配信の設定
app.use(express.static(path.join(__dirname, 'public')));

// 静的ファイル配信の設定
app.use(express.static(path.join(__dirname, 'public')));

// ルート定義
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
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
