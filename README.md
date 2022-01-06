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
$ mvn clean spring-boot:run -Djava.version=17
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

### Buildpacks

Use [Cloud Native Buildpacks](https://buildpacks.io) to build & push your Docker image:

```bash 
$ export DOCKER_LOGIN=andriykalashnykov
$ export DOCKER_PWD=YOUR-REGISTRY-PASSWORD
$ mvn clean spring-boot:build-image -Djava.version=17 -Dimage.publish=true -Dimage.name=andriykalashnykov/spring-on-k8s:latest -Ddocker.publishRegistry.username=${DOCKER_LOGIN} -Ddocker.publishRegistry.password=${DOCKER_PWD}
```

### Docker
If you <i>still</i> want to do it with Docker - here's a proper (multistage, non-root, JAR layers, distroless runtime image base) [`Dockerfile`](https://github.com/AndriyKalashnykov/spring-on-k8s/blob/facebc172dbb9f068167da774b50b41ae3385a82/Dockerfile) you can use.

Run this command to build this image:
```bash
$ docker build -t andriykalashnykov/spring-on-k8s --build-arg JDK_VENDOR=openjdk --build-arg JDK_VERSION=17 .
```

You can now push this image to your favorite Docker registry:
```bash
$ docker push andriykalashnykov/spring-on-k8s
```

## Scan for [Log4j 2 CVE-2021-44228](https://www.docker.com/blog/apache-log4j-2-cve-2021-44228/) and other vulnerabilities 

```bash
# scan for all CVEs
$ docker scan andriykalashnykov/spring-on-k8s:latest 
# scan for CVE-2021-44228
$ docker scan andriykalashnykov/spring-on-k8s:latest  | grep 'Arbitrary Code Execution'
```

### Use workaround to mitigate `Log4j 2 CVE-2021-44228` by creating Docker image with [custom buildpack](https://github.com/alexandreroman/cve-2021-44228-workaround-buildpack)

```bash
$ pack build andriykalashnykov/spring-on-k8s:latest  -b ghcr.io/alexandreroman/cve-2021-44228-workaround-buildpack -b paketo-buildpacks/java --builder paketobuildpacks/builder:buildpackless-base
```

## Run Docker image

```bash
$ docker run --rm -p 8080:8080 andriykalashnykov/spring-on-k8s:latest 
```

## Deploying to Kubernetes

This project includes Kubernetes descriptors, so you can easily deploy
this app to your favorite K8s cluster:

```bash
$ ytt -f ./k8s | kapp deploy -y --into-ns spring-on-k8s -a spring-on-k8s -f-
```

Using this command, monitor the allocated IP address for this app:
```bash
$ kubectl -n spring-on-k8s get svc
NAME     TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)        AGE
app-lb   LoadBalancer   xx.100.200.204   xx.205.141.26   80:31633/TCP   90s
```

At some point, you should see an IP address under the column `EXTERNAL-IP`.

If you hit this address, you will get a greeting message from the app:

```bash
$ curl $(kubectl -n spring-on-k8s get svc app | sed -n '2 p' | awk '{print $4}')
Hello Kubernetes!
```

## Undeploying from Kubernetes

```bash
$ kapp delete -a spring-on-k8s --yes
```

## Contribute

Contributions are always welcome!

Feel free to open issues & send PR.

## License

Copyright &copy; 2022 [VMware, Inc. or its affiliates](https://vmware.com).

This project is licensed under the [Apache Software License version 2.0](https://www.apache.org/licenses/LICENSE-2.0).
