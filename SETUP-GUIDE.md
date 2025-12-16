# PetClinic Mono-Repo 설정 가이드

## 현재 상황 정리

### 리포지토리 구조

```
https://github.com/jisoo1015/petclinic-ci
├── Dockerfile              # WAS (Spring Boot)
├── Dockerfile.web          # WEB (Nginx)  ← 새로 추가
├── Jenkinsfile             # WAS 전용 (기존)
├── Jenkinsfile.unified     # WEB + WAS 통합 ← 새로 추가
├── pom.xml                 # WAS Maven
├── src/                    # WAS 소스
└── web/                    # WEB 정적 파일 ← 새로 추가
    ├── startbootstrap-grayscale-gh-pages/
    └── image.png

https://github.com/jisoo1015/petclinic-manifests
└── k8s-manifests/
    ├── 00-namespace.yaml
    ├── 01-nginx-configmap.yaml
    ├── 02-was-deployment.yaml    ← Jenkins가 자동 업데이트
    ├── 03-was-service.yaml
    ├── 04-web-deployment.yaml    ← Jenkins가 자동 업데이트
    ├── 05-web-service.yaml
    └── 06-alb-ingress.yaml
```

---

## Step 1: petclinic-ci 리포지토리 업데이트

### 1.1 WEB 파일 추가

```bash
cd /home/ec2-user/eks-infra/petclinic-ci

# web 디렉토리 확인
ls -la web/

# 새로 생성된 파일 확인
ls -la Dockerfile.web
ls -la Jenkinsfile.unified
ls -la build-local.sh
ls -la README-MONOREPO.md
```

### 1.2 Git Commit & Push

```bash
cd /home/ec2-user/eks-infra/petclinic-ci

# Git 상태 확인
git status

# 파일 추가
git add web/
git add Dockerfile.web
git add Jenkinsfile.unified
git add build-local.sh
git add README-MONOREPO.md
git add SETUP-GUIDE.md

# Commit
git commit -m "Add WEB frontend and unified CI/CD pipeline

- Add web/ directory with static files
- Add Dockerfile.web for Nginx-based frontend
- Add Jenkinsfile.unified for WEB+WAS integrated pipeline
- Add build-local.sh for local builds
- Add comprehensive documentation

This enables mono-repo management for WEB and WAS."

# Push to GitHub
git push origin main
```

**만약 push 권한 오류가 발생하면:**

```bash
# Personal Access Token 사용
git remote set-url origin https://<USERNAME>:<TOKEN>@github.com/jisoo1015/petclinic-ci.git

# 다시 push
git push origin main
```

---

## Step 2: Jenkins 설정

### 2.1 GitHub Personal Access Token 생성

Jenkins가 `petclinic-manifests`를 업데이트하려면 GitHub 토큰이 필요합니다.

1. GitHub → Settings → Developer settings
2. Personal access tokens → Tokens (classic)
3. **Generate new token (classic)**
4. 권한 선택:
   - [x] `repo` (전체)
5. **Generate token**
6. 토큰 복사 (한 번만 보여줌!)

### 2.2 Jenkins Credentials 추가

```
Jenkins → Credentials → System → Global credentials → Add Credentials

Kind: Username with password
Username: jisoo1015  (GitHub 사용자명)
Password: <Personal Access Token>
ID: github-credentials
Description: GitHub Access Token for Manifest Updates
```

### 2.3 기존 Jenkins Job 수정 (또는 새로 생성)

#### 옵션 A: 기존 Job 수정

기존 WAS 전용 Job이 있다면:

```
Jenkins → petclinic-ci Job → Configure

Script Path: Jenkinsfile → Jenkinsfile.unified 로 변경

Save
```

#### 옵션 B: 새 Job 생성 (권장)

```
1. New Item 클릭
2. Item name: petclinic-unified-pipeline
3. Type: Pipeline
4. OK

설정:
  General:
    - [x] This project is parameterized
    - Add Parameter → Choice Parameter
      - Name: BUILD_TARGET
      - Choices: ALL\nWEB\nWAS
      - Description: 빌드 대상 선택
    - Add Parameter → Boolean Parameter
      - Name: UPDATE_MANIFEST
      - Default: true
      - Description: Manifest 리포지토리 자동 업데이트

  Build Triggers:
    - [x] Poll SCM: H/5 * * * *  (5분마다 체크)
    - 또는 GitHub hook trigger

  Pipeline:
    - Definition: Pipeline script from SCM
    - SCM: Git
    - Repository URL: https://github.com/jisoo1015/petclinic-ci.git
    - Credentials: github-credentials
    - Branch: */main
    - Script Path: Jenkinsfile.unified

Save
```

### 2.4 Jenkins 서버 kubectl 설정

Jenkins가 K8s 클러스터에 접근할 수 있어야 합니다.

```bash
# Jenkins 사용자로 전환
sudo su - jenkins

# kubeconfig 설정
aws eks update-kubeconfig --name petclinic-dev-cluster --region ap-northeast-2

# 테스트
kubectl get nodes
kubectl get pods -n petclinic

exit
```

**또는 kubeconfig 복사:**

```bash
sudo mkdir -p /var/lib/jenkins/.kube
sudo cp ~/.kube/config /var/lib/jenkins/.kube/config
sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube
```

### 2.5 Jenkins 서버 Docker 권한

```bash
# Jenkins 사용자를 docker 그룹에 추가
sudo usermod -aG docker jenkins

# Jenkins 재시작
sudo systemctl restart jenkins

# 확인
sudo su - jenkins
docker ps
exit
```

---

## Step 3: Jenkinsfile.unified 수정 (Manifest 푸시 인증)

현재 Jenkinsfile.unified는 manifest 푸시 시 인증이 필요합니다.

### 3.1 Jenkinsfile.unified 업데이트

[Jenkinsfile.unified](../petclinic-ci/Jenkinsfile.unified)의 `Update Kubernetes Manifests` 단계를 수정:

```groovy
stage('Update Kubernetes Manifests') {
    when {
        expression { params.UPDATE_MANIFEST == true }
    }
    steps {
        withCredentials([usernamePassword(
            credentialsId: 'github-credentials',
            usernameVariable: 'GIT_USER',
            passwordVariable: 'GIT_TOKEN'
        )]) {
            script {
                // ... 기존 코드 ...

                sh '''
                cd $MANIFEST_DIR

                # ... 기존 sed 명령어들 ...

                # Commit & Push with credentials
                if [ -n "$(git status --porcelain)" ]; then
                    git add .
                    git commit -m "Update image tags to build-${BUILD_NUMBER}

                    - WEB: ${BUILD_WEB}
                    - WAS: ${BUILD_WAS}
                    - Commit: ${GIT_COMMIT_SHORT}"

                    # Push with authentication
                    git push https://${GIT_USER}:${GIT_TOKEN}@github.com/jisoo1015/petclinic-manifests.git main

                    echo "Manifest updated and pushed successfully"
                else
                    echo "No changes to manifest files"
                fi
                '''
            }
        }
    }
}
```

---

## Step 4: 첫 빌드 테스트

### 4.1 수동 빌드

```
Jenkins → petclinic-unified-pipeline → Build with Parameters

BUILD_TARGET: ALL
UPDATE_MANIFEST: true

Build 클릭
```

### 4.2 빌드 로그 확인

```
Jenkins → Build History → #1 → Console Output

확인 사항:
✓ Checkout Source
✓ Detect Changes
✓ Login to ECR
✓ Build & Push WEB
✓ Build & Push WAS
✓ Update Manifests
✓ Deploy to K8s
✓ Verify Deployment
```

### 4.3 배포 확인

```bash
# Pod 상태
kubectl get pods -n petclinic -w

# Deployment 이미지 확인
kubectl describe deployment web -n petclinic | grep Image
kubectl describe deployment was -n petclinic | grep Image

# ECR 이미지 확인
aws ecr describe-images \
  --repository-name petclinic-3tier-dev-web \
  --region ap-northeast-2 \
  --query 'sort_by(imageDetails,& imagePushedAt)[-3:]'

aws ecr describe-images \
  --repository-name petclinic-3tier-dev-was \
  --region ap-northeast-2 \
  --query 'sort_by(imageDetails,& imagePushedAt)[-3:]'

# Manifest 리포지토리 확인
git clone https://github.com/jisoo1015/petclinic-manifests.git /tmp/manifests
grep "image:" /tmp/manifests/k8s-manifests/04-web-deployment.yaml
grep "image:" /tmp/manifests/k8s-manifests/02-was-deployment.yaml
```

---

## Step 5: 자동 트리거 설정 (Webhook)

### 5.1 Jenkins URL 확인

```bash
# EC2 Public IP
curl ifconfig.me

# Jenkins URL
http://<PUBLIC-IP>:8080
```

### 5.2 보안 그룹 설정

EC2 Security Group에서:
- Inbound Rules → Add Rule
- Type: Custom TCP
- Port: 8080
- Source: GitHub IP 대역 (또는 0.0.0.0/0, 테스트용)

### 5.3 GitHub Webhook 설정

```
GitHub → petclinic-ci → Settings → Webhooks → Add webhook

Payload URL: http://<JENKINS-PUBLIC-IP>:8080/github-webhook/
Content type: application/json
Secret: (비워둠)
Events: Just the push event
Active: ✓

Add webhook
```

### 5.4 Webhook 테스트

```bash
# 코드 변경
cd /home/ec2-user/eks-infra/petclinic-ci
echo "<!-- Test -->" >> web/startbootstrap-grayscale-gh-pages/index.html

git add .
git commit -m "Test webhook trigger"
git push origin main

# Jenkins에서 자동 빌드 시작되는지 확인
# → WEB만 변경되었으므로 WEB만 빌드됨
```

---

## Step 6: 로컬 빌드 테스트

### 6.1 WEB만 빌드

```bash
cd /home/ec2-user/eks-infra/petclinic-ci

./build-local.sh web

# 로컬 테스트 → y
# ECR 푸시 → y (또는 n)
```

### 6.2 WAS만 빌드

```bash
./build-local.sh was
```

### 6.3 둘 다 빌드

```bash
./build-local.sh all build-manual-1
```

---

## 전체 워크플로 요약

### 시나리오: WEB 코드 변경

```bash
# 1. 코드 변경
cd /home/ec2-user/eks-infra/petclinic-ci
echo "Updated" >> web/startbootstrap-grayscale-gh-pages/index.html

# 2. Commit & Push
git add web/
git commit -m "Update homepage"
git push origin main

# 3. Jenkins 자동 트리거 (Webhook)
# → Detect Changes: web/ 변경 감지
# → Build WEB only
# → Push to ECR: petclinic-3tier-dev-web:build-N
# → Update petclinic-manifests/k8s-manifests/04-web-deployment.yaml
# → kubectl set image deployment/web ...
# → Pod Rolling Update

# 4. 확인
kubectl get pods -n petclinic -l tier=web -w
kubectl describe deployment web -n petclinic | grep Image:

# 결과
# WAS는 변경되지 않음
# WEB Pod만 새 이미지로 업데이트됨
```

---

## 트러블슈팅

### 1. Manifest Push 실패

**증상:**
```
fatal: could not read Username for 'https://github.com'
```

**해결:**
```bash
# Jenkins Credentials 확인
Jenkins → Credentials → github-credentials

# Jenkinsfile.unified에서 withCredentials 사용 확인
```

### 2. 변경 감지 안됨

**증상:**
```
WEB만 변경했는데 WAS도 빌드됨
```

**해결:**
```bash
# BUILD_TARGET 파라미터로 강제 지정
Jenkins → Build with Parameters → BUILD_TARGET: WEB

# 또는 변경 감지 로직 확인
git diff --name-only HEAD~1 HEAD
```

### 3. ECR 푸시 권한 오류

**증상:**
```
denied: User: ... is not authorized to perform: ecr:InitiateLayerUpload
```

**해결:**
```bash
# Jenkins 서버 IAM Role 확인
aws sts get-caller-identity

# ECR 권한 확인
aws ecr describe-repositories --region ap-northeast-2
```

### 4. kubectl 권한 오류

**증상:**
```
error: You must be logged in to the server (Unauthorized)
```

**해결:**
```bash
# Jenkins 사용자 kubeconfig 확인
sudo su - jenkins
kubectl config view
aws eks update-kubeconfig --name petclinic-dev-cluster --region ap-northeast-2
exit
```

---

## 다음 단계 (선택사항)

### 1. ArgoCD 도입 (GitOps)

Manifest 변경 시 자동 동기화:

```bash
# ArgoCD 설치
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Application 생성
argocd app create petclinic \
  --repo https://github.com/jisoo1015/petclinic-manifests.git \
  --path k8s-manifests \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace petclinic \
  --sync-policy automated
```

### 2. Slack 알림

Jenkins에 Slack 플러그인 설치:

```groovy
post {
    success {
        slackSend(
            color: 'good',
            message: "Build Success: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
        )
    }
}
```

### 3. 자동 테스트

Jenkinsfile에 테스트 단계 추가:

```groovy
stage('Run Tests') {
    when {
        expression { env.BUILD_WAS == 'true' }
    }
    steps {
        sh './mvnw test'
    }
}
```

---

## 체크리스트

### 초기 설정

- [ ] petclinic-ci에 WEB 파일 추가 및 Push
- [ ] GitHub Personal Access Token 생성
- [ ] Jenkins Credentials 추가 (github-credentials)
- [ ] Jenkins Job 생성 (petclinic-unified-pipeline)
- [ ] Jenkins kubectl 설정
- [ ] Jenkins Docker 권한 설정
- [ ] Jenkinsfile.unified의 manifest 푸시 인증 추가

### 첫 빌드 테스트

- [ ] 수동 빌드 (BUILD_TARGET: ALL)
- [ ] ECR 이미지 푸시 확인
- [ ] Manifest 리포지토리 업데이트 확인
- [ ] K8s Pod 배포 확인

### 자동화 설정

- [ ] GitHub Webhook 추가
- [ ] Webhook 트리거 테스트
- [ ] 변경 감지 로직 테스트 (WEB만, WAS만)

### 검증

- [ ] WEB 코드 변경 → WEB만 빌드/배포
- [ ] WAS 코드 변경 → WAS만 빌드/배포
- [ ] 둘 다 변경 → 둘 다 빌드/배포

---

## 완료!

이제 `petclinic-ci` 하나의 리포지토리에서:
- **WEB** (Nginx + Static files)
- **WAS** (Spring Boot + Tomcat)

두 컴포넌트를 효율적으로 관리하고, 변경 사항을 자동으로 감지하여 필요한 부분만 빌드/배포할 수 있습니다!

---

## 참고 문서

- [README-MONOREPO.md](README-MONOREPO.md) - 상세 사용법
- [Jenkinsfile.unified](Jenkinsfile.unified) - 통합 파이프라인
- [build-local.sh](build-local.sh) - 로컬 빌드 스크립트
