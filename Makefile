.DEFAULT_GOAL := help

SHELL := /bin/bash
export PATH := $(HOME)/.local/bin:$(PATH)

SDKMAN := $(HOME)/.sdkman/bin/sdkman-init.sh

# === Tool Versions (pinned, Renovate-tracked) ===
# renovate: datasource=adoptium-java depName=java
JAVA_VER    := 21-tem
# renovate: datasource=maven depName=org.apache.maven:apache-maven
MAVEN_VER   := 3.9.9
# renovate: datasource=github-releases depName=nektos/act
ACT_VERSION := 0.2.87
JDK_VERSION := 21
NODE_VERSION := 24
# renovate: datasource=github-releases depName=nvm-sh/nvm
NVM_VERSION := 0.40.4
# renovate: datasource=github-releases depName=hadolint/hadolint
HADOLINT_VERSION := 2.12.0
# renovate: datasource=maven depName=com.google.googlejavaformat:google-java-format
GJF_VERSION := 1.24.0
# renovate: datasource=github-releases depName=gitleaks/gitleaks
GITLEAKS_VERSION := 8.30.1
# renovate: datasource=github-releases depName=aquasecurity/trivy
TRIVY_VERSION := 0.69.3
# renovate: datasource=github-releases depName=rhysd/actionlint
ACTIONLINT_VERSION := 1.7.12
# renovate: datasource=github-releases depName=koalaman/shellcheck
SHELLCHECK_VERSION := 0.11.0
# renovate: datasource=maven depName=org.owasp:dependency-check-maven
DEPCHECK_VERSION := 12.1.0
# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.4.2
# renovate: datasource=github-releases depName=kubernetes-sigs/kind
KIND_VERSION := 0.32.0
# KIND_NODE_IMAGE is tied to KIND_VERSION; each KinD release ships a matching node image tag
KIND_NODE_IMAGE := kindest/node:v1.34.0
# renovate: datasource=github-releases depName=metallb/metallb
METALLB_VERSION := 0.14.8
# renovate: datasource=github-releases depName=kubernetes/kubectl extractVersion=^kubernetes-(?<version>.+)$$
KUBECTL_VERSION := 1.34.4

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

IS_DARWIN := 0
IS_LINUX := 0
IS_FREEBSD := 0
IS_WINDOWS := 0
IS_AMD64 := 0
IS_AARCH64 := 0
IS_RISCV64 := 0

# Platform and architecture detection
ifeq ($(OS), Windows_NT)
	IS_WINDOWS := 1
	ifeq ($(PROCESSOR_ARCHITECTURE), AMD64)
		IS_AMD64 := 1
	else ifeq ($(PROCESSOR_ARCHITECTURE), x86)
		IS_AMD64 := 0
	else ifeq ($(PROCESSOR_ARCHITECTURE), ARM64)
		IS_AARCH64 := 1
	else
		ifeq ($(PROCESSOR_ARCHITEW6432), AMD64)
			IS_AMD64 := 1
		else ifeq ($(PROCESSOR_ARCHITEW6432), ARM64)
			IS_AARCH64 := 1
		else
			IS_AMD64 := 1
		endif
	endif
else
	UNAME_S := $(shell uname -s)
	UNAME_M := $(shell uname -m)

	ifeq ($(UNAME_S), Darwin)
		IS_DARWIN := 1
	else ifeq ($(UNAME_S), Linux)
		IS_LINUX := 1
	else ifeq ($(UNAME_S), FreeBSD)
		IS_FREEBSD := 1
	else
		$(error Unsupported platform: $(UNAME_S). Supported platforms: Darwin, Linux, FreeBSD, Windows_NT)
	endif

	ifneq (, $(filter $(UNAME_M), x86_64 amd64))
		IS_AMD64 := 1
	else ifneq (, $(filter $(UNAME_M), aarch64 arm64))
		IS_AARCH64 := 1
	else ifneq (, $(filter $(UNAME_M), riscv64))
		IS_RISCV64 := 1
	else
		$(error Unsupported architecture: $(UNAME_M). Supported architectures: x86_64/amd64, aarch64/arm64, riscv64)
	endif
endif

# === OS / Arch name translations for tool download URLs ===
# hadolint uses Darwin/Linux + x86_64/arm64
ifeq ($(IS_DARWIN),1)
  HADOLINT_OS := Darwin
else
  HADOLINT_OS := Linux
endif
ifeq ($(IS_AARCH64),1)
  HADOLINT_ARCH := arm64
else
  HADOLINT_ARCH := x86_64
endif

# gitleaks uses lowercase linux/darwin + x64/arm64
ifeq ($(IS_DARWIN),1)
  GITLEAKS_OS := darwin
else
  GITLEAKS_OS := linux
endif
ifeq ($(IS_AARCH64),1)
  GITLEAKS_ARCH := arm64
else
  GITLEAKS_ARCH := x64
endif

# trivy uses macOS/Linux + 64bit/ARM64
ifeq ($(IS_DARWIN),1)
  TRIVY_OS := macOS
else
  TRIVY_OS := Linux
endif
ifeq ($(IS_AARCH64),1)
  TRIVY_ARCH := ARM64
else
  TRIVY_ARCH := 64bit
endif

# actionlint uses lowercase linux/darwin + amd64/arm64
ifeq ($(IS_DARWIN),1)
  ACTIONLINT_OS := darwin
else
  ACTIONLINT_OS := linux
endif
ifeq ($(IS_AARCH64),1)
  ACTIONLINT_ARCH := arm64
else
  ACTIONLINT_ARCH := amd64
endif

# shellcheck uses linux/darwin + x86_64/aarch64
ifeq ($(IS_DARWIN),1)
  SHELLCHECK_OS := darwin
else
  SHELLCHECK_OS := linux
endif
ifeq ($(IS_AARCH64),1)
  SHELLCHECK_ARCH := aarch64
else
  SHELLCHECK_ARCH := x86_64
endif

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo
	@echo "Commands :"
	@echo
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-22s\033[0m - %s\n", $$1, $$2}'

#deps: @ Check required tools (java, mvn, docker, git) — auto-installs mvn if missing
deps: deps-maven
	@command -v java >/dev/null 2>&1 || { echo "Error: java is not installed. Run: make deps-install"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "Error: docker is not installed or not in PATH"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo "Error: git is not installed or not in PATH"; exit 1; }
	@echo "All required tools are installed."

#deps-maven: @ Install Apache Maven to ~/.local if missing
deps-maven:
	@mkdir -p $(HOME)/.local/bin
	@command -v mvn >/dev/null 2>&1 || { \
		echo "Installing Apache Maven $(MAVEN_VER) to $(HOME)/.local/apache-maven-$(MAVEN_VER)..."; \
		set -e; \
		TMP=$$(mktemp -d); \
		curl -sSfL -o $$TMP/maven.tar.gz "https://archive.apache.org/dist/maven/maven-3/$(MAVEN_VER)/binaries/apache-maven-$(MAVEN_VER)-bin.tar.gz"; \
		tar -xzf $$TMP/maven.tar.gz -C $(HOME)/.local/; \
		ln -sf $(HOME)/.local/apache-maven-$(MAVEN_VER)/bin/mvn $(HOME)/.local/bin/mvn; \
		rm -rf $$TMP; \
	}

#deps-install: @ Install Java/Maven via SDKMAN (one-time bootstrap)
deps-install:
	@bash -c 'set -e; \
		if [ ! -s "$(SDKMAN)" ]; then \
			echo "Installing SDKMAN..."; \
			curl -s "https://get.sdkman.io?rcupdate=false" | bash; \
		fi; \
		source "$(SDKMAN)"; \
		echo N | sdk install java $(JAVA_VER) || true; \
		sdk default java $(JAVA_VER); \
		echo N | sdk install maven $(MAVEN_VER) || true; \
		sdk default maven $(MAVEN_VER); \
		echo "Installed: java=$(JAVA_VER), maven=$(MAVEN_VER)"'

#deps-check: @ Show installed tool versions
deps-check:
	@echo "Installed tools:"
	@command -v java >/dev/null 2>&1 && java -version 2>&1 | head -1 | sed 's/^/  /' || echo "  java: NOT INSTALLED (run make deps-install)"
	@command -v mvn >/dev/null 2>&1 && echo "  $$(mvn -v 2>&1 | head -1)" || echo "  mvn: NOT INSTALLED"
	@command -v docker >/dev/null 2>&1 && echo "  $$(docker --version)" || echo "  docker: NOT INSTALLED"
	@command -v git >/dev/null 2>&1 && echo "  $$(git --version)" || echo "  git: NOT INSTALLED"

#deps-act: @ Install act for local CI (GitHub Actions)
deps-act:
	@mkdir -p $(HOME)/.local/bin
	@command -v act >/dev/null 2>&1 || { \
		echo "Installing act $(ACT_VERSION) to $(HOME)/.local/bin..."; \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/master/install.sh | bash -s -- -b $(HOME)/.local/bin v$(ACT_VERSION); \
	}

#deps-hadolint: @ Install hadolint for Dockerfile linting
deps-hadolint:
	@mkdir -p $(HOME)/.local/bin
	@command -v hadolint >/dev/null 2>&1 || { \
		echo "Installing hadolint $(HADOLINT_VERSION) to $(HOME)/.local/bin..."; \
		curl -sSfL -o $(HOME)/.local/bin/hadolint "https://github.com/hadolint/hadolint/releases/download/v$(HADOLINT_VERSION)/hadolint-$(HADOLINT_OS)-$(HADOLINT_ARCH)" && \
		chmod +x $(HOME)/.local/bin/hadolint; \
	}

#deps-gitleaks: @ Install gitleaks for secret scanning
deps-gitleaks:
	@mkdir -p $(HOME)/.local/bin
	@command -v gitleaks >/dev/null 2>&1 || { \
		echo "Installing gitleaks $(GITLEAKS_VERSION) to $(HOME)/.local/bin..."; \
		set -e; \
		TMP=$$(mktemp -d); \
		curl -sSfL -o $$TMP/gitleaks.tar.gz "https://github.com/gitleaks/gitleaks/releases/download/v$(GITLEAKS_VERSION)/gitleaks_$(GITLEAKS_VERSION)_$(GITLEAKS_OS)_$(GITLEAKS_ARCH).tar.gz"; \
		tar -xzf $$TMP/gitleaks.tar.gz -C $$TMP gitleaks; \
		install -m 755 $$TMP/gitleaks $(HOME)/.local/bin/gitleaks; \
		rm -rf $$TMP; \
	}

#deps-trivy: @ Install Trivy for filesystem and config scanning
deps-trivy:
	@mkdir -p $(HOME)/.local/bin
	@command -v trivy >/dev/null 2>&1 || { \
		echo "Installing trivy $(TRIVY_VERSION) to $(HOME)/.local/bin..."; \
		set -e; \
		TMP=$$(mktemp -d); \
		curl -sSfL -o $$TMP/trivy.tar.gz "https://github.com/aquasecurity/trivy/releases/download/v$(TRIVY_VERSION)/trivy_$(TRIVY_VERSION)_$(TRIVY_OS)-$(TRIVY_ARCH).tar.gz"; \
		tar -xzf $$TMP/trivy.tar.gz -C $$TMP trivy; \
		install -m 755 $$TMP/trivy $(HOME)/.local/bin/trivy; \
		rm -rf $$TMP; \
	}

#deps-actionlint: @ Install actionlint for GitHub Actions workflow linting
deps-actionlint:
	@mkdir -p $(HOME)/.local/bin
	@command -v actionlint >/dev/null 2>&1 || { \
		echo "Installing actionlint $(ACTIONLINT_VERSION) to $(HOME)/.local/bin..."; \
		set -e; \
		TMP=$$(mktemp -d); \
		curl -sSfL -o $$TMP/actionlint.tar.gz "https://github.com/rhysd/actionlint/releases/download/v$(ACTIONLINT_VERSION)/actionlint_$(ACTIONLINT_VERSION)_$(ACTIONLINT_OS)_$(ACTIONLINT_ARCH).tar.gz"; \
		tar -xzf $$TMP/actionlint.tar.gz -C $$TMP actionlint; \
		install -m 755 $$TMP/actionlint $(HOME)/.local/bin/actionlint; \
		rm -rf $$TMP; \
	}

#deps-shellcheck: @ Install shellcheck for shell script linting
deps-shellcheck:
	@mkdir -p $(HOME)/.local/bin
	@command -v shellcheck >/dev/null 2>&1 || { \
		echo "Installing shellcheck $(SHELLCHECK_VERSION) to $(HOME)/.local/bin..."; \
		set -e; \
		TMP=$$(mktemp -d); \
		curl -sSfL -o $$TMP/shellcheck.tar.xz "https://github.com/koalaman/shellcheck/releases/download/v$(SHELLCHECK_VERSION)/shellcheck-v$(SHELLCHECK_VERSION).$(SHELLCHECK_OS).$(SHELLCHECK_ARCH).tar.xz"; \
		tar -xJf $$TMP/shellcheck.tar.xz -C $$TMP; \
		install -m 755 $$TMP/shellcheck-v$(SHELLCHECK_VERSION)/shellcheck $(HOME)/.local/bin/shellcheck; \
		rm -rf $$TMP; \
	}

#deps-gjf: @ Download google-java-format JAR
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
	@set -e; \
	if [ -s "$(SDKMAN)" ]; then source "$(SDKMAN)"; sdk use java $(JAVA_VER) >/dev/null; fi; \
	find src/main/java src/test/java -name "*.java" -print0 | xargs -0 java $(GJF_JAVA_OPTS) -jar $(GJF_JAR) --replace; \
	echo "Formatting complete."

#format-check: @ Verify Java sources are google-java-format compliant (no changes)
format-check: deps-gjf
	@set -e; \
	if [ -s "$(SDKMAN)" ]; then source "$(SDKMAN)"; sdk use java $(JAVA_VER) >/dev/null; fi; \
	CHANGED=$$(find src/main/java src/test/java -name "*.java" -print0 | xargs -0 java $(GJF_JAVA_OPTS) -jar $(GJF_JAR) --dry-run); \
	if [ -n "$$CHANGED" ]; then \
		echo "ERROR: The following files are not formatted. Run 'make format' to fix:"; \
		echo "$$CHANGED" | sed 's/^/  /'; \
		exit 1; \
	fi; \
	echo "All Java sources are correctly formatted."

#lint: @ Run Checkstyle + Dockerfile + compiler warning checks
lint: deps deps-hadolint
	@mvn -B compile
	@mvn -B checkstyle:check
	@hadolint Dockerfile

#cve-check: @ OWASP dependency-check vulnerability scan
# Primary data source: NVD (requires NVD_API_KEY for fast path — free key
# from https://nvd.nist.gov/developers/request-an-api-key).
# Secondary data source: Sonatype OSS Index (requires OSS_INDEX_USER +
# OSS_INDEX_TOKEN for authenticated access — anonymous hits HTTP 429; free
# account at https://ossindex.sonatype.org/). If OSS Index creds are absent
# the analyzer is disabled so the build still succeeds on NVD alone.
cve-check: deps
	@set -e; \
	MVN_ARGS="-B org.owasp:dependency-check-maven:$(DEPCHECK_VERSION):check -DsuppressionFiles=dependency-check-suppressions.xml"; \
	if [ -n "$$NVD_API_KEY" ]; then \
		echo "NVD: authenticated (fast path)"; \
		MVN_ARGS="$$MVN_ARGS -DnvdApiKey=$$NVD_API_KEY"; \
	else \
		echo "WARN: NVD_API_KEY not set — NVD slow path may take 10+ min."; \
	fi; \
	if [ -n "$$OSS_INDEX_USER" ] && [ -n "$$OSS_INDEX_TOKEN" ]; then \
		echo "OSS Index: authenticated (remote errors downgraded to warnings)"; \
		MVN_ARGS="$$MVN_ARGS -DossIndexAnalyzerUsername=$$OSS_INDEX_USER -DossIndexAnalyzerPassword=$$OSS_INDEX_TOKEN -DossIndexAnalyzerWarnOnlyOnRemoteErrors=true"; \
	else \
		echo "WARN: OSS_INDEX_USER / OSS_INDEX_TOKEN not set — disabling OSS Index analyzer (anonymous is rate-limited)."; \
		MVN_ARGS="$$MVN_ARGS -DossIndexAnalyzerEnabled=false"; \
	fi; \
	mvn $$MVN_ARGS

#secrets: @ Scan working tree for secrets via gitleaks (CI-oriented; use secrets-history for full git audit)
secrets: deps-gitleaks
	@gitleaks detect --source . --no-git --verbose --redact --no-banner

#secrets-history: @ Full git history secret audit (slow, for one-time auditing)
secrets-history: deps-gitleaks
	@gitleaks detect --source . --verbose --redact --no-banner

#trivy-fs: @ Trivy filesystem scan (vulnerabilities, secrets, misconfigs)
trivy-fs: deps-trivy
	@trivy fs --scanners vuln,secret,misconfig --exit-code 0 .

#trivy-config: @ Trivy IaC/K8s manifest scan
trivy-config: deps-trivy
	@trivy config --exit-code 0 k8s/

#lint-ci: @ Lint GitHub Actions workflows (actionlint invokes shellcheck on run: scripts internally)
lint-ci: deps-actionlint deps-shellcheck
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

#ci-run: @ Run GitHub Actions workflow locally using act
ci-run: deps-act
	@docker container prune -f 2>/dev/null || true
	@act push --container-architecture linux/amd64 \
		--artifact-server-path /tmp/act-artifacts

#deps-kind: @ Install KinD (Kubernetes in Docker)
deps-kind:
	@mkdir -p $(HOME)/.local/bin
	@command -v kind >/dev/null 2>&1 || { \
		echo "Installing kind $(KIND_VERSION) to $(HOME)/.local/bin..."; \
		curl -sSfL -o $(HOME)/.local/bin/kind "https://kind.sigs.k8s.io/dl/v$(KIND_VERSION)/kind-$$(uname | tr '[:upper:]' '[:lower:]')-$$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"; \
		chmod +x $(HOME)/.local/bin/kind; \
	}

#deps-kubectl: @ Install kubectl
deps-kubectl:
	@mkdir -p $(HOME)/.local/bin
	@command -v kubectl >/dev/null 2>&1 || { \
		echo "Installing kubectl $(KUBECTL_VERSION) to $(HOME)/.local/bin..."; \
		curl -sSfL -o $(HOME)/.local/bin/kubectl "https://dl.k8s.io/release/v$(KUBECTL_VERSION)/bin/$$(uname | tr '[:upper:]' '[:lower:]')/$$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')/kubectl"; \
		chmod +x $(HOME)/.local/bin/kubectl; \
	}

#kind-create: @ Create KinD cluster
kind-create: deps-kind deps-kubectl
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

#renovate-bootstrap: @ Install nvm and pinned Node for Renovate
renovate-bootstrap:
	@command -v node >/dev/null 2>&1 || { \
		echo "Installing nvm $(NVM_VERSION)..."; \
		curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$(NVM_VERSION)/install.sh | bash; \
		export NVM_DIR="$$HOME/.nvm"; \
		[ -s "$$NVM_DIR/nvm.sh" ] && . "$$NVM_DIR/nvm.sh"; \
		nvm install $(NODE_VERSION); \
	}

#renovate-validate: @ Validate Renovate configuration
renovate-validate: renovate-bootstrap
	@if [ -n "$$GH_ACCESS_TOKEN" ]; then \
		GITHUB_COM_TOKEN=$$GH_ACCESS_TOKEN npx --yes renovate --platform=local; \
	else \
		echo "Warning: GH_ACCESS_TOKEN not set, some dependency lookups may fail"; \
		npx --yes renovate --platform=local; \
	fi

.PHONY: help deps deps-install deps-check deps-maven deps-act deps-hadolint deps-gitleaks \
	deps-trivy deps-actionlint deps-shellcheck deps-gjf deps-kind deps-kubectl clean build \
	test integration-test run format format-check lint cve-check secrets secrets-history \
	trivy-fs trivy-config lint-ci mermaid-lint deps-prune deps-prune-check static-check upgrade \
	upgrade-apply image-build image-run image-stop image-push kind-create kind-setup kind-load \
	kind-deploy kind-undeploy kind-destroy kind-up kind-down e2e ci ci-run release \
	renovate-bootstrap renovate-validate
