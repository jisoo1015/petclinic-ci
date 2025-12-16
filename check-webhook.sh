#!/bin/bash

# ========================================
# GitHub Webhook 확인 스크립트
# ========================================

REPO_OWNER="jisoo1015"
REPO_NAME="petclinic-ci"

echo "========================================"
echo "  GitHub Webhook 확인"
echo "========================================"
echo ""

# GitHub Personal Access Token 필요
echo "GitHub Personal Access Token을 입력하세요:"
read -s GITHUB_TOKEN

echo ""
echo "Checking webhooks for ${REPO_OWNER}/${REPO_NAME}..."
echo ""

# Webhooks 조회
curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/hooks | \
  jq -r '.[] | "ID: \(.id)\nURL: \(.config.url)\nEvents: \(.events | join(", "))\nActive: \(.active)\n---"'

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Webhook 조회 완료"
else
    echo ""
    echo "✗ Webhook 조회 실패 (토큰 확인 필요)"
fi
