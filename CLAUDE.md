# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Spring Boot 4.0.5 reference service for Kubernetes deployment. Exposes REST endpoints (`/v1/hello`, `/v1/bye`), Swagger UI, Prometheus metrics via Actuator, and K8s liveness / readiness probes. Application configuration is overridden at runtime by a mounted ConfigMap via Spring's `configtree:` property source.

## Build & Run Commands

```bash
make build                 # Package JAR (mvn clean package -DskipTests)
make test                  # Run unit tests (Surefire, excludes *IT.java)
make integration-test      # Run integration tests (Failsafe, *IT.java via integration-test profile)
make e2e                   # Full e2e: kind-up → curl LB assertions → kind-down
make run                   # Run locally (mvn spring-boot:run) at http://localhost:8080
make static-check          # Composite quality gate (format-check, lint, secrets, trivy-fs, trivy-config, lint-ci, mermaid-lint, deps-prune-check)
make mermaid-lint          # Validate Mermaid diagrams in README.md / CLAUDE.md against minlag/mermaid-cli
make ci                    # Full pipeline: deps → format-check → static-check → test → build
make ci-run                # Run GitHub Actions workflow locally via act
make image-build           # Build Docker image ($(DOCKER_IMAGE):$(DOCKER_TAG))
make image-run             # Run Docker container (port 8080)
make image-stop            # Stop Docker container
make image-push            # Push Docker image to registry
make kind-up               # Local K8s: create KinD + MetalLB + deploy
make kind-down             # Tear down local K8s
make e2e                   # Full e2e: kind-up → curl assertions → kind-down
make upgrade               # Show available Maven dependency updates (dry-run)
make upgrade-apply         # Apply latest Maven releases (prompts, mutates pom.xml)
make release VERSION=1.2.3 # Tag a release (with confirmation prompt)
make renovate-validate     # Validate Renovate configuration
make deps-install          # Install Java/Maven via SDKMAN (one-time bootstrap)
make deps-check            # Show installed tool versions
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

Controllers use `@Value("${app.message:...}")` for configurable messages. On K8s, the ConfigMap at `k8s/cm.yml` overrides this via config tree mount at `/etc/config/` (env `SPRING_CONFIG_IMPORT=configtree:/etc/config/`).

**Test pyramid (three layers):**
- `make test` — Surefire-discovered unit tests (`*Test.java` / `*Tests.java`; excludes `*IT.java`). Fast, no Spring context.
- `make integration-test` — Failsafe-discovered `*IT.java` under the `integration-test` Maven profile. The canonical integration test is `ApplicationIT.java` — `@SpringBootTest(RANDOM_PORT)` + `RestClient` covering `/`, `/v1/hello`, `/v1/bye`, `/actuator/health{,/liveness,/readiness}`, `/actuator/prometheus`, `/v3/api-docs`.
- `make e2e` — `scripts/e2e-test.sh` runs against a KinD cluster with MetalLB. Asserts the ConfigMap override reaches the app, probes report UP, Prometheus endpoint exposes metrics, and an unknown path returns 404.

## Key Endpoints

| Path | Description |
|------|-------------|
| `/v1/hello`, `/v1/bye` | REST API |
| `/swagger-ui.html` | API docs UI |
| `/v3/api-docs` | OpenAPI JSON |
| `/actuator/health` | Aggregate health |
| `/actuator/health/liveness` | K8s liveness probe |
| `/actuator/health/readiness` | K8s readiness probe |
| `/actuator/prometheus` | Prometheus scrape target |

## Kubernetes Deployment

Production path uses Carvel tools (ytt + kapp):
```bash
ytt -f ./k8s | kapp deploy -y --into-ns spring-on-k8s -a spring-on-k8s -f-
```

K8s manifests in `k8s/`: namespace, deployment (1 replica, 1Gi memory, liveness/readiness probes), LoadBalancer service (80→8080), ConfigMap with `app.message`.

Local e2e path uses KinD + MetalLB: `make e2e` spins up a cluster, deploys, curls the LoadBalancer IP for `/v1/hello` expecting the ConfigMap override message "Hello Kubernetes!", and tears down. Implementation lives in `scripts/kind-metallb-setup.sh` and `scripts/e2e-test.sh`.

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.

## Build Configuration Notes

- **Java:** 21 across the board — `<java.version>` in pom.xml, `JAVA_VER`/`JDK_VERSION` in Makefile, `.java-version` for setup-java in CI
- **Compiler:** `failOnWarning=true` is set on maven-compiler-plugin (pom.xml); any javac warning blocks the build
- **Docker image:** Multi-stage Dockerfile with distroless runtime (`gcr.io/distroless/java21-debian12:debug`), layered JAR via `spring-boot-maven-plugin`, non-root user
- **Buildpacks alternative:** `mvn spring-boot:build-image` with Paketo builder
- **CI workflows** (`.github/workflows/`):
  - `ci.yml` — 8 jobs: `static-check` → { `build`, `test`, `integration-test` } (parallel) → { `e2e` (needs build + test), `docker` (needs all three), `cve-check` (tag/weekly/manual only) } → `ci-pass` (branch-protection gate, `if: always()`). The `docker` job runs Trivy image scan + smoke test on every push; multi-arch build + push to GHCR + cosign keyless signing happens only on `v*` tags
  - `cleanup-runs.yml` — weekly (Sunday) run pruning via `gh run delete` (retain 7 days, keep 5 minimum)
- **Renovate:** `renovate.json` drives automated dependency updates. Makefile `_VERSION` constants carry `# renovate:` inline comments; a single generic `customManagers` regex in `renovate.json` tracks them all
- **Trivy suppressions:** `.trivyignore` documents demo-scope K8s hardening exceptions and upstream CVEs tracked by Renovate
- **Architecture diagrams:** three inline Mermaid diagrams in README.md (C4 Context under the description, C4 Container + C4 Deployment in the `## Architecture` section). Lint target: `make mermaid-lint` uses the `minlag/mermaid-cli` Docker image (same engine GitHub uses to render). Wired into `make static-check`. No separate PlantUML toolchain — single-service + modest K8s topology fits inside Mermaid C4 cleanly
- **All `make` targets depend on `deps`** — tool availability is checked / auto-installed before execution
