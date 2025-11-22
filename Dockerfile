# Node.js 18 Alpine イメージを使用(軽量)
# GitHub ホストランナーはインターネットアクセスがあるため、Docker Hubから直接取得
FROM node:18-alpine

# 作業ディレクトリを設定
WORKDIR /app

# package.jsonとpackage-lock.jsonをコピー
COPY src/package*.json ./

# 依存関係をインストール
RUN npm ci --only=production

# アプリケーションコードをコピー
COPY src/ ./

# ポート8000を公開
EXPOSE 8000

# アプリケーションを起動
CMD ["npm", "start"]
