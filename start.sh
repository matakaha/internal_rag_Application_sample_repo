#!/bin/bash
set -e

# Docker繝・・繝｢繝ｳ繧偵ヰ繝・け繧ｰ繝ｩ繧ｦ繝ｳ繝峨〒襍ｷ蜍・
echo "=== Starting Docker Daemon ==="
dockerd > /var/log/dockerd.log 2>&1 &

# Docker繝・・繝｢繝ｳ縺瑚ｵｷ蜍輔☆繧九∪縺ｧ蠕・ｩ・
echo "Waiting for Docker daemon to start..."
for i in {1..30}; do
    if docker info > /dev/null 2>&1; then
        echo "笨・Docker daemon is running"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "笶・Docker daemon failed to start"
        cat /var/log/dockerd.log
        exit 1
    fi
    sleep 1
done

# 繝・ヰ繝・げ諠・ｱ
echo "=== GitHub Runner Startup ==="
echo "Runner Name: ${RUNNER_NAME:-runner-$(hostname)}"
echo "Repository URL: ${RUNNER_REPOSITORY_URL}"
echo "Work Directory: ${RUNNER_WORK_DIRECTORY:-_work}"
echo "Labels: ${RUNNER_LABELS:-self-hosted}"

# 繝阪ャ繝医Ρ繝ｼ繧ｯ謗･邯壹ユ繧ｹ繝・
echo "=== Network Connectivity Test ==="
if curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://github.com | grep -q "200\|301\|302"; then
    echo "笨・GitHub.com is reachable"
else
    echo "笶・Cannot reach GitHub.com"
    echo "Testing DNS resolution..."
    nslookup github.com || echo "DNS resolution failed"
    exit 1
fi

# 蠢・育腸蠅・､画焚繝√ぉ繝・け
if [ -z "$RUNNER_TOKEN" ] || [ -z "$RUNNER_REPOSITORY_URL" ]; then
    echo "笶・Error: RUNNER_TOKEN and RUNNER_REPOSITORY_URL must be set"
    exit 1
fi

echo "=== Configuring GitHub Runner ==="
# runner繝ｦ繝ｼ繧ｶ繝ｼ縺ｨ縺励※螳溯｡・
su - runner -c "cd /actions-runner && ./config.sh \
    --url \"${RUNNER_REPOSITORY_URL}\" \
    --token \"${RUNNER_TOKEN}\" \
    --name \"${RUNNER_NAME:-runner-$(hostname)}\" \
    --work \"${RUNNER_WORK_DIRECTORY:-_work}\" \
    --labels \"${RUNNER_LABELS:-self-hosted}\" \
    --unattended \
    --replace"

echo "=== Starting GitHub Runner ==="
su - runner -c "cd /actions-runner && ./run.sh"
