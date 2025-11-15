#!/bin/bash
# Azure App Service Startup Script

echo "Starting RAG Application..."

# Gunicornでアプリケーションを起動
gunicorn --bind=0.0.0.0:8000 --workers=4 --timeout=600 --access-logfile '-' --error-logfile '-' src.app:app
