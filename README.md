# Running Spring Boot app on Kubernetes

This project describes how to run Spring Boot app on Kubernetes.
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

### Pre-requisites

Install and use JDK 17
```bash
sdk install java 17.0.1.12.1-amzn
sdk use java 17.0.1.12.1-amzn
```

Compile this app using a JDK:
```bash
$ mvn clean package -Djava.version=17
```

You can run this app locally:
```bash
$ mvn spring-boot:run
```

The app is available at [http://localhost:8080](http://localhost:8080)

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
ARG MVN_VERSION=3.8.4
ARG JDK_VERSION=17

FROM maven:${MVN_VERSION}-amazoncorretto-${JDK_VERSION} as build

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
# use  gcr.io/distroless/java${JDK_VERSION}-debian11:debug if you want to attach to the running image etc. and  gcr.io/distroless/java${JDK_VERSION}-debian11 for production
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
$ export DOCKER_PWD=YOUR-REGISTRY-PASSWORD
$ mvn clean spring-boot:build-image -Djava.version=17 -Dimage.publish=true -Dimage.name=andriykalashnykov/spring-on-k8s -Ddocker.publishRegistry.username=andriykalashnykov -Ddocker.publishRegistry.password=${DOCKER_PWD}
```

## Scan for [Log4j 2 CVE-2021-44228](https://www.docker.com/blog/apache-log4j-2-cve-2021-44228/) and other vulnerabilities 

```bash
# scan for all CVEs
$ docker scan andriykalashnykov/spring-on-k8s
# scan for CVE-2021-44228
$ docker scan andriykalashnykov/spring-on-k8s | grep 'Arbitrary Code Execution'
```

### Use workaround to mitigate `Log4j 2 CVE-2021-44228` by creating Docker image with [custom buildpack](https://github.com/alexandreroman/cve-2021-44228-workaround-buildpack)

```bash
$ pack build andriykalashnykov/spring-on-k8s -b ghcr.io/alexandreroman/cve-2021-44228-workaround-buildpack -b paketo-buildpacks/java --builder paketobuildpacks/builder:buildpackless-base
$ docker run --rm -p 8080:8080 andriykalashnykov/spring-on-k8s
```

## Deploying to Kubernetes

This project includes Kubernetes descriptors, so you can easily deploy
this app to your favorite K8s cluster:
```bash
$ kubectl apply -f k8s
$ kubectl apply -f k8s -o yaml --dry-run=client
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
Hello Kubernetes!
```

## Contribute

Contributions are always welcome!

Feel free to open issues & send PR.

## License

Copyright &copy; 2022 [VMware, Inc. or its affiliates](https://vmware.com).

This project is licensed under the [Apache Software License version 2.0](https://www.apache.org/licenses/LICENSE-2.0).
