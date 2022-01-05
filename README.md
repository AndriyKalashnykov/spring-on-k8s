# Running your Spring Boot app on Kubernetes

This project describes how to run your Spring Boot app on Kubernetes.
You don't actually need to rewrite your app in order to target a K8s
cluster: Spring Boot can run on many platforms, thanks to
the abstraction level it provides.

This app is made of a single REST controller:
```java
@RestController
class HelloController {
    @Value("${app.message:Hello world!}")
    private String message;

    @GetMapping(value = "/", produces = MediaType.TEXT_PLAIN_VALUE)
    String greeting() {
        // Just return a simple String.
        return message;
    }
}
```

## How to use it?

Compile this app using a JDK:
```bash
$ mvn clean package
```

You can run this app locally:
```bash
$ mvn spring-boot:run
// or
$ java -jar target/spring-on-k8s.jar
```

The app is available at http://localhost:8080:
```bash
$ curl localhost:8080
Hello world!
```
```bash
$ curl http://localhost:8080/actuator | jq .
{
  "_links": {
    "self": {
      "href": "http://localhost:8080/actuator",
      "templated": false
    },
    "health": {
      "href": "http://localhost:8080/actuator/health",
      "templated": false
    },
    "health-path": {
      "href": "http://localhost:8080/actuator/health/{*path}",
      "templated": true
    },
    "prometheus": {
      "href": "http://localhost:8080/actuator/prometheus",
      "templated": false
    }
  }
}
```

## Creating a Docker image

Our goal is to run this app in a K8s cluster: you first need to package
this app in a Docker image.

Here's a `Dockerfile` you can use:
```Dockerfile
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
```

Run this command to build this image:
```bash
$ docker build -t andriykalashnykov/spring-on-k8s .
```

You can now push this image to your favorite Docker registry:
```bash
$ docker push andriykalashnykov/spring-on-k8s
```

You can use [Cloud Native Buildpacks](https://buildpacks.io)
to build & deploy your Docker image:
```bash
$ mvn spring-boot:build-image -Dimage.name=andriykalashnykov/spring-on-k8s
```

This command will take care of building a Docker image containing
a base image, a JRE, and this image will be optimized (unzipped
JAR file, different layers for app/config/lib).

or

```bash
$ pack build andriykalashnykov/spring-on-k8s -b ghcr.io/alexandreroman/cve-2021-44228-workaround-buildpack -b paketo-buildpacks/java --builder paketobuildpacks/builder:buildpackless-base
$ docker run --rm -p 8080:8080 andriykalashnykov/spring-on-k8s
```

## Scan for [Log4j 2 CVE-2021-44228](https://www.docker.com/blog/apache-log4j-2-cve-2021-44228/) 

```bash
# scan for all CVE
$ docker scan andriykalashnykov/spring-on-k8s
# scan for CVE-2021-44228
$ docker scan andriykalashnykov/spring-on-k8s | grep 'Arbitrary Code Execution'
```

## Deploying to Kubernetes

This project includes Kubernetes descriptors, so you can easily deploy
this app to your favorite K8s cluster:
```bash
$ kubectl apply -k k8s
```

Using this command, monitor the allocated IP address for this app:
```bash
$ kubectl -n spring-on-k8s get svc
NAME     TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)        AGE
app-lb   LoadBalancer   10.100.200.204   35.205.141.26   80:31633/TCP   90s
```

At some point, you should see an IP address under the column `EXTERNAL-IP`.

If you hit this address, you will get a greeting message from the app:
```bash
$ curl 35.205.141.26
Hello Kubernetes!%
```

## Contribute

Contributions are always welcome!

Feel free to open issues & send PR.

## License

Copyright &copy; 2021 [VMware, Inc. or its affiliates](https://vmware.com).

This project is licensed under the [Apache Software License version 2.0](https://www.apache.org/licenses/LICENSE-2.0).
