# Jenkins Jobs 구성 가이드

## 개요

PetClinic 3-tier 애플리케이션을 위한 별도의 Jenkins Job 구성입니다.
- **WEB Job**: Nginx 기반 프론트엔드 빌드 및 ECR 푸시
- **WAS Job**: Spring Boot 애플리케이션 빌드 및 ECR 푸시
- **배포**: ArgoCD가 Manifest 리포지토리를 모니터링하여 자동 배포

---

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    GitOps Workflow                           │
└─────────────────────────────────────────────────────────────┘

Code Repository (petclinic-ci)
├── web/          → Jenkins Job: petclinic-web
│   ├── Dockerfile
│   └── static/
└── was/          → Jenkins Job: petclinic-was
    ├── Dockerfile
    ├── pom.xml
    └── src/

        ↓ (Git Push)

GitHub Webhook / Poll SCM

        ↓

Jenkins CI Pipeline (Build & Push only)
├── Build Docker Image
├── Push to ECR
│   ├── 723165663216.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-3tier-dev-web
│   └── 723165663216.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-3tier-dev-was
└── Update Manifest Repository
    └── https://github.com/jisoo1015/petclinic-manifests.git

        ↓

ArgoCD CD Pipeline (Deploy)
├── Detect Manifest Change
├── Sync with EKS Cluster
└── Rolling Update Deployment
    ├── web deployment
    └── was deployment
```

---

## Jenkins Job 생성

### 1. WEB Job 생성

#### Job 설정
```
Job Name: petclinic-web
Type: Pipeline
```

#### Pipeline 설정
```groovy
Pipeline script from SCM:
  SCM: Git
  Repository URL: https://github.com/jisoo1015/petclinic-ci.git
  Credentials: jisoo1015 (GitHub PAT)
  Branch: */main (또는 */master)
  Script Path: Jenkinsfile.web
```

#### Build Triggers
**옵션 1: GitHub Webhook (권장)**
```
✓ GitHub hook trigger for GITScm polling
```

**옵션 2: Poll SCM (대안)**
```
✓ Poll SCM
  Schedule: H/5 * * * *  (5분마다 체크)
```

#### Parameters (자동 설정됨)
- `IMAGE_TAG`: Docker 이미지 태그 (기본값: build-${BUILD_NUMBER})
- `UPDATE_MANIFEST`: Manifest 업데이트 여부 (기본값: true)

---

### 2. WAS Job 생성

#### Job 설정
```
Job Name: petclinic-was
Type: Pipeline
```

#### Pipeline 설정
```groovy
Pipeline script from SCM:
  SCM: Git
  Repository URL: https://github.com/jisoo1015/petclinic-ci.git
  Credentials: jisoo1015 (GitHub PAT)
  Branch: */main (또는 */master)
  Script Path: Jenkinsfile.was
```

#### Build Triggers
**옵션 1: GitHub Webhook (권장)**
```
✓ GitHub hook trigger for GITScm polling
```

**옵션 2: Poll SCM (대안)**
```
✓ Poll SCM
  Schedule: H/5 * * * *  (5분마다 체크)
```

#### Parameters (자동 설정됨)
- `IMAGE_TAG`: Docker 이미지 태그 (기본값: build-${BUILD_NUMBER})
- `UPDATE_MANIFEST`: Manifest 업데이트 여부 (기본값: true)

---

## GitHub Webhook 설정

### Jenkins URL 확인
```bash
# Jenkins 서버 URL 확인
echo "http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080/github-webhook/"
```

### GitHub 리포지토리 설정
1. GitHub 리포지토리 이동: https://github.com/jisoo1015/petclinic-ci
2. Settings → Webhooks → Add webhook
3. 설정:
   ```
   Payload URL: http://<JENKINS_PUBLIC_IP>:8080/github-webhook/
   Content type: application/json
   Secret: (비워둠)
   Events: Just the push event
   Active: ✓
   ```

### Webhook 테스트
```bash
# 최근 webhook 전송 확인
curl -X GET \
  -H "Authorization: token YOUR_GITHUB_TOKEN" \
  https://api.github.com/repos/jisoo1015/petclinic-ci/hooks
```

---

## 사용 시나리오

### Scenario 1: WEB 코드만 수정
```bash
# web/ 디렉터리 파일 수정
vim web/static/startbootstrap-grayscale-gh-pages/index.html

# Commit & Push
git add web/
git commit -m "Update web frontend UI"
git push origin main
```

**결과:**
- `petclinic-web` Job만 자동 트리거
- WEB 이미지만 빌드하여 ECR 푸시
- Manifest 리포지토리의 `04-web-deployment.yaml` 업데이트
- ArgoCD가 변경 감지하여 web deployment만 업데이트

---

### Scenario 2: WAS 코드만 수정
```bash
# was/ 디렉터리 파일 수정
vim was/src/main/java/org/springframework/samples/petclinic/owner/OwnerController.java

# Commit & Push
git add was/
git commit -m "Add new API endpoint"
git push origin main
```

**결과:**
- `petclinic-was` Job만 자동 트리거
- WAS 이미지만 빌드하여 ECR 푸시 (Maven 빌드 포함)
- Manifest 리포지토리의 `02-was-deployment.yaml` 업데이트
- ArgoCD가 변경 감지하여 was deployment만 업데이트

---

### Scenario 3: 수동 빌드 (특정 태그)
```bash
# Jenkins UI에서
Job: petclinic-web
→ Build with Parameters
→ IMAGE_TAG: v1.0.0
→ UPDATE_MANIFEST: true
→ Build
```

**결과:**
- 특정 태그(`v1.0.0`)로 이미지 빌드
- ECR에 `petclinic-3tier-dev-web:v1.0.0` 푸시
- Manifest 업데이트하여 ArgoCD 배포

---

## Pipeline 단계 설명

### WEB Pipeline (Jenkinsfile.web)
```
1. Checkout Source
   └── Git 리포지토리 체크아웃 및 커밋 해시 저장

2. Verify WEB Files
   └── web/ 디렉터리 구조 및 파일 검증

3. Login to ECR
   └── AWS ECR 인증 (aws ecr get-login-password)

4. Build WEB Image
   └── Nginx 기반 Docker 이미지 빌드
       - 태그: build-N, latest

5. Push to ECR
   └── ECR에 이미지 푸시
       - petclinic-3tier-dev-web:build-N
       - petclinic-3tier-dev-web:latest

6. Update Manifest for ArgoCD
   └── Manifest 리포지토리 업데이트
       - 04-web-deployment.yaml 이미지 태그 변경
       - Git commit & push
```

### WAS Pipeline (Jenkinsfile.was)
```
1. Checkout Source
   └── Git 리포지토리 체크아웃 및 커밋 해시 저장

2. Verify WAS Files
   └── was/ 디렉터리 구조 및 파일 검증

3. Login to ECR
   └── AWS ECR 인증

4. Build WAS Image
   └── Spring Boot 애플리케이션 빌드
       - Maven 빌드 (multi-stage)
       - Tomcat에 WAR 배포
       - 태그: build-N, latest

5. Push to ECR
   └── ECR에 이미지 푸시
       - petclinic-3tier-dev-was:build-N
       - petclinic-3tier-dev-was:latest

6. Update Manifest for ArgoCD
   └── Manifest 리포지토리 업데이트
       - 02-was-deployment.yaml 이미지 태그 변경
       - Git commit & push
```

---

## 로컬 테스트

### WEB 로컬 빌드
```bash
cd /home/ec2-user/eks-infra/petclinic-ci

# ECR URI 설정
ECR_WEB_URI="723165663216.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-3tier-dev-web"
IMAGE_TAG="local-test"

# 빌드
docker build -f web/Dockerfile -t ${ECR_WEB_URI}:${IMAGE_TAG} web/

# 테스트 실행
docker run -d -p 8080:80 --name web-test ${ECR_WEB_URI}:${IMAGE_TAG}
curl http://localhost:8080/health

# 정리
docker stop web-test
docker rm web-test
```

### WAS 로컬 빌드
```bash
cd /home/ec2-user/eks-infra/petclinic-ci

# ECR URI 설정
ECR_WAS_URI="723165663216.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-3tier-dev-was"
IMAGE_TAG="local-test"

# 빌드 (시간 소요됨 - Maven 빌드)
docker build -f was/Dockerfile -t ${ECR_WAS_URI}:${IMAGE_TAG} was/

# 테스트 실행
docker run -d -p 8009:8080 --name was-test ${ECR_WAS_URI}:${IMAGE_TAG}
curl http://localhost:8009/petclinic/

# 정리
docker stop was-test
docker rm was-test
```

---

## Credentials 설정

Jenkins에 GitHub Personal Access Token 등록되어 있어야 합니다.

### 확인
```bash
# Jenkins credentials 확인
sudo cat /var/lib/jenkins/credentials.xml | grep -A 5 "jisoo1015"
```

### 필요한 권한
GitHub PAT에 필요한 권한:
- `repo` (전체 리포지토리 접근)
- `admin:repo_hook` (webhook 관리)

---

## 트러블슈팅

### 1. ECR 푸시 실패
```bash
# ECR 리포지토리 존재 확인
aws ecr describe-repositories --region ap-northeast-2 | grep petclinic-3tier-dev

# IAM 권한 확인 (Jenkins 인스턴스 역할)
aws sts get-caller-identity
```

### 2. Manifest 업데이트 실패
```bash
# GitHub credentials 확인
# Jenkins UI → Credentials → jisoo1015 확인

# Manifest 리포지토리 접근 테스트
git clone https://github.com/jisoo1015/petclinic-manifests.git /tmp/test
```

### 3. Jenkins Job이 자동 트리거되지 않음
```bash
# Webhook 설정 확인
curl -H "Authorization: token YOUR_TOKEN" \
  https://api.github.com/repos/jisoo1015/petclinic-ci/hooks

# Jenkins 로그 확인
sudo tail -f /var/log/jenkins/jenkins.log

# Poll SCM으로 대체 사용
```

### 4. Docker 빌드 실패
```bash
# Jenkins 사용자의 Docker 권한 확인
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# Dockerfile 문법 확인
docker build -f web/Dockerfile web/
docker build -f was/Dockerfile was/
```

---

## ArgoCD 설정 (참고)

Jenkins가 Manifest를 업데이트하면 ArgoCD가 이를 감지하여 배포합니다.

### ArgoCD Application 예시
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: petclinic-web
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/jisoo1015/petclinic-manifests.git
    targetRevision: main
    path: k8s-manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: petclinic
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### 배포 확인
```bash
# ArgoCD CLI로 확인
argocd app list
argocd app get petclinic-web
argocd app sync petclinic-web
```

---

## 요약

| 항목 | 내용 |
|------|------|
| **Jenkins 역할** | Build → Push to ECR → Update Manifest |
| **ArgoCD 역할** | Detect Manifest Change → Deploy to K8s |
| **WEB Job** | Nginx 프론트엔드 빌드 및 푸시 |
| **WAS Job** | Spring Boot 애플리케이션 빌드 및 푸시 |
| **트리거** | GitHub Webhook 또는 Poll SCM |
| **배포 방식** | GitOps (Manifest 기반) |

---

## 다음 단계

1. ✅ Jenkinsfile.web 생성 완료
2. ✅ Jenkinsfile.was 생성 완료
3. ⬜ Jenkins에 두 개의 Job 생성
4. ⬜ GitHub Webhook 설정
5. ⬜ ArgoCD Application 생성
6. ⬜ 테스트 배포 실행
