# ArgoCD 구축 가이드

PetClinic 3-tier 애플리케이션을 위한 ArgoCD 설치 및 GitOps 배포 구성 가이드입니다.

---

## 목차

1. [ArgoCD 설치](#1-argocd-설치)
2. [ArgoCD 접속](#2-argocd-접속)
3. [ArgoCD CLI 설치](#3-argocd-cli-설치-선택)
4. [GitHub Repository 연결](#4-github-repository-연결)
5. [Application 생성](#5-application-생성)
6. [배포 확인](#6-배포-확인)
7. [Auto-Sync 설정](#7-auto-sync-설정)
8. [트러블슈팅](#8-트러블슈팅)

---

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    GitOps with ArgoCD                        │
└─────────────────────────────────────────────────────────────┘

Jenkins CI Pipeline
├── Build Docker Image
├── Push to ECR
│   ├── petclinic-3tier-dev-web:build-N
│   └── petclinic-3tier-dev-was:build-N
└── (Trigger webhook - optional)

        ↓

GitHub Manifest Repository
└── https://github.com/jisoo1015/petclinic-manifests.git
    └── k8s-manifests/
        ├── 01-namespace.yaml
        ├── 02-was-deployment.yaml
        ├── 03-was-service.yaml
        ├── 04-web-deployment.yaml
        └── 05-web-service.yaml

        ↓

ArgoCD (Continuous Deployment)
├── Monitor Manifest Repository
├── Detect Changes
├── Sync to EKS Cluster
└── Self-Heal & Auto-Prune

        ↓

EKS Cluster
└── Namespace: petclinic
    ├── WEB Deployment (Nginx)
    ├── WEB Service
    ├── WAS Deployment (Spring Boot)
    └── WAS Service
```

---

## 1. ArgoCD 설치

### 1.1. ArgoCD Namespace 생성

```bash
kubectl create namespace argocd
```

### 1.2. ArgoCD 설치

```bash
# 최신 stable 버전 설치
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 1.3. 설치 확인

```bash
# ArgoCD Pod 상태 확인
kubectl get pods -n argocd

# 모든 Pod가 Running 상태가 될 때까지 대기
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

예상 출력:
```
NAME                                                READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                     1/1     Running   0          2m
argocd-applicationset-controller-xxx                1/1     Running   0          2m
argocd-dex-server-xxx                               1/1     Running   0          2m
argocd-notifications-controller-xxx                 1/1     Running   0          2m
argocd-redis-xxx                                    1/1     Running   0          2m
argocd-repo-server-xxx                              1/1     Running   0          2m
argocd-server-xxx                                   1/1     Running   0          2m
```

---

## 2. ArgoCD 접속

### 2.1. 초기 Admin 비밀번호 확인

```bash
# ArgoCD 초기 admin 비밀번호 조회
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

**비밀번호를 복사해두세요!**

### 2.2. ArgoCD 서버 접속 방법

#### 옵션 1: LoadBalancer 설정 (권장)

```bash
# ArgoCD Server를 LoadBalancer로 변경
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# LoadBalancer 주소 확인 (1-2분 소요)
kubectl get svc argocd-server -n argocd -w
```

LoadBalancer 주소가 할당되면 (EXTERNAL-IP 컬럼):
```bash
# ArgoCD URL 확인
ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ArgoCD URL: https://${ARGOCD_URL}"
echo "Username: admin"
echo "Password: <위에서 확인한 비밀번호>"
```

브라우저에서 해당 URL로 접속하세요.

**예시:**
```
https://a1b2c3d4e5f6g7h8.ap-northeast-2.elb.amazonaws.com
```

#### 옵션 2: Port Forward (로컬 테스트용)

**주의:** Port forward는 EC2 인스턴스 로컬에서만 작동합니다. 외부에서 접속하려면 VSCode Port Forwarding 또는 SSH 터널링이 필요합니다.

```bash
# Port forward 시작 (8081 포트 사용 - Jenkins가 8080 사용 중)
kubectl port-forward svc/argocd-server -n argocd 8081:443 > /dev/null 2>&1 &

# VSCode에서 Port Forwarding 추가 필요
# VSCode 하단 PORTS 탭 → Forward a Port → 8081 입력
```

VSCode Port Forwarding 후:
```
https://localhost:8081
```

#### 옵션 3: Ingress 설정 (권장 - 프로덕션용)

```bash
# Ingress 리소스 생성 (AWS ALB 사용 시)
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/backend-protocol: HTTPS
    alb.ingress.kubernetes.io/healthcheck-protocol: HTTPS
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
spec:
  rules:
  - host: argocd.your-domain.com  # 도메인 변경 필요
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
EOF
```

---

## 3. ArgoCD CLI 설치 (선택)

### Linux (EC2 인스턴스)

```bash
# ArgoCD CLI 다운로드
curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64

# 실행 권한 부여
chmod +x /tmp/argocd

# PATH에 추가
sudo mv /tmp/argocd /usr/local/bin/argocd

# 버전 확인
argocd version --client
```

### CLI 로그인

```bash
# Port forward 사용 시
argocd login localhost:8080 --username admin --password <비밀번호> --insecure

# LoadBalancer 사용 시
argocd login ${ARGOCD_SERVER} --username admin --password <비밀번호>
```

### 비밀번호 변경 (권장)

```bash
argocd account update-password
```

---

## 4. GitHub Repository 연결

ArgoCD가 Manifest 리포지토리를 모니터링하도록 설정합니다.

### 4.1. Public Repository (간단)

Public 리포지토리는 별도 인증 없이 사용 가능합니다.

### 4.2. Private Repository

#### GitHub Personal Access Token 생성

1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token (classic)
3. 권한 선택:
   - ✅ `repo` (전체)
4. Generate token
5. **토큰 복사** (다시 볼 수 없음!)

#### ArgoCD에 Repository 추가 (Web UI)

1. ArgoCD UI → Settings → Repositories → Connect Repo
2. 설정:
   ```
   Repository URL: https://github.com/jisoo1015/petclinic-manifests.git
   Username: jisoo1015
   Password: <GitHub Personal Access Token>
   ```
3. **Connect** 클릭

#### ArgoCD에 Repository 추가 (CLI)

```bash
argocd repo add https://github.com/jisoo1015/petclinic-manifests.git \
  --username jisoo1015 \
  --password <GITHUB_TOKEN>
```

#### 연결 확인

```bash
argocd repo list
```

---

## 5. Application 생성

### 5.1. PetClinic Application 생성 (Web UI)

1. ArgoCD UI → Applications → **New App**
2. 설정:

**GENERAL:**
```
Application Name: petclinic
Project: default
Sync Policy: Manual (나중에 Automatic으로 변경)
```

**SOURCE:**
```
Repository URL: https://github.com/jisoo1015/petclinic-manifests.git
Revision: HEAD (또는 main/master)
Path: k8s-manifests
```

**DESTINATION:**
```
Cluster URL: https://kubernetes.default.svc
Namespace: petclinic
```

**NAMESPACE:**
```
☑ Auto-Create Namespace
```

3. **Create** 클릭

### 5.2. PetClinic Application 생성 (CLI)

```bash
argocd app create petclinic \
  --repo https://github.com/jisoo1015/petclinic-manifests.git \
  --path k8s-manifests \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace petclinic \
  --sync-policy none
```

### 5.3. Application 생성 (Kubernetes Manifest)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: petclinic
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://github.com/jisoo1015/petclinic-manifests.git
    targetRevision: HEAD
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
EOF
```

---

## 6. 배포 확인

### 6.1. Application 상태 확인

#### Web UI
1. ArgoCD UI → Applications → **petclinic** 클릭
2. 상태 확인:
   - **Health**: Healthy
   - **Sync Status**: Synced

#### CLI
```bash
# Application 목록
argocd app list

# Application 상세 정보
argocd app get petclinic
```

### 6.2. 수동 Sync (첫 배포)

#### Web UI
1. petclinic Application → **Sync** 버튼 클릭
2. **Synchronize** 클릭

#### CLI
```bash
argocd app sync petclinic
```

### 6.3. Kubernetes 리소스 확인

```bash
# Namespace 확인
kubectl get ns petclinic

# 모든 리소스 확인
kubectl get all -n petclinic

# Deployment 상태
kubectl get deployments -n petclinic

# Pod 상태
kubectl get pods -n petclinic

# Service 확인
kubectl get svc -n petclinic
```

예상 출력:
```
NAME                   READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/was    2/2     2            2           5m
deployment.apps/web    2/2     2            2           5m

NAME                       READY   STATUS    RESTARTS   AGE
pod/was-xxx                1/1     Running   0          5m
pod/was-yyy                1/1     Running   0          5m
pod/web-xxx                1/1     Running   0          5m
pod/web-yyy                1/1     Running   0          5m

NAME          TYPE           CLUSTER-IP       EXTERNAL-IP                              PORT(S)        AGE
service/was   ClusterIP      10.100.xxx.xxx   <none>                                   8080/TCP       5m
service/web   LoadBalancer   10.100.yyy.yyy   xxx.ap-northeast-2.elb.amazonaws.com     80:30080/TCP   5m
```

### 6.4. 애플리케이션 접속 테스트

```bash
# WEB Service External IP 확인
WEB_URL=$(kubectl get svc web -n petclinic -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "PetClinic WEB URL: http://${WEB_URL}"

# 헬스체크
curl http://${WEB_URL}/health

# 브라우저에서 접속
echo "브라우저에서 접속: http://${WEB_URL}"
```

---

## 7. Auto-Sync 설정

### 7.1. Automated Sync 활성화

#### Web UI
1. petclinic Application → **App Details**
2. **Sync Policy** → **Enable Auto-Sync**
3. 옵션 선택:
   - ✅ **Prune Resources**: 삭제된 리소스 자동 제거
   - ✅ **Self Heal**: 클러스터 변경 시 자동 복구

#### CLI
```bash
argocd app set petclinic \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

#### Kubernetes Manifest
```bash
kubectl patch application petclinic -n argocd --type merge -p '
{
  "spec": {
    "syncPolicy": {
      "automated": {
        "prune": true,
        "selfHeal": true
      }
    }
  }
}'
```

### 7.2. Sync Options 설정

```bash
# Namespace 자동 생성
argocd app set petclinic --sync-option CreateNamespace=true

# RespectIgnoreDifferences 설정
argocd app set petclinic --sync-option RespectIgnoreDifferences=true
```

### 7.3. Sync 주기 설정

ArgoCD는 기본적으로 **3분마다** Git 리포지토리 변경사항을 확인합니다.

변경하려면:
```bash
# argocd-cm ConfigMap 수정
kubectl edit configmap argocd-cm -n argocd

# timeout.reconciliation 값 추가 (초 단위)
data:
  timeout.reconciliation: 180s  # 기본값 3분
```

---

## 8. GitOps 워크플로우 테스트

### 8.1. Jenkins에서 새 이미지 빌드

```bash
# petclinic-ci 리포지토리에서 코드 수정
cd /home/ec2-user/eks-infra/petclinic-ci

# WEB 코드 수정 예시
echo "<!-- Updated -->" >> web/static/startbootstrap-grayscale-gh-pages/index.html

# Git commit & push
git add .
git commit -m "Update web frontend"
git push origin main
```

### 8.2. Jenkins 빌드 자동 트리거

- GitHub Webhook이 Jenkins를 트리거
- Jenkins가 새 이미지 빌드 및 ECR 푸시
- 이미지 태그: `build-N`

### 8.3. Manifest 업데이트 (수동)

**현재 구성에서는 Manifest를 수동으로 업데이트해야 합니다.**

```bash
# Manifest 리포지토리 클론
cd /tmp
git clone https://github.com/jisoo1015/petclinic-manifests.git
cd petclinic-manifests

# WEB Deployment 이미지 태그 업데이트
sed -i 's|image:.*petclinic-3tier-dev-web:.*|image: 723165663216.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-3tier-dev-web:build-10|g' k8s-manifests/04-web-deployment.yaml

# 확인
grep "image:.*petclinic-3tier-dev-web" k8s-manifests/04-web-deployment.yaml

# Commit & Push
git add .
git commit -m "Update WEB image to build-10"
git push origin main
```

### 8.4. ArgoCD Auto-Sync 확인

```bash
# ArgoCD가 변경 감지 (최대 3분 소요)
watch -n 5 'argocd app get petclinic | grep -A 5 "Sync Status"'

# 또는 수동 sync
argocd app sync petclinic
```

### 8.5. 배포 확인

```bash
# Rolling Update 진행 확인
kubectl rollout status deployment/web -n petclinic

# 새 Pod 확인
kubectl get pods -n petclinic -l app=web

# 이미지 태그 확인
kubectl describe pod -n petclinic -l app=web | grep Image:
```

---

## 9. 고급 설정

### 9.1. Webhook 설정 (즉시 Sync)

기본 3분 대기 대신, Git Push 즉시 ArgoCD에 알림.

#### GitHub Webhook 설정

1. GitHub → petclinic-manifests → Settings → Webhooks → Add webhook
2. 설정:
   ```
   Payload URL: https://<ARGOCD_SERVER>/api/webhook
   Content type: application/json
   Secret: (비워둠 또는 설정)
   Events: Just the push event
   ```

#### ArgoCD에서 Webhook Secret 설정 (선택)

```bash
# Secret 생성
kubectl -n argocd create secret generic argocd-webhook-secret \
  --from-literal=webhook.github.secret=<YOUR_SECRET>

# argocd-cm ConfigMap 업데이트
kubectl edit configmap argocd-cm -n argocd

# 추가:
data:
  webhook.github.secret: <YOUR_SECRET>
```

### 9.2. Image Updater 설정 (자동 이미지 업데이트)

ArgoCD Image Updater를 사용하면 ECR의 새 이미지를 자동으로 Manifest에 반영할 수 있습니다.

#### Image Updater 설치

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
```

#### ECR 인증 설정

```bash
# AWS ECR용 Secret 생성
kubectl create secret generic ecr-credentials -n argocd \
  --from-literal=username=AWS \
  --from-literal=password=$(aws ecr get-login-password --region ap-northeast-2)
```

#### Application에 Annotation 추가

```bash
kubectl patch application petclinic -n argocd --type merge -p '
{
  "metadata": {
    "annotations": {
      "argocd-image-updater.argoproj.io/image-list": "web=723165663216.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-3tier-dev-web:latest, was=723165663216.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-3tier-dev-was:latest",
      "argocd-image-updater.argoproj.io/web.update-strategy": "latest",
      "argocd-image-updater.argoproj.io/was.update-strategy": "latest",
      "argocd-image-updater.argoproj.io/write-back-method": "git"
    }
  }
}'
```

### 9.3. Notification 설정

Slack, Email 등으로 배포 알림 받기.

```bash
# Slack Webhook URL 설정
kubectl patch configmap argocd-notifications-cm -n argocd --type merge -p '
{
  "data": {
    "service.slack": "token: <YOUR_SLACK_TOKEN>",
    "trigger.on-deployed": "- when: app.status.operationState.phase in [\"Succeeded\"]",
    "template.app-deployed": "message: Application {{.app.metadata.name}} deployed successfully"
  }
}'
```

---

## 10. 트러블슈팅

### 10.1. Application이 OutOfSync 상태

```bash
# 차이점 확인
argocd app diff petclinic

# 강제 Sync
argocd app sync petclinic --force
```

### 10.2. Health Check 실패

```bash
# Pod 로그 확인
kubectl logs -n petclinic <POD_NAME>

# Deployment 상태 확인
kubectl describe deployment -n petclinic <DEPLOYMENT_NAME>

# ArgoCD에서 리소스 상태 확인
argocd app resources petclinic
```

### 10.3. Image Pull 실패

ECR 이미지 pull 실패 시:

```bash
# ImagePullSecret 생성
kubectl create secret docker-registry ecr-secret \
  --docker-server=723165663216.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-northeast-2) \
  -n petclinic

# Deployment에 imagePullSecrets 추가
# Manifest 파일 수정:
spec:
  template:
    spec:
      imagePullSecrets:
      - name: ecr-secret
```

**참고:** EKS 노드가 ECR에 접근할 수 있는 IAM 역할이 있다면 ImagePullSecret 불필요.

### 10.4. ArgoCD Server 접속 안됨

```bash
# Pod 상태 확인
kubectl get pods -n argocd

# 로그 확인
kubectl logs -n argocd deployment/argocd-server

# Port forward 재시작
pkill -f "port-forward.*argocd"
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

### 10.5. Sync가 자동으로 안됨

```bash
# Application Sync Policy 확인
argocd app get petclinic -o json | jq '.spec.syncPolicy'

# argocd-repo-server 로그 확인
kubectl logs -n argocd deployment/argocd-repo-server

# Git 리포지토리 연결 확인
argocd repo list
```

---

## 11. 모니터링 및 관리

### 11.1. ArgoCD UI에서 확인 가능한 정보

- **Application Tree**: 모든 Kubernetes 리소스 계층 구조
- **Sync Status**: Git과 클러스터 간 차이
- **Health Status**: 리소스 건강 상태
- **History**: 배포 이력
- **Events**: 실시간 이벤트

### 11.2. CLI 명령어 모음

```bash
# Application 목록
argocd app list

# Application 상세 정보
argocd app get petclinic

# Sync 실행
argocd app sync petclinic

# Rollback
argocd app rollback petclinic <HISTORY_ID>

# Application 삭제
argocd app delete petclinic

# Logs 확인
argocd app logs petclinic
```

### 11.3. Kubernetes 명령어 모음

```bash
# ArgoCD 전체 상태
kubectl get all -n argocd

# PetClinic 전체 상태
kubectl get all -n petclinic

# Pod 로그
kubectl logs -f -n petclinic deployment/web
kubectl logs -f -n petclinic deployment/was

# Describe
kubectl describe deployment -n petclinic web
kubectl describe pod -n petclinic <POD_NAME>
```

---

## 12. 다음 단계

✅ ArgoCD 설치 완료
✅ PetClinic Application 생성 및 배포
✅ Auto-Sync 설정

### 추가 개선 사항

1. **Monitoring**: Prometheus + Grafana 연동
2. **Alerting**: Slack/Email 알림 설정
3. **Multi-Environment**: Dev/Staging/Prod 환경 분리
4. **RBAC**: 팀별 권한 관리
5. **Secrets Management**: Sealed Secrets 또는 External Secrets Operator
6. **Progressive Delivery**: Argo Rollouts로 Canary/Blue-Green 배포

---

## 참고 자료

- [ArgoCD 공식 문서](https://argo-cd.readthedocs.io/)
- [ArgoCD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
