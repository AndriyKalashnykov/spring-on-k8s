# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Spring Boot 4.0.6 reference service for Kubernetes deployment. Exposes REST endpoints (`/v1/hello`, `/v1/bye`), Swagger UI, Prometheus metrics via Actuator, and K8s liveness / readiness probes. Application configuration is overridden at runtime by a mounted ConfigMap via Spring's `configtree:` property source.

## Build & Run Commands

Build / test / run:
```bash
make build                 # Package JAR (mvn clean package -DskipTests)
make test                  # Run unit tests (Surefire, excludes *IT.java)
make integration-test      # Run integration tests (Failsafe, *IT.java via integration-test profile)
make e2e                   # Full e2e: kind-up → curl LB assertions → kind-down
make run                   # Run locally (mvn spring-boot:run) at http://localhost:8080
```

Quality / security gates:
```bash
make format                # Apply google-java-format to Java sources
make static-check          # Composite gate: format-check, lint, secrets, trivy-fs, trivy-config, lint-ci, mermaid-lint, deps-prune-check
make mermaid-lint          # Validate Mermaid diagrams in README.md / CLAUDE.md against minlag/mermaid-cli
make cve-check             # OWASP dependency-check against NVD (canonical settings.xml flow; fast with NVD_API_KEY)
make vulncheck             # Portfolio-standard alias for cve-check
```

CI (local + act):
```bash
make ci                    # Full pipeline: deps → static-check → test → integration-test → build (format-check runs inside static-check)
make ci-run                # Run subset of GitHub Actions locally via act (static-check, build, test, integration-test, docker; skips e2e, cve-check, ci-pass)
make ci-run-tag            # Simulate a tag-push event under act (exercises tag-gated docker job; cosign signing fails — expected, no OIDC under act)
```

Docker image:
```bash
make image-build           # Build Docker image ($(DOCKER_IMAGE):$(DOCKER_TAG))
make image-run             # Run Docker container (port 8080)
make image-stop            # Stop Docker container
make image-push            # Push Docker image to registry
make docker-smoke-test     # Boot the locally-built spring-on-k8s:ci-scan image; verify /actuator/health/readiness within 60s (mirrors CI Gate 3)
make dast                  # Build image → boot → OWASP ZAP baseline → cleanup (local equivalent of CI DAST gate)
make dast-scan             # Run ZAP baseline against http://localhost:8080 (assumes container is already running)
```

Local Kubernetes (KinD + cloud-provider-kind):
```bash
make kind-up               # Bring stack up: create cluster → start cloud-provider-kind → load image → deploy
make kind-down             # Tear stack down (alias for kind-destroy)
# Granular targets (debugging flow only — kind-up composes these in order):
make kind-create kind-setup kind-load kind-deploy kind-undeploy kind-destroy
```

Toolchain / dependency management:
```bash
make deps                  # Install mise + every tool pinned in .mise.toml (idempotent)
make deps-check            # Show installed tool versions (mise list + docker/git)
make upgrade               # Show available Maven dependency updates (dry-run)
make upgrade-apply         # Apply latest Maven releases (prompts, mutates pom.xml)
make release VERSION=1.2.3 # Tag a release (with confirmation prompt)
make renovate-bootstrap    # Install Node + pnpm via mise so renovate-validate can run
make renovate-validate     # Validate Renovate configuration locally (npx renovate --platform=local)
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
- `make e2e` — `scripts/e2e-test.sh` runs against a KinD cluster with cloud-provider-kind (host-side LoadBalancer controller). Asserts the ConfigMap override reaches the app, probes report UP, Prometheus endpoint exposes metrics, and an unknown path returns 404.

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

Local e2e path uses KinD + cloud-provider-kind: `make e2e` creates the KinD cluster, runs `cloud-provider-kind` as a host-side Docker container on the `kind` network (it watches `Service: LoadBalancer` resources and assigns IPs from the KinD subnet), deploys, curls the LoadBalancer IP for `/v1/hello` expecting the ConfigMap override message "Hello Kubernetes!", and tears down. Lifecycle decomposes into `kind-create` → `kind-setup` (start cloud-provider-kind) → `kind-load` (load image into KinD) → `kind-deploy` (apply k8s manifests + `kubectl set image` to the actual digest) — orchestrated by `kind-up`; tear down via `kind-down` (alias for `kind-destroy`). The driver is `scripts/e2e-test.sh`. No separate installer script; the previous MetalLB-based scaffolding (`scripts/kind-metallb-setup.sh`) was removed in favor of this kind-team-maintained approach that works on every supported `kindest/node` version.

## Upgrade Backlog

Items surfaced by `/upgrade-analysis`; last re-run 2026-05-11.

- [ ] **Post-release manifest verification (first run after next tag push)** — after the hardened `docker` job first publishes with Pattern A (`provenance: false` + `sbom: false`, single-arch `linux/amd64`), run the three checks in README §"Post-release manifest verification": (a) `docker buildx imagetools inspect` shows `linux/amd64` with zero `unknown/unknown` entries, (b) GHCR Packages UI lists the package, (c) `cosign verify` succeeds. Once verified, delete this item.
- [ ] **Maven 4.0.0** is at RC-5 (latest: rc-5 published 2025-11-13); GA not yet released. Monitor; migrate when GA ships and plugin ecosystem signals stable 4.x support.
- [ ] **Spring Boot 4.0.7** — when it ships, re-evaluate the hibernate-validator suppression in `dependency-check-suppressions.xml` (CVE-2025-15104); drop it if the upstream fix lands.

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

- **Java:** Java 21 LTS for source/target/local build; **Java 25 LTS for the runtime image**. `<java.version>21</java.version>` in pom.xml + `JDK_VERSION := 21` in Makefile + `.mise.toml` `java = "temurin-21"` govern the build artifact (compiled bytecode targets Java 21). The Dockerfile runtime stage uses `eclipse-temurin:25-jre-alpine` for the longest-supported in-production JRE. Java 21 bytecode runs forward on Java 25 LTS — verified by the CI `docker` job's smoke test on every push.
- **Compiler:** `failOnWarning=true` is set on maven-compiler-plugin (pom.xml); any javac warning blocks the build
- **Docker image:** Multi-stage Dockerfile with `eclipse-temurin:25-jre-alpine` runtime (Adoptium-official Java 25 LTS, Alpine 3.23, digest-pinned), layered JAR via `spring-boot-maven-plugin`, runs as UID/GID `65532:65532` (created in the Dockerfile to match the distroless convention). Migrated from `gcr.io/distroless/java21-debian13:nonroot` on 2026-05-11 (Java 21 LTS → 25 LTS bump landed via Renovate shortly after); rationale and tradeoffs in [`docs/adr/0001-runtime-base-image.md`](docs/adr/0001-runtime-base-image.md). BusyBox shell is present (good for `kubectl exec` debugging) — small attack-surface tradeoff documented in the ADR.
- **Buildpacks alternative:** `mvn spring-boot:build-image` with Paketo builder
- **CI workflows** (`.github/workflows/`):
  - `ci.yml` — 9 jobs: `changes` (path filter via `dorny/paths-filter`) → `static-check` → { `build`, `test`, `integration-test` } (parallel) → { `e2e` (needs build + test), `docker` (needs all three + cve-check), `cve-check` (tag/weekly/manual only) } → `ci-pass` (branch-protection gate, `if: always()`, treats `skipped` as PASS). Path filtering happens **inside** the workflow, not at the trigger level — Repository Rulesets requiring `ci-pass` would deadlock on doc-only changes if `paths-ignore` filtered triggers (no run → no `ci-pass` status). Every code-running job gates on `needs.changes.outputs.code == 'true'`; doc-only PRs skip the heavy jobs and `ci-pass` still goes green. Every job uses `jdx/mise-action` to provision java+maven+CLI tools from `.mise.toml`; `actions/cache` handles `~/.m2/repository` separately. The `docker` job follows Pattern A, single-arch (`linux/amd64`): Gates 1–3 (build + Trivy image scan blocking CRITICAL/HIGH with `scanners=vuln,secret,misconfig` + smoke test via `make docker-smoke-test`) run on every push, then DAST runs inline (OWASP ZAP baseline `-I` warn-only against the running smoke container; ZAP image is `actions/cache`-d so subsequent runs load in seconds; all DAST steps gated by `vars.ACT != 'true'`); Gate 4 publish build + Gate 5 cosign keyless signing happen only on `v*` tags. `provenance: false` + `sbom: false` keep the image index clean. Multi-arch (amd64+arm64) is intentionally disabled — the project ships a single linux/amd64 image (`docker/setup-qemu-action` is loaded for canonical-template parity, harmless on single-arch). The DAST steps (formerly a separate `dast` job, since 2026-05-03) live inside `docker` after Gate 3 to share the already-built `spring-on-k8s:ci-scan` image and the running smoke container — eliminates the duplicate ~30–60s build per push and the duplicated cleanup. Run `make dast` directly to cover the act-gap locally
  - `cleanup-runs.yml` (workflow `Cleanup old workflow runs`) — weekly Sunday 00:00 UTC, two jobs: `cleanup-runs` prunes old workflow runs via `gh run delete` (retain 7 days, keep 5 minimum); `cleanup-caches` deletes actions caches scoped to deleted refs (frees room against the 10 GB repo cache limit)
- **Version manager:** [mise](https://mise.jdx.dev/) is the single source of truth for every CLI tool the build needs — Java, Maven, Node, kubectl, kind, act, hadolint, gitleaks, trivy, actionlint, shellcheck all pin in `.mise.toml`. `make deps` bootstraps mise (if missing) and runs `mise install`. The Makefile retains a short list of `_VERSION` constants only for things mise does not manage: `GJF_VERSION` (google-java-format JAR), `DEPCHECK_VERSION` (Maven plugin), `MERMAID_CLI_VERSION` (Docker image), `KIND_NODE_IMAGE` (Docker image digest — bumped manually in tandem with kind in `.mise.toml`; not Renovate-trackable), `CLOUD_PROVIDER_KIND_VERSION` (Docker image tag on registry.k8s.io), `ACT_UBUNTU_VERSION` (catthehacker/ubuntu image used by `make ci-run`/`ci-run-tag`), `ZAP_VERSION` (`ghcr.io/zaproxy/zaproxy` Docker image used by `make dast` and the inline DAST steps inside the `docker` CI job — also duplicated as a workflow-level `env:` literal in `ci.yml`; both are Renovate-tracked via the workflow `customManagers` regex, so a Renovate PR bumps them together)
- **Renovate:** `renovate.json` drives automated dependency updates. Enabled managers: `maven`, `github-actions`, `dockerfile`, `kubernetes` (scoped to `k8s/*.ya?ml`), `mise` (native `.mise.toml` reader), and `custom.regex`. Three `customManagers` regexes track inline `# renovate:` comments — one for the Makefile, one for `.mise.toml`, and one for `.github/workflows/*.ya?ml` `env:` literals (covers `ZAP_VERSION` duplicated between the Makefile and the `docker` job's `env:` block)
- **Trivy suppressions:** `.trivyignore` documents demo-scope K8s hardening exceptions and upstream CVEs tracked by Renovate
- **`docker` job gates on `cve-check`** via the GitHub idiom `if: ${{ !failure() && !cancelled() && needs.changes.outputs.code == 'true' }}`. `cve-check` is in `docker.needs` so a real CVE failure on a tag push blocks the release; on regular pushes `cve-check` is `skipped` (it's tag/schedule/manual-only) and `!failure() && !cancelled()` lets `docker` proceed regardless. `ci-pass` lists both in `needs:` for branch-protection completeness
- **`k8s/deployment.yml` uses `image: ghcr.io/.../spring-on-k8s:latest`:** intentional template-style placeholder. The actual tag is set at deploy time — `make kind-deploy` runs `kubectl set image deployment/app "app=$(DOCKER_IMAGE):$(DOCKER_TAG)"` after `kubectl apply`, and the Carvel production path uses `ytt` overlays. Renovate's `kubernetes` manager scans the file but treats `:latest` as a no-op (nothing to bump), which is fine
- **Architecture diagrams:** three inline Mermaid diagrams in README.md (C4 Context under the description, C4 Container + C4 Deployment in the `## Architecture` section). Lint target: `make mermaid-lint` uses the `minlag/mermaid-cli` Docker image (same engine GitHub uses to render). Wired into `make static-check`. No separate PlantUML toolchain — single-service + modest K8s topology fits inside Mermaid C4 cleanly
- **e2e guard rails (`scripts/e2e-test.sh`)** — three load-bearing details a future contributor must preserve: (1) pod selection uses `role=app` label (matches `k8s/deployment.yml` `spec.selector.matchLabels`); (2) `assert_pod_ready` filters terminating pods via `jq` `.metadata.deletionTimestamp == null` (kubectl jsonpath's subset has no negation operator — using `[?(!@...)]` fails with `unrecognized character in action: U+0021 '!'`); (3) `make docker-smoke-test` accepts both named (`nonroot:nonroot`) and numeric (`65532:65532`) container User strings via a `case` against root forms — the runtime image sets numeric UID/GID
- **All `make` targets depend on `deps`** — tool availability is checked / auto-installed before execution
