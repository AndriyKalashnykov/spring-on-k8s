ARG MVN_VERSION=3.9.14
ARG JDK_VENDOR=eclipse-temurin
ARG JDK_VERSION=21

# https://hub.docker.com/_/maven?tab=tags&page=1&name=eclipse-temurin
FROM maven:${MVN_VERSION}-${JDK_VENDOR}-${JDK_VERSION} AS build

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
# use gcr.io/distroless/java${JDK_VERSION}-debian12:debug if you want to attach to the running image etc. and  gcr.io/distroless/java${JDK_VERSION}-debian12 for production
FROM gcr.io/distroless/java${JDK_VERSION}-debian12:debug@sha256:d100a8c571a3ed914a1a59dc076ca6d950347610385d7ca2e14cb6825a362fe3 AS runtime

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