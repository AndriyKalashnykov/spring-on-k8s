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
If you <i>still</i> want to do it with Docker - here's a proper (multistage, non-root, JAR layers, distroless runtime image base, etc.) [`Dockerfile`](https://github.com/AndriyKalashnykov/spring-on-k8s/blob/facebc172dbb9f068167da774b50b41ae3385a82/Dockerfile) you can use.

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

## VMware Tanzu Observability (Wavefront) for Spring Boot

Wavefront for Spring Boot allows you to quickly configure your
environment, so Spring Boot components send metrics, histograms,
and traces/spans to the Wavefront service, for more details see
how to [examine Spring Boot data in Wavefront dashboards and charts](https://docs.wavefront.com/wavefront_springboot.html#prerequisites-for-wavefront-spring-boot-starter)


Now you can run the project and observe Wavefront libraries automatically negotiated and created `api-token`: `dc9addea-8bae-467e-8f04-6b5dcfad1527`
and `one-time use link` : `https://wavefront.surf/us/8HggSpT5BD`

```bash
$ mvn clean package

[INFO] Scanning for projects...
  .   ____          _            __ _ _
 /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \
( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \
 \\/  ___)| |_)| | | | | || (_| |  ) ) ) )
  '  |____| .__|_| |_|_| |_\__, | / / / /
 =========|_|==============|___/=/_/_/_/
 :: Spring Boot ::                (v2.5.5)

2022-01-12 Wed 16:28:04.185 INFO  59841 [    main] com.vmware.demos.springonk8s.ApplicationTests:55 : Starting ApplicationTests using Java 17.0.1 on akalashnyko-a02.vmware.com with PID 59841 (started by akalashnykov in /Users/akalashnykov/projects/spring-on-k8s)
2022-01-12 Wed 16:28:04.186 INFO  59841 [    main] com.vmware.demos.springonk8s.ApplicationTests:659 : No active profile set, falling back to default profiles: default
2022-01-12 Wed 16:28:04.820 INFO  59841 [    main] org.springframework.cloud.context.scope.GenericScope:283 : BeanFactory id=964ae347-b9e4-313e-8d67-3ac7de89d489
2022-01-12 Wed 16:28:05.287 INFO  59841 [    main] org.springframework.boot.web.embedded.tomcat.TomcatWebServer:108 : Tomcat initialized with port(s): 0 (http)
2022-01-12 Wed 16:28:05.295 INFO  59841 [    main] org.apache.catalina.core.StandardService:173 : Starting service [Tomcat]
2022-01-12 Wed 16:28:05.296 INFO  59841 [    main] org.apache.catalina.core.StandardEngine:173 : Starting Servlet engine: [Apache Tomcat/9.0.53]
2022-01-12 Wed 16:28:05.391 INFO  59841 [    main] org.apache.catalina.core.ContainerBase.[Tomcat].[localhost].[/]:173 : Initializing Spring embedded WebApplicationContext
2022-01-12 Wed 16:28:05.391 INFO  59841 [    main] org.springframework.boot.web.servlet.context.ServletWebServerApplicationContext:290 : Root WebApplicationContext: initialization completed in 1189 ms
2022-01-12 Wed 16:28:05.492 INFO  59841 [    main] io.micrometer.core.instrument.push.PushMeterRegistry:71 : publishing metrics for WavefrontMeterRegistry every 1m
2022-01-12 Wed 16:28:07.116 INFO  59841 [    main] org.springframework.boot.actuate.endpoint.web.EndpointLinksResolver:58 : Exposing 4 endpoint(s) beneath base path '/actuator'
2022-01-12 Wed 16:28:07.201 INFO  59841 [    main] org.springframework.boot.web.embedded.tomcat.TomcatWebServer:220 : Tomcat started on port(s): 65081 (http) with context path ''
2022-01-12 Wed 16:28:07.224 INFO  59841 [    main] com.vmware.demos.springonk8s.ApplicationTests:61 : Started ApplicationTests in 4.046 seconds (JVM running for 4.742)

Your existing Wavefront account information has been restored from disk.

To share this account, make sure the following is added to your configuration:

        management.metrics.export.wavefront.api-token=dc9addea-8bae-467e-8f04-6b5dcfad1527
        management.metrics.export.wavefront.uri=https://wavefront.surf

Connect to your Wavefront dashboard using this one-time use link:
https://wavefront.surf/us/8HggSpT5BD

2022-01-12 Wed 16:28:07.773 INFO  59841 [o-auto-1-exec-1] org.apache.catalina.core.ContainerBase.[Tomcat].[localhost].[/]:173 : Initializing Spring DispatcherServlet 'dispatcherServlet'
2022-01-12 Wed 16:28:07.773 INFO  59841 [o-auto-1-exec-1] org.springframework.web.servlet.DispatcherServlet:525 : Initializing Servlet 'dispatcherServlet'
2022-01-12 Wed 16:28:07.775 INFO  59841 [o-auto-1-exec-1] org.springframework.web.servlet.DispatcherServlet:547 : Completed initialization in 2 ms
[INFO] Tests run: 4, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 5.13 s - in com.vmware.demos.springonk8s.ApplicationTests
[INFO] 
[INFO] Results:
[INFO] 
[INFO] Tests run: 4, Failures: 0, Errors: 0, Skipped: 0

```

Click on generated link [https://wavefront.surf/us/8HggSpT5BD](https://wavefront.surf/us/8HggSpT5BD) and navigate to `Dashboards -> Spring Boot`


![Spring Boot Dashboard](./docs/spring-dash.png "Spring Boot Dashboard")

you may also want to check `Applications -> Traces`

![Application Traces Dashboard](./docs/traces-dash.png "Application Traces Dashboard")

## Application Accelerator for VMware Tanzu
Creating Tanzu App Accelerators

[Creating Accelerators](https://docs.vmware.com/en/Application-Accelerator-for-VMware-Tanzu/1.0/acc-docs/GUID-creating-accelerators-index.html)
and [Creating an accelerator.yaml](https://docs.vmware.com/en/Application-Accelerator-for-VMware-Tanzu/1.0/acc-docs/GUID-creating-accelerators-accelerator-yaml.html)

## Publishing the new accelerator

### With kubectl

```bash
mkdir -p ~/projects/; cd ~/projects/
git clone git@github.com:AndriyKalashnykov/spring-on-k8s.git

kubectl apply -f  ~/projects/spring-on-k8s/k8s-resource.yaml --namespace accelerator-system
```

### With Tanzu CLI

```bash
tanzu acc create spring-on-k8s --kubeconfig $HOME/.kube/config  --git-repository https://github.com/AndriyKalashnykov/spring-on-k8s.git --git-branch main
```

## Deleting the accelerator

### With kubectl
```bash
kubectl delete -f  ~/projects/spring-on-k8s/k8s-resource.yaml --namespace accelerator-system
``` 

### With Tanzu CLI

```bash
tanzu acc delete spring-on-k8s --kubeconfig $HOME/.kube/config
```

## Contribute

Contributions are always welcome!

Feel free to open issues & send PR.

## License

Copyright &copy; 2022 [VMware, Inc. or its affiliates](https://vmware.com).

This project is licensed under the [Apache Software License version 2.0](https://www.apache.org/licenses/LICENSE-2.0).
