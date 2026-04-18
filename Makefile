.DEFAULT_GOAL := help

SHELL := /bin/bash
# mise shims come first, then ~/.local/bin tool installs, then system PATH.
export PATH := $(HOME)/.local/share/mise/shims:$(HOME)/.local/bin:$(PATH)

# === Tool Versions (pinned, Renovate-tracked) ===
# Single source of truth for every mise-managed tool is .mise.toml. The
# constants below are the exceptions — values that are not mise-managed
# (Maven plugins, JAR downloads, Docker image pins, literals consumed by
# Docker build args).
JDK_VERSION := 21
NODE_VERSION := $(shell cat .nvmrc 2>/dev/null || echo 24)
# renovate: datasource=maven depName=com.google.googlejavaformat:google-java-format
GJF_VERSION := 1.35.0
# renovate: datasource=maven depName=org.owasp:dependency-check-maven
DEPCHECK_VERSION := 12.2.1
# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.12.0
# KIND_NODE_IMAGE is tied to the kind release in .mise.toml; each kind
# release ships a matching node image tag (digest from kind release notes).
# renovate: datasource=docker depName=kindest/node
KIND_NODE_IMAGE := kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f
# renovate: datasource=github-releases depName=metallb/metallb
METALLB_VERSION := 0.15.3

# === Docker image coordinates ===
APP_NAME        := spring-on-k8s
DOCKER_REGISTRY := andriykalashnykov
DOCKER_IMAGE    := $(DOCKER_REGISTRY)/$(APP_NAME)
CURRENTTAG      := $(shell git describe --tags --abbrev=0 2>/dev/null || echo dev)
DOCKER_TAG      := $(CURRENTTAG)

KIND_CLUSTER := spring-on-k8s

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

#deps-install: @ Alias for deps (kept for backwards compatibility)
deps-install: deps

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

#clean: @ Cleanup
clean: deps
	@mvn clean

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

#lint: @ Run Checkstyle + Dockerfile + compiler warning checks
lint: deps
	@mvn -B compile
	@mvn -B checkstyle:check
	@hadolint Dockerfile

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
	@set -e; \
	MVN_ARGS="-B org.owasp:dependency-check-maven:$(DEPCHECK_VERSION):check -DsuppressionFiles=dependency-check-suppressions.xml -DossindexAnalyzerEnabled=false"; \
	if [ -n "$$NVD_API_KEY" ]; then \
		echo "NVD: authenticated (fast path)"; \
		MVN_ARGS="$$MVN_ARGS -DnvdApiKey=$$NVD_API_KEY"; \
	else \
		echo "WARN: NVD_API_KEY not set — NVD slow path may take 10+ min."; \
	fi; \
	mvn $$MVN_ARGS

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

#lint-ci: @ Lint GitHub Actions workflows (actionlint invokes shellcheck on run: scripts internally)
lint-ci: deps
	@actionlint
	@echo "Workflow lint complete."

#mermaid-lint: @ Validate Mermaid diagrams in markdown files
mermaid-lint:
	@command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is required for mermaid-lint"; exit 1; }
	@set -euo pipefail; \
	MD_FILES=$$(grep -lF '```mermaid' README.md CLAUDE.md 2>/dev/null || true); \
	if [ -z "$$MD_FILES" ]; then \
		echo "No Mermaid blocks found — skipping."; \
		exit 0; \
	fi; \
	FAILED=0; \
	for md in $$MD_FILES; do \
		echo "Validating Mermaid blocks in $$md..."; \
		LOG=$$(mktemp); \
		if docker run --rm -v "$$PWD:/data" \
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
static-check: format-check lint secrets trivy-fs trivy-config lint-ci mermaid-lint deps-prune-check
	@echo "All static checks passed. Run 'make cve-check' separately for vulnerability scan (slow)."

#upgrade: @ Show available Maven dependency updates (dry-run)
upgrade: deps
	@mvn versions:display-dependency-updates

#upgrade-apply: @ Apply latest Maven releases (mutates pom.xml — prompts for confirmation)
upgrade-apply: deps
	@bash -c 'read -p "Apply latest releases to pom.xml? [y/N] " ans && [ "$${ans:-N}" = y ] || { echo "Aborted."; exit 1; }'
	@mvn versions:use-latest-releases
	@mvn versions:commit

#image-build: @ Build Docker image (see DOCKER_IMAGE / DOCKER_TAG)
image-build: build
	@docker buildx build --load -t $(DOCKER_IMAGE):$(DOCKER_TAG) --build-arg JDK_VENDOR=eclipse-temurin --build-arg JDK_VERSION=$(JDK_VERSION) .

#image-run: @ Run Docker container
image-run: image-stop
	@docker run --rm -p 8080:8080 --name $(APP_NAME) $(DOCKER_IMAGE):$(DOCKER_TAG)

#image-stop: @ Stop Docker container
image-stop:
	@docker stop $(APP_NAME) 2>/dev/null || true

#image-push: @ Push Docker image to registry
image-push: image-build
	@if [ -n "$$GH_ACCESS_TOKEN" ] && [ "$(DOCKER_REGISTRY)" = "ghcr.io" ]; then \
		echo "$$GH_ACCESS_TOKEN" | docker login ghcr.io -u $$GITHUB_ACTOR --password-stdin; \
	fi
	@docker push $(DOCKER_IMAGE):$(DOCKER_TAG)

#ci: @ Run full CI pipeline (deps, format-check, static-check, test, integration-test, build)
ci: deps format-check static-check test integration-test build
	@echo "CI pipeline completed successfully."

#ci-run: @ Run GitHub Actions workflow locally using act (serialized per-job, random artifact port)
ci-run: deps
	@docker container prune -f 2>/dev/null || true
	@ACT_PORT=$$(shuf -i 40000-59999 -n 1); \
	ARTIFACT_PATH=$$(mktemp -d -t act-artifacts.XXXXXX); \
	for j in static-check build test integration-test docker; do \
		echo "==== act push --job $$j ===="; \
		act push --job $$j --container-architecture linux/amd64 \
			--artifact-server-port "$$ACT_PORT" \
			--artifact-server-path "$$ARTIFACT_PATH" || exit 1; \
	done

#kind-create: @ Create KinD cluster
kind-create: deps
	@kind get clusters 2>/dev/null | grep -q "^$(KIND_CLUSTER)$$" || { \
		echo "Creating KinD cluster '$(KIND_CLUSTER)' with node image $(KIND_NODE_IMAGE)..."; \
		kind create cluster --name $(KIND_CLUSTER) --image $(KIND_NODE_IMAGE); \
	}
	@kubectl cluster-info --context kind-$(KIND_CLUSTER)

#kind-setup: @ Install MetalLB in KinD for LoadBalancer services
kind-setup: kind-create
	@METALLB_VERSION=$(METALLB_VERSION) bash scripts/kind-metallb-setup.sh

#kind-load: @ Load the local Docker image into KinD
kind-load: kind-create image-build
	@echo "Loading $(DOCKER_IMAGE):$(DOCKER_TAG) into KinD cluster '$(KIND_CLUSTER)'..."
	@kind load docker-image $(DOCKER_IMAGE):$(DOCKER_TAG) --name $(KIND_CLUSTER)

#kind-deploy: @ Apply K8s manifests to the KinD cluster
kind-deploy: kind-load
	@kubectl apply -f k8s/namespace.yml
	@kubectl -n spring-on-k8s apply -f k8s/cm.yml -f k8s/deployment.yml -f k8s/service.yml
	@echo "Patching deployment to use image $(DOCKER_IMAGE):$(DOCKER_TAG)..."
	@kubectl -n spring-on-k8s set image deployment/app "app=$(DOCKER_IMAGE):$(DOCKER_TAG)"
	@kubectl -n spring-on-k8s rollout status deployment/app --timeout=180s

#kind-undeploy: @ Remove the app from the KinD cluster (keeps cluster running)
kind-undeploy:
	@kubectl -n spring-on-k8s delete -f k8s/service.yml -f k8s/deployment.yml -f k8s/cm.yml --ignore-not-found
	@kubectl delete -f k8s/namespace.yml --ignore-not-found

#kind-destroy: @ Delete the KinD cluster
kind-destroy:
	@kind delete cluster --name $(KIND_CLUSTER) 2>/dev/null || true

#kind-up: @ Bring the full stack up (create + setup + load + deploy)
kind-up: kind-create kind-setup kind-load kind-deploy
	@echo "Stack is up. Service: kubectl -n spring-on-k8s get svc app"

#kind-down: @ Tear the full stack down (alias for kind-destroy)
kind-down: kind-destroy

#e2e: @ End-to-end test against KinD (spins up, tests, tears down)
e2e: kind-up
	@set -e; \
	trap '$(MAKE) kind-down' EXIT; \
	bash scripts/e2e-test.sh

#release: @ Create a release (usage: make release VERSION=1.2.3)
release: deps
	@if [ -z "$(VERSION)" ]; then echo "Error: VERSION is required (e.g., make release VERSION=1.2.3)"; exit 1; fi
	@if ! echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$'; then echo "Error: VERSION must be valid semver (e.g., 1.2.3)"; exit 1; fi
	@bash -c 'read -p "Create release v$(VERSION)? [y/N] " ans && [ "$${ans:-N}" = y ] || { echo "Aborted."; exit 1; }'
	@mvn versions:set -DnewVersion=$(VERSION) -DgenerateBackupPoms=false
	@git add pom.xml
	@git commit -m "release: v$(VERSION)"
	@git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	@echo "Release v$(VERSION) created. Push with: git push origin main --tags"

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

.PHONY: help deps deps-install deps-check deps-gjf deps-prune deps-prune-check \
	clean build test integration-test run format format-check lint cve-check \
	secrets secrets-history trivy-fs trivy-config lint-ci mermaid-lint \
	static-check upgrade upgrade-apply image-build image-run image-stop image-push \
	kind-create kind-setup kind-load kind-deploy kind-undeploy kind-destroy \
	kind-up kind-down e2e ci ci-run release renovate-bootstrap renovate-validate
