.DEFAULT_GOAL := help

SHELL := /bin/bash
# mise shims come first, then ~/.local/bin tool installs, then system PATH.
export PATH := $(HOME)/.local/share/mise/shims:$(HOME)/.local/bin:$(PATH)

# === Tool Versions (pinned) ===
# Single source of truth for every mise-managed tool is .mise.toml. The
# constants below are the exceptions — values that are not mise-managed
# (Maven plugins, JAR downloads, Docker image pins, literals consumed by
# Docker build args).

# --- Group 1: major-only, NOT Renovate-tracked (manual bump on LTS rollover) ---
# JDK_VERSION is the major-only Java version consumed as a Docker `--build-arg`
# (Dockerfile `ARG JDK_VERSION`). Must stay in sync with `.mise.toml`
# (`java = "temurin-21"`) and `pom.xml` `<java.version>21</java.version>`.
# Analogous to the NODE_VERSION exemption in the `/renovate` skill — bumps
# are coordinated manually across the four files when a new Java LTS ships.
JDK_VERSION := 21

# --- Group 2: Renovate-tracked tool versions (one inline `# renovate:` per pin) ---
# renovate: datasource=maven depName=com.google.googlejavaformat:google-java-format
GJF_VERSION := 1.35.0
# renovate: datasource=maven depName=org.owasp:dependency-check-maven
DEPCHECK_VERSION := 12.2.2
# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.12.0
# renovate: datasource=github-releases depName=zaproxy/zaproxy extractVersion=^v(?<version>.*)$$
ZAP_VERSION := 2.17.0
# KIND_NODE_IMAGE is tied to the kind release in .mise.toml; each kind
# release ships a matching node image tag (digest from kind release notes).
# Bump manually whenever Renovate bumps `kind` in `.mise.toml` — the value
# (tag@digest concatenation) is not independently Renovate-trackable per the
# `/renovate` skill's "Not independently trackable" exception.
KIND_NODE_IMAGE := kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f
# cloud-provider-kind runs as a host-side Docker container on the `kind`
# network; watches Services of type LoadBalancer and allocates IPs from the
# KinD Docker subnet. Kind-team maintained (kubernetes-sigs/cloud-provider-kind),
# works on every supported kindest/node version. Tracked via the docker
# datasource so Renovate only proposes versions that are actually published
# to registry.k8s.io (a github-release without a corresponding image push
# would be unpullable).
# renovate: datasource=docker depName=registry.k8s.io/cloud-provider-kind/cloud-controller-manager
CLOUD_PROVIDER_KIND_VERSION := v0.10.0

# act runner image — pinned so `make ci-run` produces deterministic local
# CI runs across machines.
# renovate: datasource=docker depName=catthehacker/ubuntu versioning=loose
ACT_UBUNTU_VERSION := act-24.04

# === Docker image coordinates ===
APP_NAME        := spring-on-k8s
DOCKER_REGISTRY := andriykalashnykov
DOCKER_IMAGE    := $(DOCKER_REGISTRY)/$(APP_NAME)
CURRENTTAG      := $(shell git describe --tags --abbrev=0 2>/dev/null || echo dev)
DOCKER_TAG      := $(CURRENTTAG)

# KinD cluster name follows the project APP_NAME so multiple projects can coexist
# on one laptop without collision.
KIND_CLUSTER_NAME := $(APP_NAME)

# Pin every kubectl call to OUR cluster's context. A parallel `make` from another
# KinD-using project on the same host can otherwise overwrite the kubeconfig's
# current-context via `kubectl config use-context`, sending bare-`kubectl` calls
# to the wrong cluster mid-recipe (silent failure: namespaces "vanish",
# rollouts wait on non-existent Deployments).
KUBECTL := kubectl --context=kind-$(KIND_CLUSTER_NAME)

# Local-only image tag and container names used by docker-smoke-test / dast.
SMOKE_IMAGE     := $(APP_NAME):ci-scan
SMOKE_CONTAINER := $(APP_NAME)-smoke
DAST_CONTAINER  := $(APP_NAME)-test

GJF_JAR := $(HOME)/.local/lib/google-java-format-$(GJF_VERSION).jar

# google-java-format uses internal JDK compiler APIs — requires --add-exports on JDK 16+
GJF_JAVA_OPTS := --add-exports jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.main=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.parser=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.processing=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo
	@echo "Commands :"
	@echo
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-22s\033[0m - %s\n", $$1, $$2}'

#deps: @ Install mise + all tools pinned in .mise.toml (idempotent)
deps:
	@command -v mise >/dev/null 2>&1 || { \
		echo "Installing mise (no root required, to ~/.local/bin)..."; \
		curl -fsSL https://mise.run | sh; \
	}
	@mise install --yes
	@command -v docker >/dev/null 2>&1 || { echo "Error: docker is not installed or not in PATH"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo "Error: git is not installed or not in PATH"; exit 1; }

#deps-check: @ Show installed tool versions from mise
deps-check:
	@command -v mise >/dev/null 2>&1 && mise list || echo "mise not installed — run 'make deps'"
	@command -v docker >/dev/null 2>&1 && echo "  $$(docker --version)" || echo "  docker: NOT INSTALLED"
	@command -v git >/dev/null 2>&1 && echo "  $$(git --version)" || echo "  git: NOT INSTALLED"

#deps-gjf: @ Download google-java-format JAR (not managed by mise — JAR download only)
deps-gjf:
	@mkdir -p $(HOME)/.local/lib
	@test -f $(GJF_JAR) || { \
		echo "Downloading google-java-format $(GJF_VERSION) to $(GJF_JAR)..."; \
		curl -sSfL -o $(GJF_JAR) "https://github.com/google/google-java-format/releases/download/v$(GJF_VERSION)/google-java-format-$(GJF_VERSION)-all-deps.jar"; \
	}

#clean: @ Cleanup build artifacts (no toolchain required)
clean:
	@rm -rf target zap-output

#build: @ Build project
build: deps
	@mvn clean package -DskipTests

#test: @ Run unit tests (fast, Surefire-discovered)
test: deps
	@mvn test

#integration-test: @ Run integration tests (*IT.java via Failsafe profile; in-process Spring Boot)
integration-test: deps
	@mvn -B verify -P integration-test -Dsurefire.skip=true

#run: @ Run project
run: deps
	@mvn clean spring-boot:run -Djava.version=$(JDK_VERSION)

#format: @ Format Java sources with google-java-format (writes changes)
format: deps-gjf
	@find src/main/java src/test/java -name "*.java" -print0 | xargs -0 java $(GJF_JAVA_OPTS) -jar $(GJF_JAR) --replace
	@echo "Formatting complete."

#format-check: @ Verify Java sources are google-java-format compliant (no changes)
format-check: deps-gjf
	@set -e; \
	CHANGED=$$(find src/main/java src/test/java -name "*.java" -print0 | xargs -0 java $(GJF_JAVA_OPTS) -jar $(GJF_JAR) --dry-run); \
	if [ -n "$$CHANGED" ]; then \
		echo "ERROR: The following files are not formatted. Run 'make format' to fix:"; \
		echo "$$CHANGED" | sed 's/^/  /'; \
		exit 1; \
	fi; \
	echo "All Java sources are correctly formatted."

#lint: @ Run Maven compiler warnings + Checkstyle + hadolint Dockerfile + scripts +x guard
lint: deps
	@mvn -B compile
	@mvn -B checkstyle:check
	@hadolint Dockerfile
	@NONEXEC=$$(find scripts -name '*.sh' -not -executable -print 2>/dev/null); \
	if [ -n "$$NONEXEC" ]; then \
		echo "ERROR: shell scripts missing executable bit:"; \
		echo "$$NONEXEC" | sed 's/^/  /'; \
		echo "Fix with: chmod +x <file>"; \
		exit 1; \
	fi

#cve-check: @ OWASP dependency-check vulnerability scan (NVD only)
# Data source: NVD (requires NVD_API_KEY for fast path — free key from
# https://nvd.nist.gov/developers/request-an-api-key).
#
# OSS Index is intentionally disabled. Spring Boot's dependency tree
# submits ~173 component-report batches per scan, which exceeds even the
# authenticated free-tier Sonatype rate limit. The analyzer fails midway
# with HTTP 401 (bad-auth classification on rate-limit), and the
# `ossIndexAnalyzerWarnOnlyOnRemoteErrors=true` flag does not catch 401s.
# OSS_INDEX_USER / OSS_INDEX_TOKEN repo secrets are kept for local dev use
# and for potential future re-enablement (paid tier or reduced dep tree).
cve-check: deps
	@# Canonical OWASP dependency-check secret pattern (rules/common/security.md):
	@# write a private settings.xml with <server id="nvd"><password>...</password></server>
	@# via the bash-builtin printf (no fork → no argv leak), then pass the public
	@# -DnvdApiServerId=nvd flag. The pom.xml form `${env.NVD_API_KEY}` was avoided
	@# because `mvn help:effective-pom` would interpolate the live value into stdout.
	@if [ -z "$$NVD_API_KEY" ]; then \
		echo "WARN: NVD_API_KEY not set — NVD slow path may take 10+ min."; \
		mvn -B org.owasp:dependency-check-maven:$(DEPCHECK_VERSION):check \
			-DsuppressionFiles=dependency-check-suppressions.xml \
			-DossindexAnalyzerEnabled=false; \
	else \
		echo "NVD: authenticated (fast path)"; \
		SETTINGS=$$(mktemp -t mvn-cve-settings-XXXXXX.xml); \
		trap 'rm -f "$$SETTINGS"' EXIT; \
		umask 077; \
		printf '<settings><servers><server><id>nvd</id><password>%s</password></server></servers></settings>\n' "$$NVD_API_KEY" > "$$SETTINGS"; \
		mvn -B -s "$$SETTINGS" org.owasp:dependency-check-maven:$(DEPCHECK_VERSION):check \
			-DsuppressionFiles=dependency-check-suppressions.xml \
			-DossindexAnalyzerEnabled=false \
			-DnvdApiServerId=nvd; \
	fi

#vulncheck: @ Alias for cve-check (portfolio-standard target name)
vulncheck: cve-check

#secrets: @ Scan working tree for secrets via gitleaks (CI-oriented; use secrets-history for full git audit)
secrets: deps
	@gitleaks detect --source . --no-git --verbose --redact --no-banner

#secrets-history: @ Full git history secret audit (slow, for one-time auditing)
secrets-history: deps
	@gitleaks detect --source . --verbose --redact --no-banner

#trivy-fs: @ Trivy filesystem scan (vulnerabilities, secrets, misconfigs)
trivy-fs: deps
	@trivy fs --scanners vuln,secret,misconfig --exit-code 1 --severity HIGH,CRITICAL --ignorefile .trivyignore .

#trivy-config: @ Trivy IaC/K8s manifest scan
trivy-config: deps
	@trivy config --exit-code 1 --severity HIGH,CRITICAL --ignorefile .trivyignore k8s/

#lint-ci: @ Lint GitHub Actions workflows (actionlint + shellcheck via mise)
lint-ci: deps
	@actionlint
	@echo "Workflow lint complete."

#mermaid-lint: @ Validate Mermaid diagrams in markdown files
mermaid-lint:
	@command -v docker >/dev/null 2>&1 || { echo "ERROR: docker required for mermaid-lint"; exit 1; }
	@set -euo pipefail; \
	MD_FILES=$$(grep -lF '```mermaid' README.md CLAUDE.md 2>/dev/null || true); \
	if [ -z "$$MD_FILES" ]; then \
		echo "No Mermaid blocks found — skipping."; \
		exit 0; \
	fi; \
	for attempt in 1 2 3; do \
		if docker pull --quiet minlag/mermaid-cli:$(MERMAID_CLI_VERSION) >/dev/null 2>&1; then \
			break; \
		fi; \
		[ "$$attempt" -lt 3 ] && { echo "  docker pull attempt $$attempt failed; retrying..."; sleep $$((attempt * 5)); } || { \
			echo "ERROR: docker pull minlag/mermaid-cli:$(MERMAID_CLI_VERSION) failed after 3 attempts"; \
			exit 1; \
		}; \
	done; \
	FAILED=0; \
	for md in $$MD_FILES; do \
		echo "Validating Mermaid blocks in $$md..."; \
		LOG=$$(mktemp); \
		if docker run --rm -v "$$PWD:/data:ro" \
			minlag/mermaid-cli:$(MERMAID_CLI_VERSION) \
			-i "/data/$$md" -o "/tmp/$$(basename $$md .md).svg" >"$$LOG" 2>&1; then \
			echo "  ✓ All blocks rendered cleanly."; \
		else \
			echo "  ✗ Parse error in $$md:"; \
			sed 's/^/    /' "$$LOG"; \
			FAILED=$$((FAILED + 1)); \
		fi; \
		rm -f "$$LOG"; \
	done; \
	if [ "$$FAILED" -gt 0 ]; then \
		echo "Mermaid lint: $$FAILED file(s) had parse errors."; \
		exit 1; \
	fi

#deps-prune: @ Report unused/undeclared Maven dependencies (informational)
deps-prune: deps
	@mvn -B dependency:analyze -DignoreNonCompile=true

#deps-prune-check: @ Fail if unused/undeclared Maven dependencies are found
deps-prune-check: deps
	@mvn -B dependency:analyze -DignoreNonCompile=true -DfailOnWarning=true

#static-check: @ Fast composite quality gate (format-check, lint, secrets, trivy-fs, trivy-config, lint-ci, mermaid-lint, deps-prune-check)
# vulncheck/cve-check is intentionally excluded — runs separately as a tag /
# weekly / manual job in CI. NVD slow path adds 10+ min when NVD_API_KEY is
# absent, which would dominate every static-check run. See CLAUDE.md.
static-check: format-check lint secrets trivy-fs trivy-config lint-ci mermaid-lint deps-prune-check
	@echo "All static checks passed. Run 'make cve-check' separately for vulnerability scan (slow)."

#upgrade: @ Show available Maven dependency updates (dry-run)
upgrade: deps
	@mvn versions:display-dependency-updates

#upgrade-apply: @ Apply latest Maven releases (mutates pom.xml — prompts for confirmation)
upgrade-apply: deps
	@git diff --quiet pom.xml || { echo "Error: pom.xml has uncommitted changes; commit or stash first."; exit 1; }
	@bash -c 'read -p "Apply latest releases to pom.xml? [y/N] " ans && [ "$${ans:-N}" = y ] || { echo "Aborted."; exit 1; }'
	@mvn versions:use-latest-releases
	@mvn versions:commit

#image-build: @ Build Docker image (see DOCKER_IMAGE / DOCKER_TAG)
image-build: build
	@docker buildx build --load -t $(DOCKER_IMAGE):$(DOCKER_TAG) --build-arg JDK_VENDOR=eclipse-temurin --build-arg JDK_VERSION=$(JDK_VERSION) .

#docker-smoke-test: @ Boot the locally-built image and verify /actuator/health/readiness reports UP within 60s (leaves container running)
# Shared by the CI `docker` and `dast` jobs. The caller is responsible for the
# follow-up `docker rm -f $(SMOKE_CONTAINER)` cleanup step (already wired into
# both CI jobs as `if: always()` steps; the local `make dast` target runs the
# cleanup in its own recipe).
docker-smoke-test: deps
	@docker rm -f $(SMOKE_CONTAINER) 2>/dev/null || true
	@docker run -d --name $(SMOKE_CONTAINER) -p 8080:8080 $(SMOKE_IMAGE) >/dev/null
	@# Verify the runtime image exposes the documented port and runs as nonroot.
	@USER=$$(docker inspect -f '{{.Config.User}}' $(SMOKE_CONTAINER)); \
	if [ "$$USER" != "nonroot:nonroot" ]; then \
		echo "Smoke test FAIL: container User='$$USER' (expected 'nonroot:nonroot')"; \
		docker rm -f $(SMOKE_CONTAINER) >/dev/null 2>&1 || true; \
		exit 1; \
	fi; \
	echo "Image runtime user: $$USER"
	@PORTS=$$(docker inspect -f '{{range $$p, $$_ := .Config.ExposedPorts}}{{$$p}} {{end}}' $(SMOKE_CONTAINER)); \
	if ! echo "$$PORTS" | grep -q '8080/tcp'; then \
		echo "Smoke test FAIL: container ExposedPorts='$$PORTS' (expected to contain 8080/tcp)"; \
		docker rm -f $(SMOKE_CONTAINER) >/dev/null 2>&1 || true; \
		exit 1; \
	fi; \
	echo "Image exposes: $$PORTS"
	@for _ in $$(seq 1 30); do \
		if curl -sf http://localhost:8080/actuator/health/readiness 2>/dev/null | grep -q '"status":"UP"'; then \
			echo "Smoke test PASS: /actuator/health/readiness reports UP"; \
			exit 0; \
		fi; \
		sleep 2; \
	done; \
	echo "Smoke test FAIL: /actuator/health/readiness did not report UP within 60s"; \
	docker logs $(SMOKE_CONTAINER) 2>&1 || true; \
	docker rm -f $(SMOKE_CONTAINER) >/dev/null 2>&1 || true; \
	exit 1

#dast-scan: @ Run OWASP ZAP baseline against http://localhost:8080 (assumes container is running)
dast-scan: deps
	@mkdir -p zap-output && chmod 777 zap-output
	@docker run --rm --network host \
		-v "$$PWD/zap-output:/zap/wrk:rw" \
		ghcr.io/zaproxy/zaproxy:$(ZAP_VERSION) \
		zap-baseline.py \
			-t http://localhost:8080 \
			-I \
			-r zap-report.html \
			-J zap-report.json \
			-w zap-report.md
	@echo "DAST report: $$PWD/zap-output/zap-report.html"

#dast: @ Build image, boot, run ZAP baseline DAST scan, cleanup (local equivalent of the CI docker job's DAST steps)
dast: image-build
	@docker rm -f $(DAST_CONTAINER) 2>/dev/null || true
	@docker run -d --name $(DAST_CONTAINER) -p 8080:8080 $(DOCKER_IMAGE):$(DOCKER_TAG) >/dev/null
	@echo "Waiting for container readiness..."
	@end=$$(($$(date +%s) + 60)); \
	while [ $$(date +%s) -lt $$end ]; do \
		curl -fsS http://localhost:8080/actuator/health/readiness 2>/dev/null | grep -q '"status":"UP"' && break; \
		sleep 1; \
	done
	@$(MAKE) dast-scan || EXIT=$$?; \
	docker rm -f $(DAST_CONTAINER) >/dev/null 2>&1 || true; \
	exit $${EXIT:-0}

#image-run: @ Run Docker container
image-run: deps image-stop
	@docker run --rm -p 8080:8080 --name $(APP_NAME) $(DOCKER_IMAGE):$(DOCKER_TAG)

#image-stop: @ Stop Docker container
image-stop: deps
	@docker stop $(APP_NAME) 2>/dev/null || true

#image-push: @ Push Docker image to registry
image-push: image-build
	@if [ -n "$$GH_ACCESS_TOKEN" ] && [ "$(DOCKER_REGISTRY)" = "ghcr.io" ]; then \
		echo "$$GH_ACCESS_TOKEN" | docker login ghcr.io -u $$GITHUB_ACTOR --password-stdin; \
	fi
	@docker push $(DOCKER_IMAGE):$(DOCKER_TAG)

#ci: @ Run full CI pipeline (deps, static-check, test, integration-test, build)
# format-check is invoked transitively by static-check (Makefile:246) — listing it
# here would run it twice per `make ci`.
ci: deps static-check test integration-test build
	@echo "CI pipeline completed successfully."

#ci-run: @ Run a subset of GitHub Actions workflow locally via act (excludes e2e, cve-check, ci-pass)
# Skipped jobs and rationale (cross-reference: ci.yml job keys must match):
#   e2e       — requires KinD inside act (docker-in-docker is flaky); use `make e2e` directly.
#   cve-check — gated on tags/schedule/manual in ci.yml; requires NVD_API_KEY for fast path.
#   ci-pass   — meta aggregator (`if: always()` over upstream needs); nothing to validate locally.
# If you rename a job in ci.yml, update this comment AND CLAUDE.md "ci.yml" bullet so the
# documentation stays in sync with the workflow.
# Forwards GH_ACCESS_TOKEN, NVD_API_KEY, OSS_INDEX_USER, OSS_INDEX_TOKEN to act
# only when set on the host, so the local run mirrors the CI secret surface.
ci-run: deps
	@docker container prune -f 2>/dev/null || true
	@# Synthesize a push event payload that includes `repository.default_branch`
	@# so the `changes` job's dorny/paths-filter step can resolve its base ref
	@# (act's default push event omits this, breaking the action with
	@# "This action requires 'base' input to be configured...").
	@echo '{"ref":"refs/heads/main","repository":{"default_branch":"main","name":"spring-on-k8s","full_name":"AndriyKalashnykov/spring-on-k8s"}}' > /tmp/act-push-event.json
	@ACT_PORT=$$(shuf -i 40000-59999 -n 1); \
	ARTIFACT_PATH=$$(mktemp -d -t act-artifacts.XXXXXX); \
	secret_args=(); \
	for v in GH_ACCESS_TOKEN NVD_API_KEY OSS_INDEX_USER OSS_INDEX_TOKEN; do \
		if [ -n "$${!v:-}" ]; then secret_args+=(--secret "$$v"); fi; \
	done; \
	for j in static-check build test integration-test docker; do \
		echo "==== act push --job $$j ===="; \
		act push --job $$j --container-architecture linux/amd64 \
			--pull=false \
			--var ACT=true \
			--eventpath /tmp/act-push-event.json \
			-P ubuntu-24.04=catthehacker/ubuntu:$(ACT_UBUNTU_VERSION) \
			--artifact-server-port "$$ACT_PORT" \
			--artifact-server-path "$$ARTIFACT_PATH" \
			"$${secret_args[@]}" || exit 1; \
	done

#ci-run-tag: @ Simulate a tag push under act (exercises tag-gated docker job; cosign signing fails — expected, no OIDC under act)
# The `dast` job is skipped under act (`vars.ACT == 'true'`) — its docker-in-docker
# bind mount of `$GITHUB_WORKSPACE/zap-output` does not round-trip through the host
# Docker daemon. Run `make dast` directly to cover that ground locally.
ci-run-tag: deps
	@docker container prune -f 2>/dev/null || true
	@TAG="$$(git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)"; \
		echo '{"ref":"refs/tags/'"$$TAG"'","ref_type":"tag"}' > /tmp/act-tag-event.json
	@ACT_PORT=$$(shuf -i 40000-59999 -n 1); \
	ARTIFACT_PATH=$$(mktemp -d -t act-artifacts.XXXXXX); \
	act push \
		--eventpath /tmp/act-tag-event.json \
		--container-architecture linux/amd64 \
		--pull=false \
		--var ACT=true \
		-P ubuntu-24.04=catthehacker/ubuntu:$(ACT_UBUNTU_VERSION) \
		--artifact-server-port "$$ACT_PORT" \
		--artifact-server-path "$$ARTIFACT_PATH" || true
	@echo "Note: cosign signing fails under act (no OIDC) — expected. dast job is skipped under act."

#kind-create: @ Create KinD cluster
kind-create: deps
	@kind get clusters 2>/dev/null | grep -q "^$(KIND_CLUSTER_NAME)$$" || { \
		echo "Creating KinD cluster '$(KIND_CLUSTER_NAME)' with node image $(KIND_NODE_IMAGE)..."; \
		kind create cluster --name $(KIND_CLUSTER_NAME) --image $(KIND_NODE_IMAGE); \
	}
	@$(KUBECTL) cluster-info

#kind-setup: @ Start cloud-provider-kind for LoadBalancer services
kind-setup: kind-create
	@# cloud-provider-kind runs on the host (not in the cluster), watches
	@# Services of type LoadBalancer on the `kind` Docker network, and
	@# allocates IPs from the KinD subnet. No in-cluster install, no IP
	@# pool to configure. Idempotent: replace any existing container.
	@docker rm -f cloud-provider-kind >/dev/null 2>&1 || true
	@echo "Starting cloud-provider-kind $(CLOUD_PROVIDER_KIND_VERSION)..."
	@docker run --rm -d \
		--name cloud-provider-kind \
		--network kind \
		-v /var/run/docker.sock:/var/run/docker.sock \
		registry.k8s.io/cloud-provider-kind/cloud-controller-manager:$(CLOUD_PROVIDER_KIND_VERSION) >/dev/null

#kind-load: @ Load the local Docker image into KinD
kind-load: kind-create image-build
	@echo "Loading $(DOCKER_IMAGE):$(DOCKER_TAG) into KinD cluster '$(KIND_CLUSTER_NAME)'..."
	@kind load docker-image $(DOCKER_IMAGE):$(DOCKER_TAG) --name $(KIND_CLUSTER_NAME)

#kind-deploy: @ Apply K8s manifests to the KinD cluster
# Depends on kind-setup so the cloud-provider-kind container is running before
# the LoadBalancer service is created — otherwise the Service hangs in <pending>
# with no clear failure signal. cloud-provider-kind startup is idempotent.
kind-deploy: kind-load kind-setup
	@$(KUBECTL) apply -f k8s/namespace.yml
	@$(KUBECTL) -n spring-on-k8s apply -f k8s/cm.yml -f k8s/deployment.yml -f k8s/service.yml
	@echo "Patching deployment to use image $(DOCKER_IMAGE):$(DOCKER_TAG)..."
	@$(KUBECTL) -n spring-on-k8s set image deployment/app "app=$(DOCKER_IMAGE):$(DOCKER_TAG)"
	@$(KUBECTL) -n spring-on-k8s rollout status deployment/app --timeout=180s

#kind-undeploy: @ Remove the app from the KinD cluster (keeps cluster running)
kind-undeploy: deps
	@$(KUBECTL) -n spring-on-k8s delete -f k8s/service.yml -f k8s/deployment.yml -f k8s/cm.yml --ignore-not-found
	@$(KUBECTL) delete -f k8s/namespace.yml --ignore-not-found

#kind-destroy: @ Delete the KinD cluster, stop cloud-provider-kind, prune kindccm-* sidecars
# cloud-provider-kind spawns a per-Service Envoy sidecar container named
# kindccm-<hash> for every LoadBalancer. These survive `kind delete cluster`
# and orphan-hold IPs in the kind Docker subnet. A subsequent `kind-up`
# can land on an orphan's IP, inheriting its stale Envoy config (configured
# for a dead pod from the previous run) → "connection reset" on first curl.
# Always prune kindccm-* on teardown.
kind-destroy: deps
	@docker rm -f cloud-provider-kind >/dev/null 2>&1 || true
	@ORPHANS=$$(docker ps -aq --filter name=kindccm- 2>/dev/null); \
	if [ -n "$$ORPHANS" ]; then \
		docker rm -f $$ORPHANS >/dev/null 2>&1 || true; \
	fi
	@kind delete cluster --name $(KIND_CLUSTER_NAME) 2>/dev/null || true

#kind-up: @ Bring the full stack up (create + setup + load + deploy)
kind-up: kind-create kind-setup kind-load kind-deploy
	@echo "Stack is up. Service: $(KUBECTL) -n spring-on-k8s get svc app"

#kind-down: @ Tear the full stack down (alias for kind-destroy)
kind-down: kind-destroy

#e2e: @ End-to-end test against KinD (spins up, tests, tears down)
e2e: kind-up
	@set -e; \
	trap '$(MAKE) kind-down' EXIT; \
	KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) bash scripts/e2e-test.sh

#release: @ Create and push a release tag (usage: make release VERSION=1.2.3)
release: deps
	@if [ -z "$(VERSION)" ]; then echo "Error: VERSION is required (e.g., make release VERSION=1.2.3)"; exit 1; fi
	@if ! echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$'; then echo "Error: VERSION must be valid semver (e.g., 1.2.3)"; exit 1; fi
	@bash -c 'read -p "Create AND push release v$(VERSION) (commit + tag → origin)? [y/N] " ans && [ "$${ans:-N}" = y ] || { echo "Aborted."; exit 1; }'
	@mvn versions:set -DnewVersion=$(VERSION) -DgenerateBackupPoms=false
	@git add pom.xml
	@git commit -m "release: v$(VERSION)"
	@git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	@git push origin "v$(VERSION)"
	@git push origin HEAD
	@echo "Release v$(VERSION) created and pushed."

#renovate-bootstrap: @ Install mise + Node for Renovate
renovate-bootstrap: deps

#renovate-validate: @ Validate Renovate configuration
renovate-validate: renovate-bootstrap
	@if [ -n "$$GH_ACCESS_TOKEN" ]; then \
		GITHUB_COM_TOKEN=$$GH_ACCESS_TOKEN npx --yes renovate --platform=local; \
	else \
		echo "Warning: GH_ACCESS_TOKEN not set, some dependency lookups may fail"; \
		npx --yes renovate --platform=local; \
	fi

.PHONY: help deps deps-check deps-gjf deps-prune deps-prune-check \
	clean build test integration-test run format format-check lint cve-check vulncheck \
	secrets secrets-history trivy-fs trivy-config lint-ci mermaid-lint \
	static-check upgrade upgrade-apply image-build image-run image-stop image-push \
	docker-smoke-test dast dast-scan \
	kind-create kind-setup kind-load kind-deploy kind-undeploy kind-destroy \
	kind-up kind-down e2e ci ci-run ci-run-tag release renovate-bootstrap renovate-validate
