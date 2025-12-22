#!/bin/bash

# ========================================
# GitHub Push 스크립트
# ========================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  GitHub Push Script${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# 현재 상태 확인
echo -e "${YELLOW}Current Git Status:${NC}"
git status --short
echo ""

# 커밋 확인
COMMITS_AHEAD=$(git rev-list --count origin/main..HEAD)
echo -e "${YELLOW}Commits to push: ${COMMITS_AHEAD}${NC}"
git log --oneline origin/main..HEAD
echo ""

# GitHub Personal Access Token 입력
echo -e "${YELLOW}GitHub Personal Access Token을 입력하세요:${NC}"
echo -e "${YELLOW}(토큰이 없다면: https://github.com/settings/tokens)${NC}"
read -s GITHUB_TOKEN
echo ""

if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}Error: Token이 입력되지 않았습니다.${NC}"
    exit 1
fi

# Push
echo -e "${GREEN}Pushing to GitHub...${NC}"
git push https://jisoo1015:${GITHUB_TOKEN}@github.com/jisoo1015/petclinic-ci.git main

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${BLUE}======================================${NC}"
    echo -e "${GREEN}     Push Successful!${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "1. Jenkins에서 빌드 확인:"
    echo -e "   ${BLUE}http://43.203.247.182:8080/job/petclinic-unified-pipeline/${NC}"
    echo ""
    echo -e "2. 수동 빌드 트리거:"
    echo -e "   Build with Parameters → BUILD_TARGET: ALL → Build"
    echo ""
else
    echo -e "${RED}Push failed!${NC}"
    exit 1
fi
