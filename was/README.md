# PetClinic WAS (Spring Boot)

Spring Boot + Tomcat 기반의 백엔드 애플리케이션

## 구조

```
was/
├── Dockerfile                  # Multi-stage 빌드 (Maven + Tomcat)
├── pom.xml                     # Maven 설정
└── src/                        # Spring Boot 소스 코드
    ├── main/
    │   ├── java/
    │   └── resources/
    └── test/
```

## 빌드

### 로컬 빌드

```bash
# 프로젝트 루트에서
./build-local.sh was

# 또는 직접 빌드
docker build -f was/Dockerfile -t petclinic-was:test was/
```

### Jenkins 빌드

```bash
# was/ 디렉토리 변경 시 자동 감지
git add was/
git commit -m "Update backend API"
git push origin main

# → Jenkins가 WAS만 빌드
```

## 로컬 테스트

```bash
# RDS 연결 필요
docker run -d --name was-test -p 8080:8080 petclinic-was:test
curl http://localhost:8080/petclinic
docker stop was-test && docker rm was-test
```

## 데이터베이스

- Engine: MySQL 8.0
- Database: petclinic
- Username: admin
- Password: petclinic
- Port: 3306

## ECR 이미지

- Repository: `petclinic-3tier-dev-was`
- Tags: `latest`, `build-N`
