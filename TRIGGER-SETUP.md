# Jenkins 자동 트리거 설정 가이드

3가지 방법으로 Git Push 시 Jenkins를 자동으로 트리거할 수 있습니다.

---

## 현재 상태

### ✅ 완료된 설정

- Jenkins Job: `petclinic-unified-pipeline`
- GitHub Credentials: `jisoo1015` (설정됨)
- Git Repository: `https://github.com/jisoo1015/petclinic-ci.git`
- Script Path: `Jenkinsfile.unified`

### ❌ 미설정

- 자동 트리거 (Webhook or Polling)

---

## 방법 1: GitHub Webhook (권장) ⭐

Git Push → GitHub → Jenkins Webhook 호출 → 자동 빌드

### 장점
- ✅ 실시간 트리거 (푸시 즉시 빌드)
- ✅ 서버 리소스 효율적
- ✅ GitHub 표준 방식

### 단점
- ❌ Jenkins가 Public IP로 접근 가능해야 함
- ❌ 보안 그룹 8080 포트 오픈 필요

### 설정 방법

#### 1-1. Jenkins 설정 업데이트

```bash
sudo nano /var/lib/jenkins/jobs/petclinic-unified-pipeline/config.xml
```

`<triggers/>` 부분을 다음으로 변경:

```xml
<triggers>
  <com.cloudbees.jenkins.GitHubPushTrigger plugin="github@1.40.0">
    <spec></spec>
  </com.cloudbees.jenkins.GitHubPushTrigger>
</triggers>
```

Jenkins 재시작:

```bash
sudo systemctl restart jenkins
```

#### 1-2. EC2 보안 그룹 설정

```
AWS Console → EC2 → Security Groups
→ Jenkins 인스턴스의 Security Group
→ Inbound Rules → Edit

Add Rule:
- Type: Custom TCP
- Port: 8080
- Source: GitHub IP 범위 또는 0.0.0.0/0 (테스트용)
```

#### 1-3. GitHub Webhook 추가

**방법 A: GitHub UI**

```
https://github.com/jisoo1015/petclinic-ci/settings/hooks
→ Add webhook

Payload URL: http://43.203.247.182:8080/github-webhook/
Content type: application/json
Events: Just the push event
Active: ✓

→ Add webhook
```

**방법 B: GitHub API (스크립트)**

```bash
# GitHub Personal Access Token 필요
GITHUB_TOKEN="your_token_here"

curl -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/jisoo1015/petclinic-ci/hooks \
  -d '{
    "name": "web",
    "active": true,
    "events": ["push"],
    "config": {
      "url": "http://43.203.247.182:8080/github-webhook/",
      "content_type": "json"
    }
  }'
```

#### 1-4. 테스트

```bash
cd /home/ec2-user/eks-infra/petclinic-ci

echo "# Test" >> README.md
git add README.md
git commit -m "Test webhook trigger"
git push origin main

# Jenkins에서 자동 빌드 시작 확인
# http://43.203.247.182:8080/job/petclinic-unified-pipeline/
```

---

## 방법 2: Jenkins Poll SCM (간단)

Jenkins가 주기적으로 Git 리포지토리를 체크

### 장점
- ✅ Public IP 불필요
- ✅ 보안 그룹 변경 불필요
- ✅ 설정이 간단

### 단점
- ❌ 딜레이 발생 (최대 5분)
- ❌ 불필요한 Git 폴링
- ❌ 리소스 낭비

### 설정 방법

#### 2-1. Jenkins Job Config 수정

```bash
sudo nano /var/lib/jenkins/jobs/petclinic-unified-pipeline/config.xml
```

`<triggers/>` 부분을 다음으로 변경:

```xml
<triggers>
  <hudson.triggers.SCMTrigger>
    <spec>H/5 * * * *</spec>
    <ignorePostCommitHooks>false</ignorePostCommitHooks>
  </hudson.triggers.SCMTrigger>
</triggers>
```

**스케줄 설명:**
- `H/5 * * * *` - 5분마다 체크
- `H/2 * * * *` - 2분마다 체크 (더 빠르게)
- `* * * * *` - 1분마다 체크 (비권장, 부하 증가)

#### 2-2. Jenkins 재시작

```bash
sudo systemctl restart jenkins
```

#### 2-3. 테스트

```bash
cd /home/ec2-user/eks-infra/petclinic-ci

echo "# Test polling" >> README.md
git add README.md
git commit -m "Test poll SCM"
git push origin main

# 최대 5분 대기 후 빌드 시작
```

---

## 방법 3: Git Pre-Push Hook (로컬)

Git Push 전에 로컬에서 Jenkins API 호출

### 장점
- ✅ 즉시 트리거
- ✅ Public IP 불필요 (로컬 → Jenkins 직접 호출)
- ✅ 개발자별 커스터마이징 가능

### 단점
- ❌ 각 개발자가 Hook 설정 필요
- ❌ Jenkins API 토큰 필요
- ❌ 로컬 네트워크에서만 작동

### 설정 방법

#### 3-1. Jenkins API Token 생성

```
Jenkins → 사용자 클릭 → Configure
→ API Token → Add new Token
→ Generate → 토큰 복사
```

#### 3-2. Git Pre-Push Hook 생성

```bash
cd /home/ec2-user/eks-infra/petclinic-ci

cat > .git/hooks/pre-push <<'EOF'
#!/bin/bash

# Jenkins 설정
JENKINS_URL="http://localhost:8080"  # 또는 http://43.203.247.182:8080
JENKINS_USER="admin"                  # Jenkins 사용자명
JENKINS_TOKEN="your_jenkins_api_token_here"
JOB_NAME="petclinic-unified-pipeline"

echo "Triggering Jenkins build..."

# Jenkins API 호출 (파라미터 포함)
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "${JENKINS_URL}/job/${JOB_NAME}/buildWithParameters?BUILD_TARGET=ALL&UPDATE_MANIFEST=true" \
  --user "${JENKINS_USER}:${JENKINS_TOKEN}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" -eq 201 ]; then
    echo "✓ Jenkins build triggered successfully!"
else
    echo "✗ Failed to trigger Jenkins (HTTP $HTTP_CODE)"
fi

# Push는 계속 진행
exit 0
EOF

chmod +x .git/hooks/pre-push
```

#### 3-3. 토큰 설정

```bash
# Hook 파일 수정
nano .git/hooks/pre-push

# JENKINS_TOKEN 값을 실제 토큰으로 변경
```

#### 3-4. 테스트

```bash
echo "# Test pre-push hook" >> README.md
git add README.md
git commit -m "Test pre-push hook"
git push origin main

# 출력:
# Triggering Jenkins build...
# ✓ Jenkins build triggered successfully!
```

---

## 방법 비교

| 방법 | 속도 | 설정 난이도 | 보안 | 권장도 |
|------|------|-------------|------|--------|
| **Webhook** | ⚡ 즉시 | 중간 | 보통 | ⭐⭐⭐⭐⭐ |
| **Poll SCM** | 🐌 5분 | 쉬움 | 높음 | ⭐⭐⭐ |
| **Pre-Push Hook** | ⚡ 즉시 | 어려움 | 높음 | ⭐⭐ |

---

## 추천 설정

### 프로덕션 환경
→ **방법 1: GitHub Webhook** (실시간, 표준 방식)

### 개발/테스트 환경
→ **방법 2: Poll SCM** (간단, 안전)

### 로컬 개발
→ **방법 3: Pre-Push Hook** (즉시, 프라이빗)

---

## 현재 Webhook 확인

```bash
# Webhook 확인 스크립트 실행
cd /home/ec2-user/eks-infra/petclinic-ci
./check-webhook.sh
```

또는 GitHub UI에서:
```
https://github.com/jisoo1015/petclinic-ci/settings/hooks
```

---

## Jenkins Job 수동 트리거 (현재 가능)

Webhook 설정 전에도 수동으로 빌드 가능:

```bash
# 방법 1: Jenkins UI
http://43.203.247.182:8080/job/petclinic-unified-pipeline/
→ Build with Parameters
→ BUILD_TARGET: ALL
→ UPDATE_MANIFEST: true
→ Build

# 방법 2: Jenkins CLI (API Token 필요)
JENKINS_TOKEN="your_token"
curl -X POST "http://localhost:8080/job/petclinic-unified-pipeline/buildWithParameters?BUILD_TARGET=ALL&UPDATE_MANIFEST=true" \
  --user "admin:${JENKINS_TOKEN}"
```

---

## 트러블슈팅

### Webhook이 작동하지 않을 때

```bash
# 1. Jenkins 로그 확인
sudo tail -f /var/log/jenkins/jenkins.log

# 2. GitHub Webhook 전송 확인
https://github.com/jisoo1015/petclinic-ci/settings/hooks
→ Webhook 클릭 → Recent Deliveries

# 3. 포트 접근 테스트
curl -I http://43.203.247.182:8080/github-webhook/

# 4. 보안 그룹 확인
aws ec2 describe-security-groups --region ap-northeast-2
```

### Poll SCM이 작동하지 않을 때

```bash
# Jenkins 폴링 로그 확인
sudo cat /var/lib/jenkins/jobs/petclinic-unified-pipeline/polling.log

# Git 접근 확인
sudo su - jenkins
git ls-remote https://github.com/jisoo1015/petclinic-ci.git
```

---

## 다음 단계

1. ✅ **지금**: Git Push 완료
2. **선택**: Webhook 또는 Poll SCM 설정
3. **테스트**: 코드 변경 후 자동 빌드 확인
4. **모니터링**: Jenkins 빌드 로그 확인

어떤 방법을 선택하시겠습니까?
