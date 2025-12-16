# PetClinic 3-Tier Application

WEB (Nginx) + WAS (Spring Boot) 통합 리포지토리

## 프로젝트 구조

```
petclinic-ci/
├── web/                                # WEB 컴포넌트 (Nginx)
│   ├── Dockerfile                      # Nginx 이미지 빌드
│   ├── README.md
│   └── static/                         # 정적 파일
│       ├── startbootstrap-grayscale-gh-pages/
│       └── image.png
│
├── was/                                # WAS 컴포넌트 (Spring Boot)
│   ├── Dockerfile                      # Spring Boot + Tomcat
│   ├── README.md
│   ├── pom.xml
│   └── src/
│
├── Jenkinsfile.unified                 # 통합 CI/CD 파이프라인
├── build-local.sh                      # 로컬 빌드 스크립트
├── README.md                           # 이 파일
├── README-MONOREPO.md                  # 상세 사용 가이드
└── SETUP-GUIDE.md                      # 단계별 설정 가이드
```

## 빠른 시작

### 로컬 빌드

```bash
# WEB만 빌드
./build-local.sh web

# WAS만 빌드
./build-local.sh was

# 둘 다 빌드
./build-local.sh all
```

### Jenkins CI/CD

```bash
# 코드 변경
vi web/static/startbootstrap-grayscale-gh-pages/index.html
# 또는
vi was/src/main/java/.../Controller.java

# Commit & Push
git add .
git commit -m "Update WEB or WAS"
git push origin main

# → Jenkins 자동 감지 및 빌드
#    web/ 변경 → WEB만 빌드
#    was/ 변경 → WAS만 빌드
```

## 워크플로

```
코드 변경 (web/ or was/)
   ↓
Git Push (petclinic-ci)
   ↓
Jenkins 자동 트리거
   ↓
변경 감지 (지능형)
   ├─ web/ 변경 → WEB만 빌드
   ├─ was/ 변경 → WAS만 빌드
   └─ 둘 다 변경 → 둘 다 빌드
   ↓
Docker 빌드 & ECR 푸시
   ├─ petclinic-3tier-dev-web:build-N
   └─ petclinic-3tier-dev-was:build-N
   ↓
Manifest 업데이트 (petclinic-manifests)
   ↓
K8s Deployment 업데이트
   ↓
Pod Rolling Update
```

## 관련 리포지토리

| 리포지토리 | 용도 | URL |
|-----------|------|-----|
| **petclinic-ci** | 소스 코드 (WEB + WAS) | https://github.com/jisoo1015/petclinic-ci |
| **petclinic-manifests** | K8s Manifest 파일 | https://github.com/jisoo1015/petclinic-manifests |

## 아키텍처

```
Internet
   │
   ▼
ALB (AWS Load Balancer)
   │
   ▼
WEB Pod (Nginx:80)
   ├─ /health → Health Check
   ├─ /petclinic → Proxy to WAS
   └─ / → Static Files
   │
   ▼
WAS Pod (Spring:8080)
   │
   ▼
RDS MySQL (petclinic DB)
```

## ECR 리포지토리

| 컴포넌트 | ECR Repository | 이미지 |
|---------|----------------|--------|
| WEB | petclinic-3tier-dev-web | Nginx + Static files |
| WAS | petclinic-3tier-dev-was | Spring Boot + Tomcat |

## 환경 정보

- **AWS Region**: ap-northeast-2
- **AWS Account ID**: 723165663216
- **EKS Cluster**: petclinic-dev-cluster
- **Namespace**: petclinic

## 문서

- [README-MONOREPO.md](README-MONOREPO.md) - 상세 사용법 및 트러블슈팅
- [SETUP-GUIDE.md](SETUP-GUIDE.md) - 단계별 초기 설정 가이드
- [web/README.md](web/README.md) - WEB 컴포넌트 상세
- [was/README.md](was/README.md) - WAS 컴포넌트 상세

## Jenkins 파이프라인 파라미터

| 파라미터 | 값 | 설명 |
|---------|-----|------|
| BUILD_TARGET | ALL / WEB / WAS | 빌드 대상 선택 |
| UPDATE_MANIFEST | true / false | Manifest 자동 업데이트 여부 |

## 개발 가이드

### WEB 개발

```bash
# 정적 파일 수정
vi web/static/startbootstrap-grayscale-gh-pages/index.html

# 로컬 테스트
./build-local.sh web

# Commit & Push
git add web/
git commit -m "Update frontend design"
git push origin main
```

### WAS 개발

```bash
# 소스 코드 수정
vi was/src/main/java/org/springframework/samples/petclinic/...

# 로컬 테스트
./build-local.sh was

# Commit & Push
git add was/
git commit -m "Fix API bug"
git push origin main
```

## 버전 관리

- **latest**: 항상 최신 빌드
- **build-N**: Jenkins 빌드 번호 (예: build-123)
- **custom**: 수동 빌드 시 사용자 정의 태그

## 라이선스

Spring PetClinic Sample Application
