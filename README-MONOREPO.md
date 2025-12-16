# PetClinic 3-Tier Mono Repository

WEB (Nginx) + WAS (Spring Boot)를 하나의 리포지토리에서 관리하는 통합 CI/CD

## 리포지토리 구조

```
petclinic-ci/
├── Dockerfile                  # WAS용 Dockerfile (Spring Boot + Tomcat)
├── Dockerfile.web              # WEB용 Dockerfile (Nginx + Static files)
├── Jenkinsfile.unified         # 통합 CI/CD 파이프라인
├── pom.xml                     # WAS Maven 설정
├── src/                        # WAS 소스 코드 (Spring Boot)
│   ├── main/
│   └── test/
└── web/                        # WEB 정적 파일
    ├── startbootstrap-grayscale-gh-pages/
    │   ├── index.html
    │   ├── css/
    │   ├── js/
    │   └── assets/
    └── image.png
```

## 관련 리포지토리

| 리포지토리 | 용도 | URL |
|-----------|------|-----|
| **petclinic-ci** | 소스 코드 (WEB + WAS) | https://github.com/jisoo1015/petclinic-ci |
| **petclinic-manifests** | K8s Manifest 파일 | https://github.com/jisoo1015/petclinic-manifests |

## 워크플로

```
코드 변경 (WEB or WAS)
   ↓
Git Push to petclinic-ci
   ↓
Jenkins 트리거
   ↓
변경 감지 (WEB/WAS 구분)
   ↓
Docker 이미지 빌드
   ├─ WEB: Dockerfile.web → petclinic-3tier-dev-web
   └─ WAS: Dockerfile → petclinic-3tier-dev-was
   ↓
ECR 푸시
   ↓
petclinic-manifests 업데이트
   ├─ 04-web-deployment.yaml (WEB 변경 시)
   └─ 02-was-deployment.yaml (WAS 변경 시)
   ↓
K8s Deployment 업데이트
   ↓
Pod Rolling Update
```

## Jenkins 파이프라인 설정

### 1. Jenkins Job 생성

**Job 이름:** `petclinic-unified-pipeline`

**Pipeline 설정:**
- Definition: **Pipeline script from SCM**
- SCM: **Git**
- Repository URL: `https://github.com/jisoo1015/petclinic-ci.git`
- Credentials: GitHub Token
- Branch: `*/main`
- **Script Path:** `Jenkinsfile.unified`

### 2. 파이프라인 파라미터

| 파라미터 | 타입 | 기본값 | 설명 |
|---------|------|--------|------|
| BUILD_TARGET | Choice | ALL | `ALL`: WEB+WAS 모두<br>`WEB`: 웹만<br>`WAS`: WAS만 |
| UPDATE_MANIFEST | Boolean | true | Manifest 리포지토리 자동 업데이트 |

### 3. 변경 감지 로직

Jenkins가 자동으로 변경된 파일을 감지하여 빌드 대상을 결정합니다:

```bash
# WEB 변경 감지
web/ 디렉토리 변경 → WEB만 빌드

# WAS 변경 감지
src/, pom.xml, Dockerfile 변경 → WAS만 빌드

# 둘 다 변경
양쪽 모두 빌드

# BUILD_TARGET 파라미터로 강제 지정 가능
```

## 로컬 빌드 및 테스트

### WEB 빌드

```bash
cd /home/ec2-user/eks-infra/petclinic-ci

# WEB 이미지 빌드
docker build -f Dockerfile.web \
  -t 723165663216.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-3tier-dev-web:latest .

# 로컬 테스트
docker run -d --name web-test -p 8080:80 \
  723165663216.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-3tier-dev-web:latest

# 테스트
curl http://localhost:8080/health
curl http://localhost:8080/

# 정리
docker stop web-test && docker rm web-test
```

### WAS 빌드

```bash
# WAS 이미지 빌드
docker build -f Dockerfile \
  -t 723165663216.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-3tier-dev-was:latest .

# 로컬 테스트 (RDS 연결 필요)
docker run -d --name was-test -p 8080:8080 \
  723165663216.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-3tier-dev-was:latest

# 테스트
curl http://localhost:8080/petclinic

# 정리
docker stop was-test && docker rm was-test
```

## Jenkins 파이프라인 단계

| 단계 | 설명 | 실행 조건 |
|------|------|----------|
| **Checkout Source** | Git 소스 체크아웃 | 항상 |
| **Detect Changes** | 변경 파일 감지 및 빌드 대상 결정 | 항상 |
| **Login to ECR** | AWS ECR 로그인 | 항상 |
| **Build & Push WEB** | WEB 이미지 빌드 및 푸시 | WEB 변경 시 |
| **Build & Push WAS** | WAS 이미지 빌드 및 푸시 | WAS 변경 시 |
| **Update Manifests** | petclinic-manifests 업데이트 | UPDATE_MANIFEST=true |
| **Deploy to K8s** | Kubernetes Deployment 업데이트 | 항상 |
| **Verify Deployment** | Pod 상태 확인 | 항상 |

## Manifest 자동 업데이트

Jenkins가 이미지를 빌드한 후 자동으로 manifest 리포지토리를 업데이트합니다:

```bash
# petclinic-manifests 리포지토리 클론
git clone https://github.com/jisoo1015/petclinic-manifests.git

# 이미지 태그 업데이트
sed -i 's|image:.*petclinic-3tier-dev-web:.*|image: 723165663216.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-3tier-dev-web:build-123|g' \
  k8s-manifests/04-web-deployment.yaml

# Commit & Push
git commit -am "Update image tags to build-123"
git push origin main
```

이를 위해 Jenkins에서 **GitHub Credentials**가 필요합니다.

## GitHub Credentials 설정

### 1. Personal Access Token 생성

1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token (classic)
3. 권한 선택:
   - `repo` (전체)
4. 토큰 복사

### 2. Jenkins Credentials 추가

1. Jenkins → Credentials → System → Global credentials
2. Add Credentials
3. Kind: **Username with password**
   - Username: GitHub 사용자명
   - Password: Personal Access Token
   - ID: `github-credentials`

### 3. Git Push 인증 설정

Jenkinsfile에서 Git push 시 credentials 사용:

```groovy
withCredentials([usernamePassword(
    credentialsId: 'github-credentials',
    usernameVariable: 'GIT_USER',
    passwordVariable: 'GIT_TOKEN'
)]) {
    sh '''
    git push https://${GIT_USER}:${GIT_TOKEN}@github.com/jisoo1015/petclinic-manifests.git main
    '''
}
```

## 사용 시나리오

### 시나리오 1: WEB 코드만 변경

```bash
# WEB 파일 수정
echo "<!-- Updated -->" >> web/startbootstrap-grayscale-gh-pages/index.html

git add web/
git commit -m "Update homepage design"
git push origin main

# Jenkins 자동 감지
# → WEB만 빌드
# → ECR 푸시: petclinic-3tier-dev-web:build-N
# → Manifest 업데이트: 04-web-deployment.yaml
# → K8s 배포: web pod만 Rolling Update
```

### 시나리오 2: WAS 코드만 변경

```bash
# WAS 코드 수정
vi src/main/java/org/springframework/samples/petclinic/owner/OwnerController.java

git add src/
git commit -m "Fix owner controller bug"
git push origin main

# Jenkins 자동 감지
# → WAS만 빌드
# → ECR 푸시: petclinic-3tier-dev-was:build-N
# → Manifest 업데이트: 02-was-deployment.yaml
# → K8s 배포: was pod만 Rolling Update
```

### 시나리오 3: 둘 다 변경

```bash
# WEB + WAS 모두 수정
git add .
git commit -m "Update frontend and backend"
git push origin main

# Jenkins 자동 감지
# → WEB + WAS 모두 빌드
# → 두 이미지 모두 ECR 푸시
# → Manifest 두 파일 모두 업데이트
# → K8s 배포: 두 pod 모두 Rolling Update
```

### 시나리오 4: 수동 빌드 (특정 컴포넌트만)

Jenkins UI에서:
1. Build with Parameters 클릭
2. BUILD_TARGET: `WEB` 선택 (또는 `WAS`)
3. UPDATE_MANIFEST: 체크
4. Build 클릭

## 트러블슈팅

### 1. Manifest 업데이트 실패

```bash
# Jenkins 로그 확인
# "fatal: could not read Username" 에러

# 해결: GitHub Credentials 설정 확인
Jenkins → Credentials → github-credentials
```

### 2. 변경 감지 안됨

```bash
# 첫 커밋이거나 git diff 실패 시 → 모두 빌드
# 강제로 특정 컴포넌트만 빌드하려면:
BUILD_TARGET 파라미터 사용
```

### 3. ECR 푸시 권한 오류

```bash
# Jenkins 서버에서 확인
aws ecr describe-repositories --region ap-northeast-2

# IAM Role 확인 (EC2)
aws sts get-caller-identity
```

### 4. K8s 배포 실패

```bash
# kubectl 권한 확인
sudo su - jenkins
kubectl get pods -n petclinic

# kubeconfig 확인
cat ~/.kube/config
```

## 디렉토리 구조 권장사항

```
petclinic-ci/
├── .github/
│   └── workflows/           # GitHub Actions (선택사항)
├── web/                     # WEB 관련 파일
│   ├── startbootstrap-grayscale-gh-pages/
│   └── image.png
├── src/                     # WAS 관련 파일
│   ├── main/
│   └── test/
├── Dockerfile               # WAS Dockerfile
├── Dockerfile.web           # WEB Dockerfile
├── Jenkinsfile.unified      # 통합 파이프라인
├── pom.xml                  # WAS Maven
└── README.md
```

## 다음 단계

1. **GitOps 도입**: ArgoCD 사용하여 manifest 자동 동기화
2. **롤백 기능**: 이전 버전으로 자동 롤백
3. **알림 설정**: Slack/Email 알림
4. **테스트 자동화**: Unit/Integration 테스트 추가

---

## 요약

```bash
# 1. 코드 변경
cd /home/ec2-user/eks-infra/petclinic-ci
# WEB 또는 WAS 파일 수정

# 2. Commit & Push
git add .
git commit -m "Your message"
git push origin main

# 3. Jenkins 자동 빌드
# → 변경 감지
# → 해당 컴포넌트만 빌드
# → ECR 푸시
# → Manifest 업데이트
# → K8s 자동 배포

# 4. 확인
kubectl get pods -n petclinic -w
```

이제 하나의 리포지토리에서 WEB과 WAS를 효율적으로 관리할 수 있습니다!
