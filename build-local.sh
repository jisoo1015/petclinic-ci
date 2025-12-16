#!/bin/bash

# ========================================
# PetClinic 로컬 빌드 스크립트 (WEB + WAS)
# ========================================

set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 환경 변수
AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID="723165663216"
ECR_WEB_REPO="petclinic-3tier-dev-web"
ECR_WAS_REPO="petclinic-3tier-dev-was"
IMAGE_TAG="${2:-latest}"

ECR_WEB_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_WEB_REPO}"
ECR_WAS_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_WAS_REPO}"

# 사용법 표시
show_usage() {
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}  PetClinic Local Build Script${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo ""
    echo "Usage: $0 <target> [tag]"
    echo ""
    echo "Targets:"
    echo "  web     - Build WEB only (Nginx)"
    echo "  was     - Build WAS only (Spring Boot)"
    echo "  all     - Build both WEB and WAS"
    echo ""
    echo "Tag: (optional, default: latest)"
    echo ""
    echo "Examples:"
    echo "  $0 web              # Build WEB with 'latest' tag"
    echo "  $0 was v1.0.0       # Build WAS with 'v1.0.0' tag"
    echo "  $0 all build-123    # Build both with 'build-123' tag"
    echo ""
    exit 1
}

# 인자 확인
if [ $# -lt 1 ]; then
    show_usage
fi

TARGET="$1"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  PetClinic Local Build${NC}"
echo -e "${BLUE}======================================${NC}"
echo -e "Target: ${YELLOW}${TARGET}${NC}"
echo -e "Tag:    ${YELLOW}${IMAGE_TAG}${NC}"
echo ""

# WEB 빌드 함수
build_web() {
    echo -e "${GREEN}[WEB] Building Nginx Frontend...${NC}"

    # 파일 확인
    if [ ! -d "web/startbootstrap-grayscale-gh-pages" ]; then
        echo -e "${RED}Error: web/startbootstrap-grayscale-gh-pages directory not found!${NC}"
        exit 1
    fi

    # Docker 빌드
    docker build -f Dockerfile.web \
        -t ${ECR_WEB_URI}:${IMAGE_TAG} \
        -t ${ECR_WEB_URI}:latest .

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}WEB image built successfully!${NC}"
        echo -e "Image: ${ECR_WEB_URI}:${IMAGE_TAG}"
    else
        echo -e "${RED}WEB build failed!${NC}"
        exit 1
    fi
}

# WAS 빌드 함수
build_was() {
    echo -e "${GREEN}[WAS] Building Spring Boot Application...${NC}"

    # 파일 확인
    if [ ! -f "pom.xml" ]; then
        echo -e "${RED}Error: pom.xml not found!${NC}"
        exit 1
    fi

    # Docker 빌드
    docker build -f Dockerfile \
        -t ${ECR_WAS_URI}:${IMAGE_TAG} \
        -t ${ECR_WAS_URI}:latest .

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}WAS image built successfully!${NC}"
        echo -e "Image: ${ECR_WAS_URI}:${IMAGE_TAG}"
    else
        echo -e "${RED}WAS build failed!${NC}"
        exit 1
    fi
}

# ECR 로그인 함수
ecr_login() {
    echo -e "${GREEN}Logging in to Amazon ECR...${NC}"
    aws ecr get-login-password --region ${AWS_REGION} \
      | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}ECR login successful.${NC}"
    else
        echo -e "${RED}ECR login failed!${NC}"
        exit 1
    fi
}

# ECR 푸시 함수
push_to_ecr() {
    local TARGET=$1

    echo ""
    echo -e "${YELLOW}Do you want to push images to ECR? (y/n)${NC}"
    read -r RESPONSE

    if [[ "$RESPONSE" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        ecr_login

        if [ "$TARGET" == "web" ] || [ "$TARGET" == "all" ]; then
            echo -e "${GREEN}Pushing WEB image...${NC}"
            docker push ${ECR_WEB_URI}:${IMAGE_TAG}
            docker push ${ECR_WEB_URI}:latest
            echo -e "${GREEN}WEB image pushed successfully!${NC}"
        fi

        if [ "$TARGET" == "was" ] || [ "$TARGET" == "all" ]; then
            echo -e "${GREEN}Pushing WAS image...${NC}"
            docker push ${ECR_WAS_URI}:${IMAGE_TAG}
            docker push ${ECR_WAS_URI}:latest
            echo -e "${GREEN}WAS image pushed successfully!${NC}"
        fi
    fi
}

# 로컬 테스트 함수
test_local() {
    local TARGET=$1

    echo ""
    echo -e "${YELLOW}Do you want to test images locally? (y/n)${NC}"
    read -r RESPONSE

    if [[ "$RESPONSE" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        if [ "$TARGET" == "web" ]; then
            echo -e "${GREEN}Starting WEB container on port 8888...${NC}"
            docker run -d --name petclinic-web-test -p 8888:80 ${ECR_WEB_URI}:${IMAGE_TAG}

            echo -e "${GREEN}WEB container started. Test at: http://localhost:8888${NC}"
            echo -e "${BLUE}Health check: curl http://localhost:8888/health${NC}"
            echo -e "${YELLOW}Press Enter to stop and remove the test container...${NC}"
            read -r

            docker stop petclinic-web-test
            docker rm petclinic-web-test
            echo -e "${GREEN}WEB test container removed.${NC}"

        elif [ "$TARGET" == "was" ]; then
            echo -e "${GREEN}Starting WAS container on port 8080...${NC}"
            docker run -d --name petclinic-was-test -p 8080:8080 ${ECR_WAS_URI}:${IMAGE_TAG}

            echo -e "${GREEN}WAS container started. Test at: http://localhost:8080/petclinic${NC}"
            echo -e "${YELLOW}Note: RDS connection may fail in local test${NC}"
            echo -e "${YELLOW}Press Enter to stop and remove the test container...${NC}"
            read -r

            docker stop petclinic-was-test
            docker rm petclinic-was-test
            echo -e "${GREEN}WAS test container removed.${NC}"
        fi
    fi
}

# 메인 로직
case $TARGET in
    web)
        build_web
        test_local "web"
        push_to_ecr "web"
        ;;
    was)
        build_was
        test_local "was"
        push_to_ecr "was"
        ;;
    all)
        build_web
        echo ""
        build_was
        push_to_ecr "all"
        ;;
    *)
        echo -e "${RED}Invalid target: $TARGET${NC}"
        show_usage
        ;;
esac

echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${GREEN}     Build Complete!${NC}"
echo -e "${BLUE}======================================${NC}"

if [ "$TARGET" == "web" ] || [ "$TARGET" == "all" ]; then
    echo -e "WEB Image: ${ECR_WEB_URI}:${IMAGE_TAG}"
fi

if [ "$TARGET" == "was" ] || [ "$TARGET" == "all" ]; then
    echo -e "WAS Image: ${ECR_WAS_URI}:${IMAGE_TAG}"
fi

echo ""
echo -e "${YELLOW}Next Steps (if pushed to ECR):${NC}"
echo ""

if [ "$TARGET" == "web" ] || [ "$TARGET" == "all" ]; then
    echo -e "${BLUE}# Update WEB deployment:${NC}"
    echo -e "kubectl set image deployment/web web=${ECR_WEB_URI}:${IMAGE_TAG} -n petclinic"
    echo ""
fi

if [ "$TARGET" == "was" ] || [ "$TARGET" == "all" ]; then
    echo -e "${BLUE}# Update WAS deployment:${NC}"
    echo -e "kubectl set image deployment/was was=${ECR_WAS_URI}:${IMAGE_TAG} -n petclinic"
    echo ""
fi

echo -e "${BLUE}# Check rollout status:${NC}"
echo -e "kubectl rollout status deployment/web -n petclinic"
echo -e "kubectl rollout status deployment/was -n petclinic"
echo ""
echo -e "${BLUE}======================================${NC}"
