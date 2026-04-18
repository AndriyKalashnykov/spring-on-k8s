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
make deps                  # Install mise + every tool pinned in .mise.toml (idempotent)
make deps-check            # Show installed tool versions (mise list + docker/git)
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

## Upgrade Backlog

Items surfaced by `/upgrade-analysis` 2026-04-13. Re-run 2026-04-18:

- [x] ~~`KIND_VERSION` pinned at non-existent 0.32.0~~ → downgraded to 0.31.0 + `kindest/node:v1.35.0@sha256:452d707d...`
- [x] ~~google-java-format 1.24.0 → 1.35.0~~ → bumped, GJF jar re-downloaded
- [x] ~~Maven 3.9.9 → 3.9.14~~ → bumped in Makefile + Dockerfile ARG default (3.9.14 → 3.9.15 pending in PR #201)
- [x] ~~metallb → 0.15.3, kubectl → 1.35.3, mermaid-cli → 11.12.0, hadolint → 2.14.0, maven-dependency-plugin → 3.10.0~~ → all bumped
- [x] ~~Mise migration: 8 CLI tools (act, hadolint, gitleaks, trivy, actionlint, shellcheck, kind, kubectl) moved from Makefile `_VERSION` pins to `.mise.toml`~~ → single source of truth
- [x] ~~kubectl 1.35.3 → 1.35.4~~ (2026-04-18)
- [x] ~~Paketo builder 0.4.286 → 0.4.563~~ (`pom.xml`; buildpacks-only path, 277 versions behind)
- [x] ~~Dockerfile ARG Renovate blind spot~~ → `# renovate:` annotation added to `Dockerfile:1` ARG MVN_VERSION, custom-regex added to `renovate.json`
- [x] ~~Distroless `java21-debian12:debug` → `java21-debian13:nonroot`~~ (2026-04-18) — ahead of Debian 12 EOL 2026-06-10. Smoke-tested: readiness UP, `/v1/hello` responds, container runs as nonroot:nonroot. Reverted: if troubleshooting via `kubectl exec` is needed, temporarily swap the tag back to `:debug` (keep the same image path / digest pattern).
- [ ] **Post-release manifest verification (first run after next tag push)** — after the hardened `docker` job first publishes with Pattern A (`provenance: false` + `sbom: false`, multi-arch), run the three checks documented in README §"Post-release manifest verification": (a) `docker buildx imagetools inspect` lists linux/amd64 + linux/arm64 with zero `unknown/unknown` entries, (b) GHCR Packages UI shows the "OS / Arch" tab, (c) `cosign verify` succeeds. Once verified, delete this item.
- [ ] **Maven 4.0.0** is at RC-5 (latest: rc-5 published 2025-11-13); GA not yet released. Monitor; migrate when GA ships and plugin ecosystem signals stable 4.x support.
- [ ] **Spring Boot 4.0.6+** not yet released (latest stable: 4.0.5 published 2026-03-26). When it ships, check hibernate-validator for CVE-2025-15104 fix; remove the corresponding entry from `dependency-check-suppressions.xml` if the upstream fix lands.

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

- **Java:** 21 across the board — `<java.version>` in pom.xml, `JDK_VERSION` in Makefile (used for Docker build args), `.mise.toml` `java = "temurin-21"` is the single source of truth consumed by both local `make deps` and the CI `jdx/mise-action` step
- **Compiler:** `failOnWarning=true` is set on maven-compiler-plugin (pom.xml); any javac warning blocks the build
- **Docker image:** Multi-stage Dockerfile with distroless runtime (`gcr.io/distroless/java21-debian13:nonroot`, digest-pinned), layered JAR via `spring-boot-maven-plugin`, runs as `nonroot:nonroot` (no shell / no coreutils in runtime). Debian 13 base (Debian 12 EOL 2026-06-10).
- **Buildpacks alternative:** `mvn spring-boot:build-image` with Paketo builder
- **CI workflows** (`.github/workflows/`):
  - `ci.yml` — 8 jobs: `static-check` → { `build`, `test`, `integration-test` } (parallel) → { `e2e` (needs build + test), `docker` (needs all three), `cve-check` (tag/weekly/manual only) } → `ci-pass` (branch-protection gate, `if: always()`). Every job uses `jdx/mise-action` to provision java+maven+CLI tools from `.mise.toml`; `actions/cache` handles `~/.m2/repository` separately. The `docker` job follows Pattern A: Gates 1–3 (build + Trivy image scan blocking CRITICAL/HIGH + smoke test) plus Gate 4 multi-arch build run on every push (catches arm64 cross-compile regressions early); push to GHCR + cosign keyless signing happen only on `v*` tags. `provenance: false` + `sbom: false` keep the image index clean
  - `cleanup-runs.yml` — weekly (Sunday) run pruning via `gh run delete` (retain 7 days, keep 5 minimum)
- **Version manager:** [mise](https://mise.jdx.dev/) is the single source of truth for every CLI tool the build needs — Java, Maven, Node, kubectl, kind, act, hadolint, gitleaks, trivy, actionlint, shellcheck all pin in `.mise.toml`. `make deps` bootstraps mise (if missing) and runs `mise install`. The Makefile retains a short list of `_VERSION` constants only for things mise does not manage: `GJF_VERSION` (google-java-format JAR), `DEPCHECK_VERSION` (Maven plugin), `MERMAID_CLI_VERSION` (Docker image), `KIND_NODE_IMAGE` (Docker image digest), `METALLB_VERSION` (manifest URL)
- **Renovate:** `renovate.json` drives automated dependency updates. Two `customManagers` regexes track both the `.mise.toml` `# renovate:` inline comments and the remaining Makefile `_VERSION` constants
- **Trivy suppressions:** `.trivyignore` documents demo-scope K8s hardening exceptions and upstream CVEs tracked by Renovate
- **Architecture diagrams:** three inline Mermaid diagrams in README.md (C4 Context under the description, C4 Container + C4 Deployment in the `## Architecture` section). Lint target: `make mermaid-lint` uses the `minlag/mermaid-cli` Docker image (same engine GitHub uses to render). Wired into `make static-check`. No separate PlantUML toolchain — single-service + modest K8s topology fits inside Mermaid C4 cleanly
- **All `make` targets depend on `deps`** — tool availability is checked / auto-installed before execution
