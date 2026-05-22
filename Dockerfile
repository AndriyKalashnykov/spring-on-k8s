ARG JDK_VERSION=21

# Maven build image. Literal tag — Renovate's `dockerfile` manager tracks this
# `FROM` line natively (Docker Hub tags for library/maven; bump when the
# 3.9.x-eclipse-temurin-21 variant is published).
# https://hub.docker.com/_/maven?tab=tags&page=1&name=eclipse-temurin-21
FROM maven:3.9.15-eclipse-temurin-21 AS build

WORKDIR /build
COPY pom.xml .
# create a layer with all of the Maven dependencies, first time it takes a while consequent calls are very fast
RUN mvn dependency:go-offline

COPY ./pom.xml /tmp/
COPY ./src /tmp/src/
WORKDIR /tmp/
# build the project
RUN mvn clean package

# extract JAR Layers (Spring Boot 3.2+ jarmode; destination flattens layer dirs into /tmp/target/extracted/)
WORKDIR /tmp/target
RUN java -Djarmode=tools -jar *.jar extract --layers --launcher --destination extracted

# runtime image
# Eclipse Temurin 25 JRE on Alpine — Adoptium-official Java 25 LTS, faster CVE
# rebuild cadence than Google's distroless. Decision + tradeoffs documented in
# docs/adr/0001-runtime-base-image.md. Renovate's `dockerfile` manager tracks
# this `FROM` line (Docker Hub library/eclipse-temurin); pinned by index digest.
FROM eclipse-temurin:25.0.3_9-jre-alpine@sha256:c707c0d18cb9e8556380719f80d96a7529d0746fbb42143893949b98ed2f8943 AS runtime

# Alpine does not ship a nonroot user — create one at the distroless-compatible
# UID/GID 65532 so the K8s posture (PodSecurity restricted, uid >= 10000) and
# any future PSA / OPA-Gatekeeper rule keep working without manifest changes.
RUN addgroup -g 65532 -S nonroot \
 && adduser  -u 65532 -S nonroot -G nonroot -h /home/nonroot -s /sbin/nologin

USER 65532:65532
WORKDIR /application

# copy layers from build image to runtime image as nonroot user
COPY --from=build --chown=65532:65532 /tmp/target/extracted/dependencies/ ./
COPY --from=build --chown=65532:65532 /tmp/target/extracted/snapshot-dependencies/ ./
COPY --from=build --chown=65532:65532 /tmp/target/extracted/spring-boot-loader/ ./
COPY --from=build --chown=65532:65532 /tmp/target/extracted/application/ ./

EXPOSE 8080

ENV _JAVA_OPTIONS="-XX:MinRAMPercentage=80.0 -XX:MaxRAMPercentage=90.0 \
-Djava.security.egd=file:/dev/./urandom \
-Djava.awt.headless=true -Dfile.encoding=UTF-8 \
-Dspring.output.ansi.enabled=ALWAYS \
-Dspring.profiles.active=default"

# set entrypoint to layered Spring Boot application
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]