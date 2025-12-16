# ====================
# Stage 1: 빌드 단계
# ====================
FROM maven:3.8-amazoncorretto-17 AS builder
WORKDIR /build
COPY pom.xml .
COPY src ./src
RUN mvn clean package -P MySQL -DskipTests
RUN ls -lh /build/target/

# ====================
# Stage 2: 실행 단계
# ====================
FROM tomcat:9.0.110-jre17
RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=builder /build/target/*.war /usr/local/tomcat/webapps/petclinic.war
EXPOSE 8080
CMD ["catalina.sh", "run"]
