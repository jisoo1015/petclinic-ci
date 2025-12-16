# PetClinic WEB (Nginx Frontend)

Nginx 기반의 정적 파일 서빙 및 리버스 프록시

## 구조

```
web/
├── Dockerfile                                  # Nginx 이미지 빌드
└── static/                                     # 정적 파일
    ├── startbootstrap-grayscale-gh-pages/
    │   ├── index.html
    │   ├── css/
    │   ├── js/
    │   └── assets/
    └── image.png
```

## 빌드

### 로컬 빌드

```bash
# 프로젝트 루트에서
./build-local.sh web

# 또는 직접 빌드
docker build -f web/Dockerfile -t petclinic-web:test web/
```

### Jenkins 빌드

```bash
# web/ 디렉토리 변경 시 자동 감지
git add web/
git commit -m "Update frontend"
git push origin main

# → Jenkins가 WEB만 빌드
```

## 로컬 테스트

```bash
docker run -d --name web-test -p 8888:80 petclinic-web:test
curl http://localhost:8888/health
curl http://localhost:8888/
docker stop web-test && docker rm web-test
```

## Nginx 설정

- `/health`: 헬스체크 엔드포인트
- `/`: 정적 파일 서빙
- K8s ConfigMap으로 추가 설정 오버라이드 가능

## ECR 이미지

- Repository: `petclinic-3tier-dev-web`
- Tags: `latest`, `build-N`
