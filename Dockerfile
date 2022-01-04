# 1. First build we build this app.
FROM adoptopenjdk:11-jdk-hotspot as BUILDER
RUN mkdir /build
ADD . /build
WORKDIR /build
# Use Maven wrapper script to build & test this app.
RUN ./mvnw -B clean package
RUN mkdir -p target/dependency && (cd target/dependency; jar -xf ../*.jar)

# As this point the app is built & tested,
# and the artifact is available in /build/target.

# 2. We build the target image, containing the app artifact.
FROM adoptopenjdk:11-jre-hotspot
VOLUME /tmp
# We don't want to run this app as root, so let's create a new user.
RUN useradd -m -s /bin/bash app
USER app
# Copy the app artifact from the previous run.
ARG DEPENDENCY=/build/target/dependency
COPY --from=BUILDER ${DEPENDENCY}/BOOT-INF/lib /app/lib
COPY --from=BUILDER ${DEPENDENCY}/META-INF /app/META-INF
COPY --from=BUILDER ${DEPENDENCY}/BOOT-INF/classes /app
# Since this container is using Java 11+, you don't need to add extra args:
# '+UseContainerSupport' is enabled by default to automatically tune JVM memory
# settings according to container memory resources.
ENTRYPOINT ["java","-cp","app:app/lib/*","com.vmware.demos.springonk8s.Application"]
