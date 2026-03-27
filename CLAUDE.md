# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Spring Boot 4.0.2 demo application designed for Kubernetes deployment. Exposes REST endpoints (`/v1/hello`, `/v1/bye`) with Swagger UI, Prometheus metrics via Actuator, and K8s health probes.

## Build & Run Commands

```bash
make build          # Clean + package (mvn clean package -DskipTests)
make test           # Run tests (mvn test)
make run            # Run locally (mvn spring-boot:run), app at http://localhost:8080
make image-build    # Build Docker image with JDK 21
make image-run      # Run Docker container (port 8080)
make image-stop     # Stop Docker container
make lint           # Checkstyle code style checks
make ci             # Full pipeline: deps, build, test, lint
make ci-run         # Run GitHub Actions workflow locally via act
make upgrade        # Update Maven dependencies
make release VERSION=1.2.3  # Tag a release (with confirmation prompt)
make renovate-validate      # Validate Renovate configuration
make deps-check     # Install Java/Maven via SDKMAN
```

Direct Maven equivalents:
```bash
mvn clean package -DskipTests               # Build
mvn test                                     # Run all tests
mvn clean spring-boot:run -Djava.version=21  # Run locally
mvn test -Dtest=ApplicationTests#testHello   # Run single test method
```

## Architecture

**Base package:** `com.vmware.demos.springonk8s`

```
src/main/java/.../springonk8s/
  Application.java              # @SpringBootApplication entry point
  api/rest/controller/
    HelloController.java        # GET /, GET /v1/hello (message from ${app.message})
    ByeController.java          # GET /v1/bye (message from ${app.message})
  api/rest/docs/
    SwaggerConfig.java          # OpenAPI bean configuration
```

Controllers use `@Value("${app.message:...}")` for configurable messages. On K8s, the ConfigMap at `k8s/cm.yml` overrides this via config tree mount at `/etc/config/`.

**Test file:** Single integration test class `ApplicationTests.java` using `@SpringBootTest(RANDOM_PORT)` with `RestClient`. Tests: contextLoads, testHello, testBye, testHealth.

## Key Endpoints

| Path | Description |
|------|-------------|
| `/v1/hello`, `/v1/bye` | REST API |
| `/swagger-ui.html` | API docs UI |
| `/actuator/health` | Health check |
| `/actuator/health/liveness` | K8s liveness probe |
| `/actuator/health/readiness` | K8s readiness probe |
| `/actuator/prometheus` | Prometheus metrics |

## Kubernetes Deployment

Uses Carvel tools (ytt + kapp):
```bash
ytt -f ./k8s | kapp deploy -y --into-ns spring-on-k8s -a spring-on-k8s -f-
```

K8s manifests in `k8s/`: namespace, deployment (1 replica, 1Gi memory, liveness/readiness probes), LoadBalancer service (80->8080), ConfigMap with `app.message`.

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.yml` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.

## Build Configuration Notes

- **pom.xml java.version:** 17 (compile target), but **SDKMAN/CI uses JDK 21** for runtime
- **Docker image:** Multi-stage build with distroless base, layered JAR, non-root user
- **Buildpacks alternative:** `mvn spring-boot:build-image` with Paketo builder
- **CI:** GitHub Actions runs `make build` + `make test` + `make lint` on ubuntu-latest with JDK 21 Temurin
- **All targets depend on `deps`** — tool availability is checked before execution
