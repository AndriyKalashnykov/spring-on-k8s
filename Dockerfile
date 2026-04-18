ARG JDK_VERSION=21

# Maven build image. Literal tag — Renovate's `dockerfile` manager tracks this
# `FROM` line natively (Docker Hub tags for library/maven; bump when the
# 3.9.x-eclipse-temurin-21 variant is published).
# https://hub.docker.com/_/maven?tab=tags&page=1&name=eclipse-temurin-21
FROM maven:3.9.14-eclipse-temurin-21 AS build

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
# https://github.com/GoogleContainerTools/distroless
# Production-hardened: distroless :nonroot has no shell and no coreutils. For
# troubleshooting (`kubectl exec`), temporarily swap this tag for :debug which
# ships busybox. Debian 13 base (Debian 12 EOL 2026-06-10).
FROM gcr.io/distroless/java${JDK_VERSION}-debian13:nonroot@sha256:80b758131ebac8564fc68c835d948497716de84e54b9eb76b49a4e892a68a8ea AS runtime

USER nonroot:nonroot
WORKDIR /application

# copy layers from build image to runtime image as nonroot user
COPY --from=build --chown=nonroot:nonroot /tmp/target/extracted/dependencies/ ./
COPY --from=build --chown=nonroot:nonroot /tmp/target/extracted/snapshot-dependencies/ ./
COPY --from=build --chown=nonroot:nonroot /tmp/target/extracted/spring-boot-loader/ ./
COPY --from=build --chown=nonroot:nonroot /tmp/target/extracted/application/ ./

EXPOSE 8080

ENV _JAVA_OPTIONS="-XX:MinRAMPercentage=80.0 -XX:MaxRAMPercentage=90.0 \
-Djava.security.egd=file:/dev/./urandom \
-Djava.awt.headless=true -Dfile.encoding=UTF-8 \
-Dspring.output.ansi.enabled=ALWAYS \
-Dspring.profiles.active=default"

# set entrypoint to layered Spring Boot application
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]