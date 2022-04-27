ARG MVN_VERSION=3.8.5
ARG JDK_VENDOR=eclipse-temurin
ARG JDK_VERSION=17

# https://hub.docker.com/_/maven?tab=tags&page=1&name=eclipse-temurin
FROM maven:${MVN_VERSION}-${JDK_VENDOR}-${JDK_VERSION} as build

WORKDIR /build
COPY pom.xml .
# create a layer with all of the Manven dependencies, first time it takes a while consequent call are very fast
RUN mvn dependency:go-offline

COPY ./pom.xml /tmp/
COPY ./src /tmp/src/
WORKDIR /tmp/
# build the project
RUN mvn clean package

# extract JAR Layers
WORKDIR /tmp/target
RUN java -Djarmode=layertools -jar *.jar extract

# runtime image
# https://github.com/GoogleContainerTools/distroless
# use gcr.io/distroless/java${JDK_VERSION}-debian11:debug if you want to attach to the running image etc. and  gcr.io/distroless/java${JDK_VERSION}-debian11 for production
FROM gcr.io/distroless/java${JDK_VERSION}-debian11:debug as runtime

USER nonroot:nonroot
WORKDIR /application

# copy layers from build image to runtime image as nonroot user
COPY --from=build --chown=nonroot:nonroot /tmp/target/dependencies/ ./
COPY --from=build --chown=nonroot:nonroot /tmp/target/snapshot-dependencies/ ./
COPY --from=build --chown=nonroot:nonroot /tmp/target/spring-boot-loader/ ./
COPY --from=build --chown=nonroot:nonroot /tmp/target/application/ ./

EXPOSE 8080

ENV _JAVA_OPTIONS "-XX:MinRAMPercentage=80.0 -XX:MaxRAMPercentage=90.0 \
-Djava.security.egd=file:/dev/./urandom \
-Djava.awt.headless=true -Dfile.encoding=UTF-8 \
-Dspring.output.ansi.enabled=ALWAYS \
-Dspring.profiles.active=default"

# set entrypoint to layered Spring Boot application
ENTRYPOINT ["java", "org.springframework.boot.loader.JarLauncher"]