ARG JDK_VERSION=21

# Maven build image. Literal tag — Renovate's `dockerfile` manager tracks this
# `FROM` line natively (Docker Hub tags for library/maven; bump when the
# 3.9.x-eclipse-temurin-21 variant is published).
# https://hub.docker.com/_/maven?tab=tags&page=1&name=eclipse-temurin-21
FROM maven:3.9.16-eclipse-temurin-21@sha256:8272290d5a97124dad475635f31556931e6a3b5fd74c6b4b37f3af9c0e53d735 AS build

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
FROM eclipse-temurin:25.0.3_9-jre-alpine@sha256:28db6fdf60e38945e43d840c0333aeaec66c15943070104f7586fd3c9d1665b0 AS runtime

# Operator-tunable runtime build args. Defaults: UID/GID 65532 matches the
# distroless `nonroot` convention (and the k8s restricted-PodSecurity
# expectation, uid >= 10000); APP_INTERNAL_PORT mirrors the Spring Boot bind
# port and the k8s containerPort. Override at build time with `--build-arg`.
ARG APP_UID=65532
ARG APP_GID=65532
ARG APP_INTERNAL_PORT=8080

# Cache-busting arg for the OS-package upgrade layer below. Its cache key is
# otherwise the instruction text + the pinned base digest — neither changes — so
# `cache-from: type=gha` reuses a STALE layer indefinitely and freezes OS
# packages at first-build state. Freshly-disclosed CVEs then never clear until
# the base digest bumps (e.g. CVE-2026-45186 in expat, fixed 2.8.1-r0, shipped
# 2.7.5-r0 from a cached layer). CI passes a rotating value (the run id) so this
# layer rebuilds every run and the upgrade reflects the latest Alpine 3.23
# packages; `make image-build` passes a daily date. Default 0 (local cache OK).
ARG APK_UPGRADE_BUST=0

# Patch the base image's OS packages to the latest in the pinned Alpine 3.23
# branch before the image is scanned. The digest-pinned eclipse-temurin base
# lags Alpine security updates between Adoptium rebuilds, so freshly-disclosed
# CVEs against baked-in libs (e.g. CVE-2026-45447 in openssl/libcrypto3/libssl3,
# fixed in 3.5.7-r0) ship until the next base rebuild. `apk upgrade` pulls the
# fixed packages immediately and self-heals future base-lag CVEs — a real fix,
# not a Trivy waiver. `--no-cache` leaves no apk index behind. Runs as root,
# before the USER switch. See docs/adr/0001-runtime-base-image.md (Addendum).
RUN echo "apk-upgrade-bust=${APK_UPGRADE_BUST}" \
 && apk --no-cache upgrade

# Alpine does not ship a nonroot user — create one at the distroless-compatible
# UID/GID so the K8s posture (PodSecurity restricted, uid >= 10000) and any
# future PSA / OPA-Gatekeeper rule keep working without manifest changes.
RUN addgroup -g ${APP_GID} -S nonroot \
 && adduser  -u ${APP_UID} -S nonroot -G nonroot -h /home/nonroot -s /sbin/nologin

USER ${APP_UID}:${APP_GID}
WORKDIR /application

# copy layers from build image to runtime image as nonroot user
COPY --from=build --chown=${APP_UID}:${APP_GID} /tmp/target/extracted/dependencies/ ./
COPY --from=build --chown=${APP_UID}:${APP_GID} /tmp/target/extracted/snapshot-dependencies/ ./
COPY --from=build --chown=${APP_UID}:${APP_GID} /tmp/target/extracted/spring-boot-loader/ ./
COPY --from=build --chown=${APP_UID}:${APP_GID} /tmp/target/extracted/application/ ./

EXPOSE ${APP_INTERNAL_PORT}

ENV _JAVA_OPTIONS="-XX:MinRAMPercentage=80.0 -XX:MaxRAMPercentage=90.0 \
-Djava.security.egd=file:/dev/./urandom \
-Djava.awt.headless=true -Dfile.encoding=UTF-8 \
-Dspring.output.ansi.enabled=ALWAYS \
-Dspring.profiles.active=default"

# set entrypoint to layered Spring Boot application
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]