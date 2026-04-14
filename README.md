[![CI](https://github.com/AndriyKalashnykov/spring-on-k8s/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/spring-on-k8s/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/spring-on-k8s.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/spring-on-k8s/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/spring-on-k8s)

# Running Spring Boot app on Kubernetes

Spring Boot 4 reference service for Kubernetes deployment. Exposes REST endpoints (`/v1/hello`, `/v1/bye`), Swagger UI, Prometheus metrics via Spring Boot Actuator, and K8s liveness / readiness probes. Application configuration is overridden at runtime by a mounted `ConfigMap` via Spring's `configtree:` property source.

```mermaid
C4Context
  title System Context — spring-on-k8s

  Person(user, "End User", "Consumes the REST API over HTTPS")
  System(sys, "spring-on-k8s", "Spring Boot 4 service: REST + Actuator + Swagger")
  System_Ext(prom, "Prometheus", "Scrapes /actuator/prometheus")
  System_Ext(k8s, "Kubernetes", "Runs the pod; probes health endpoints")

  Rel(user, sys, "Uses", "HTTPS / JSON")
  Rel(prom, sys, "Scrapes metrics", "HTTP")
  Rel(k8s, sys, "Probes liveness + readiness", "HTTP")

  UpdateLayoutConfig($c4ShapeInRow="2")
```

| Component | Technology |
|-----------|-----------|
| Language | Java 21 (source + target + runtime) |
| Framework | Spring Boot 4.0.5 |
| API style | REST + OpenAPI via [springdoc-openapi](https://springdoc.org/) 3.0.3 |
| Metrics | [Micrometer](https://micrometer.io/) + Prometheus registry |
| Build | Maven 3.9 |
| Container | Multi-stage Dockerfile, distroless runtime, non-root user |
| Orchestration | Kubernetes 1.30+, deployed via [Carvel](https://carvel.dev/) (`ytt` + `kapp`) |
| Local K8s | [KinD](https://kind.sigs.k8s.io/) + [MetalLB](https://metallb.io/) for `make e2e` |
| CI/CD | GitHub Actions (split `static-check` / `build` / `test` / `ci-pass`) |
| Code quality | Checkstyle, hadolint, [google-java-format](https://github.com/google/google-java-format), gitleaks, Trivy, actionlint, OWASP dependency-check |
| Dep management | Renovate (automerge minor/patch, 3-day buffer on majors) |

## Quick Start

```bash
make deps          # verify tools; installs Maven locally if missing
make build         # build the project
make test          # run tests
make run           # start at http://localhost:8080
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+ | Build orchestration |
| [JDK](https://adoptium.net/) | 21+ | Java runtime and compiler |
| [Maven](https://maven.apache.org/) | 3.9+ | Build and dependency management (`make deps-maven` auto-installs if missing) |
| [Docker](https://www.docker.com/) | latest | Container image builds, KinD, Trivy filesystem scans |
| [Git](https://git-scm.com/) | 2.0+ | Version control |
| [SDKMAN](https://sdkman.io/) | latest | Java/Maven version management (optional — `make deps-install` uses it) |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.30+ | Kubernetes deployment (`make deps-kubectl` auto-installs) |
| [KinD](https://kind.sigs.k8s.io/) | 0.32+ | Local K8s cluster for `make e2e` (`make deps-kind` auto-installs) |
| [Carvel](https://carvel.dev/) | latest | `ytt` + `kapp` for production K8s deploy (optional) |

Install all required dependencies:

```bash
make deps
```

## Available Make Targets

Run `make help` to see all available targets.

### Build & Run

| Target | Description |
|--------|-------------|
| `make build` | Build project (skips tests) |
| `make run` | Run locally at `http://localhost:8080` |
| `make clean` | Clean Maven build artifacts |

### Testing (three layers)

| Target | Description | Runtime | Discovery |
|--------|-------------|---------|-----------|
| `make test` | Unit tests (Surefire, excludes `*IT.java`) | seconds | `**/*Test.java`, `**/*Tests.java` |
| `make integration-test` | In-process integration tests via `@SpringBootTest(RANDOM_PORT)` + real Actuator/Springdoc | ~5s | `**/*IT.java` (Failsafe, `integration-test` Maven profile) |
| `make e2e` | Full-stack end-to-end against KinD + MetalLB; asserts ConfigMap override + LB wiring + negative case | ~3–5 min | `scripts/e2e-test.sh` |

### Code Quality & Security

| Target | Description |
|--------|-------------|
| `make format` | Format Java sources with google-java-format (writes changes) |
| `make format-check` | Verify Java sources are formatted (no changes) |
| `make lint` | Checkstyle + hadolint + compiler warnings-as-errors |
| `make secrets` | gitleaks scan of working tree |
| `make secrets-history` | gitleaks full git history audit (slow) |
| `make trivy-fs` | Trivy filesystem scan (vulns, secrets, misconfigs) |
| `make trivy-config` | Trivy scan of K8s manifests |
| `make lint-ci` | actionlint on `.github/workflows/` |
| `make cve-check` | OWASP dependency-check (fast with `NVD_API_KEY`) |
| `make deps-prune` | Report unused/undeclared Maven dependencies |
| `make deps-prune-check` | Fail if unused/undeclared Maven dependencies found |
| `make static-check` | Composite gate: format-check + lint + secrets + trivy-fs + trivy-config + lint-ci + deps-prune-check |

### Docker

| Target | Description |
|--------|-------------|
| `make image-build` | Build Docker image (`$(DOCKER_IMAGE):$(DOCKER_TAG)`) |
| `make image-run` | Run Docker container |
| `make image-stop` | Stop Docker container |
| `make image-push` | Push Docker image to registry |

### Kubernetes (KinD)

| Target | Description |
|--------|-------------|
| `make kind-up` | Bring the full stack up: create cluster → install MetalLB → load image → deploy |
| `make kind-down` | Tear the cluster down |
| `make kind-create` | Create KinD cluster (granular) |
| `make kind-setup` | Install MetalLB in KinD for `LoadBalancer` services (granular) |
| `make kind-load` | Load local Docker image into KinD (granular) |
| `make kind-deploy` | Apply K8s manifests to the KinD cluster (granular) |
| `make kind-undeploy` | Remove the app from the cluster (granular) |
| `make kind-destroy` | Delete the KinD cluster (granular) |
| `make e2e` | Full end-to-end: `kind-up` → curl LB IP assertions → `kind-down` |

### CI

| Target | Description |
|--------|-------------|
| `make ci` | Full local CI: deps → format-check → static-check → test → build |
| `make ci-run` | Run the GitHub Actions workflow locally via [act](https://github.com/nektos/act) |

### Utilities

| Target | Description |
|--------|-------------|
| `make help` | List all available targets |
| `make deps` | Verify required tools; auto-installs Maven if missing |
| `make deps-install` | Install Java + Maven via SDKMAN (one-time bootstrap) |
| `make deps-check` | Show installed tool versions |
| `make upgrade` | Show available Maven dependency updates (dry-run) |
| `make upgrade-apply` | Apply latest Maven releases (prompts, mutates `pom.xml`) |
| `make release VERSION=x.y.z` | Create a semver release tag |
| `make renovate-validate` | Validate Renovate configuration locally |

## Endpoints

| Path | Description |
|------|-------------|
| `GET /` | Hardcoded greeting (`Hello world`) |
| `GET /v1/hello` | Returns `${app.message}` (default: `Hello world!`; overridden by ConfigMap to `Hello Kubernetes!`) |
| `GET /v1/bye` | Returns `${app.message}` |
| `GET /actuator/health` | Aggregate health |
| `GET /actuator/health/liveness` | K8s liveness probe endpoint |
| `GET /actuator/health/readiness` | K8s readiness probe endpoint |
| `GET /actuator/prometheus` | Prometheus scrape target |
| `GET /swagger-ui.html` | OpenAPI / Swagger UI |
| `GET /v3/api-docs` | OpenAPI JSON |

### Swagger UI

![Swagger UI](./docs/swagger-ui.png "Swagger UI")

## Architecture

### Container view

```mermaid
C4Container
  title Container View — spring-on-k8s

  Person(user, "End User")
  System_Ext(prom, "Prometheus")

  System_Boundary(sys, "spring-on-k8s") {
    Container(api, "API Service", "Spring Boot 4.0.5, Java 21", "REST controllers + Spring Boot Actuator + springdoc-openapi 3.0.3")
    ContainerDb(cm, "ConfigMap", "Kubernetes ConfigMap", "Provides app.message; Spring reads it via configtree mount at /etc/config/")
  }

  Rel(user, api, "GET /v1/hello, /v1/bye, /swagger-ui.html", "HTTPS")
  Rel(api, cm, "Reads app.message", "configtree (file mount)")
  Rel(prom, api, "Scrapes /actuator/prometheus", "HTTP")
```

- **API Service** — single Spring Boot process, Micrometer exports Prometheus metrics, Actuator backs the K8s probes (`/actuator/health/liveness`, `/actuator/health/readiness`)
- **ConfigMap** — cluster-side K8s resource, mounted as a volume at `/etc/config/`; the env `SPRING_CONFIG_IMPORT=configtree:/etc/config/` tells Spring to read each file as a property (default `Hello world!` → ConfigMap overrides to `Hello Kubernetes!`)
- **Prometheus** — external scrape target, no code changes required; the endpoint is enabled via `management.endpoints.web.exposure.include`

### Deployment

```mermaid
C4Deployment
  title Deployment — Kubernetes (via Carvel ytt + kapp)

  Deployment_Node(cluster, "Kubernetes Cluster", "v1.30+") {
    Deployment_Node(ns, "Namespace: spring-on-k8s") {
      Deployment_Node(pod, "Pod (Deployment replicas=1)") {
        Container(api, "app container", "ghcr.io/andriykalashnykov/spring-on-k8s, distroless Java 21, non-root")
      }
      Container(svc, "Service: app", "LoadBalancer 80 → 8080")
      ContainerDb(cmres, "ConfigMap: config", "app.message = Hello Kubernetes!")
    }
  }

  Rel(svc, api, "Routes to :8080", "TCP")
  Rel(cmres, api, "Mounted at /etc/config/", "volume")
```

- **Deployment** — 1 replica, 1 Gi memory limit, liveness+readiness probes point at Actuator
- **Service** — LoadBalancer; locally served by MetalLB in the `make e2e` KinD stack, cloud-provided in production
- **ConfigMap** — deployed alongside the Deployment; edits to `k8s/cm.yml` propagate via `kapp deploy` and trigger a pod rollout (config source-of-truth lives in git, not in `kubectl edit`)

Sources: diagrams are inline Mermaid in this README — no build step; GitHub renders them natively. Lint with `make mermaid-lint` (uses the same `minlag/mermaid-cli` engine GitHub uses, so what parses locally renders on the homepage).

## Docker image

A multi-stage [Dockerfile](./Dockerfile) builds a distroless runtime image with a non-root user and Spring Boot JAR layering.

```bash
make image-build                                         # build
make image-run                                           # run at http://localhost:8080
make image-push                                          # push to registry
```

Buildpacks alternative (Paketo):

```bash
export DOCKER_LOGIN=<your-dockerhub-username>
export DOCKER_PWD=<your-dockerhub-token>
mvn clean spring-boot:build-image \
  -Djava.version=21 \
  -Dimage.publish=false \
  -Dimage.name=${DOCKER_LOGIN}/spring-on-k8s:latest \
  -Ddocker.publishRegistry.username=${DOCKER_LOGIN} \
  -Ddocker.publishRegistry.password=${DOCKER_PWD}
```

Scan with Docker Scout:

```bash
docker scout cves andriykalashnykov/spring-on-k8s:latest
```

## Deploying to Kubernetes

### Production path (Carvel)

```bash
ytt -f ./k8s | kapp deploy -y --into-ns spring-on-k8s -a spring-on-k8s -f-
```

Wait for the `LoadBalancer` Service to receive an external IP:

```bash
kubectl -n spring-on-k8s get svc app

NAME   TYPE           CLUSTER-IP     EXTERNAL-IP    PORT(S)        AGE
app    LoadBalancer   10.96.10.42    192.0.2.10     80:31633/TCP   90s
```

Verify the ConfigMap override is applied:

```bash
curl "http://$(kubectl -n spring-on-k8s get svc app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/v1/hello"
Hello Kubernetes!
```

Undeploy:

```bash
kapp delete -a spring-on-k8s --yes
```

### Local E2E path (KinD + MetalLB)

```bash
make e2e                 # spins up cluster, deploys, runs assertions, tears down
```

Or step by step for debugging:

```bash
make kind-up             # create cluster + MetalLB + deploy
kubectl -n spring-on-k8s get svc app
# run manual curls against the assigned LoadBalancer IP
make kind-down           # tear down
```

## CI/CD

GitHub Actions runs on every push to `main`, tags `v*`, and pull requests. Non-source paths (`*.md`, `docs/`, images, `LICENSE`) are skipped via `paths-ignore`.

| Job | Triggers | Steps |
|-----|----------|-------|
| **static-check** | push, PR, tags | `make static-check` (format-check, Checkstyle, hadolint, compiler warnings, gitleaks, Trivy fs + config, actionlint, deps-prune-check) |
| **build** | push, PR, tags (needs: static-check) | `make build` |
| **test** | push, PR, tags (needs: static-check) | `make test` — unit layer (Surefire) |
| **integration-test** | push, PR, tags (needs: static-check) | `make integration-test` — in-process integration via Failsafe profile |
| **e2e** | push, PR, tags (needs: build, test) | `make e2e` — KinD + MetalLB, asserts ConfigMap override + LB wiring |
| **cve-check** | tags, weekly Monday 04:00 UTC, manual dispatch (needs: static-check) | `make cve-check` — OWASP dependency-check (fast with `NVD_API_KEY` secret; tag-gated so every release is scanned) |
| **docker** | push, PR, tags (needs: static-check, build, test) | Every push: build single-arch + Trivy image scan + smoke test. On tag: rebuild multi-arch (amd64, arm64), push to `ghcr.io`, cosign keyless OIDC sign |
| **ci-pass** | always (needs: static-check, build, test, integration-test, e2e, docker) | Single stable branch-protection gate. `cve-check` is intentionally excluded from the gate — transient external-dep issues (Sonatype rate limits, NVD slowness) shouldn't block releases; failures still show in the run UI |
| **cleanup** | weekly (Sunday) | Prune old workflow runs (retain 7 days, keep 5 minimum) |

### Required Secrets and Variables

| Name | Type | Used by | How to obtain |
|------|------|---------|---------------|
| `GITHUB_TOKEN` | Secret (default) | `docker` job (GHCR push), `cleanup` job (run delete) | Provided automatically by GitHub Actions |
| `NVD_API_KEY` | Secret (recommended) | `cve-check` job (NVD data source) | Free API key from [NIST NVD](https://nvd.nist.gov/developers/request-an-api-key). Without it, NVD uses an anonymous slow path (~15 min); with it, ~1 min |

Set via **Settings → Secrets and variables → Actions → New repository secret**. The same env var works locally (`export NVD_API_KEY=...`) for `make cve-check` runs.

OSS Index (Sonatype) is disabled for this project — Spring Boot's ~173-batch dependency tree exceeds free-tier rate limits even with authentication (server returns HTTP 401, which OWASP dep-check classifies as permanent and does not soft-fail). NVD is the sole CVE data source. If you want OSS Index back, upgrade to a paid Sonatype account and remove the `-DossIndexAnalyzerEnabled=false` flag from `make cve-check`.

### Image signing

On tag push (`v*`), the `docker` job signs the published image with [cosign](https://docs.sigstore.dev/) using keyless OIDC — no signing key to manage. Verify a published image with:

```bash
cosign verify ghcr.io/andriykalashnykov/spring-on-k8s:<tag> \
  --certificate-identity-regexp 'https://github\.com/AndriyKalashnykov/spring-on-k8s/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

[Renovate](https://docs.renovatebot.com/) keeps dependencies up to date with platform automerge enabled for minor/patch (3-day release-age buffer on majors).

## Contributing

Contributions welcome — open a PR.
