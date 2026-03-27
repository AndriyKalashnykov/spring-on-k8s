.DEFAULT_GOAL := help

SHELL := /bin/bash
SDKMAN := $(HOME)/.sdkman/bin/sdkman-init.sh

# === Tool Versions (pinned) ===
JAVA_VER    := 21-tem
MAVEN_VER   := 3.9.9
ACT_VERSION := 0.2.86
JDK_VERSION := 21
NVM_VERSION := 0.40.4

SDKMAN_EXISTS := @printf "sdkman"

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
	# Windows architecture detection using PROCESSOR_ARCHITECTURE
	ifeq ($(PROCESSOR_ARCHITECTURE), AMD64)
		IS_AMD64 := 1
	else ifeq ($(PROCESSOR_ARCHITECTURE), x86)
		# 32-bit x86 - you might want to add IS_X86 := 1 if needed
		IS_AMD64 := 0
	else ifeq ($(PROCESSOR_ARCHITECTURE), ARM64)
		IS_AARCH64 := 1
	else
		# Fallback: check PROCESSOR_ARCHITEW6432 for 32-bit processes on 64-bit systems
		ifeq ($(PROCESSOR_ARCHITEW6432), AMD64)
			IS_AMD64 := 1
		else ifeq ($(PROCESSOR_ARCHITEW6432), ARM64)
			IS_AARCH64 := 1
		else
			# Default to AMD64 if unable to determine
			IS_AMD64 := 1
		endif
	endif
else
	# Unix-like systems - detect platform and architecture
	UNAME_S := $(shell uname -s)
	UNAME_M := $(shell uname -m)

	# Platform detection
	ifeq ($(UNAME_S), Darwin)
		IS_DARWIN := 1
	else ifeq ($(UNAME_S), Linux)
		IS_LINUX := 1
	else ifeq ($(UNAME_S), FreeBSD)
		IS_FREEBSD := 1
	else
		$(error Unsupported platform: $(UNAME_S). Supported platforms: Darwin, Linux, FreeBSD, Windows_NT)
	endif

	# Architecture detection
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

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo
	@echo "Commands :"
	@echo
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-20s\033[0m - %s\n", $$1, $$2}'

#deps: @ Check required tools (java, mvn, docker, git)
deps:
	@command -v java >/dev/null 2>&1 || { echo "Error: java is not installed. Run: make deps-check"; exit 1; }
	@command -v mvn >/dev/null 2>&1 || { echo "Error: mvn is not installed. Run: make deps-check"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "Error: docker is not installed or not in PATH"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo "Error: git is not installed or not in PATH"; exit 1; }
	@echo "All required tools are installed."

#deps-check: @ Check SDKMAN and install Java/Maven
deps-check:
	@. $(SDKMAN)
ifndef SDKMAN_DIR
	@curl -s "https://get.sdkman.io?rcupdate=false" | bash
	@source $(SDKMAN)
	ifndef SDKMAN_DIR
		SDKMAN_EXISTS := @echo "SDKMAN_VERSION is undefined" && exit 1
	endif
endif

	@. $(SDKMAN) && echo N | sdk install java $(JAVA_VER) && sdk use java $(JAVA_VER)
	@. $(SDKMAN) && echo N | sdk install maven $(MAVEN_VER) && sdk use maven $(MAVEN_VER)

#deps-act: @ Install act for local CI (GitHub Actions)
deps-act: deps
	@command -v act >/dev/null 2>&1 || { echo "Installing act $(ACT_VERSION)..."; \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash -s -- -b /usr/local/bin v$(ACT_VERSION); \
	}

#env-check: @ Check installed tools
env-check: deps-check
	@printf "\xE2\x9C\x94 "
	@$(SDKMAN_EXISTS)
	@printf "\n"

#clean: @ Cleanup
clean: deps
	@mvn clean

#build: @ Build project
build: deps
	@mvn clean package -DskipTests

#test: @ Run project tests
test: deps
	@mvn test

#run: @ Run project
run: deps
	@mvn clean spring-boot:run -Djava.version=$(JDK_VERSION)

#upgrade: @ Upgrade Maven dependencies
upgrade: deps
	@mvn versions:display-dependency-updates
	@mvn versions:use-latest-releases
	@mvn versions:commit

#image-build: @ Build Docker image
image-build: deps
	@docker build --load -t andriykalashnykov/spring-on-k8s:latest --build-arg JDK_VENDOR=eclipse-temurin --build-arg JDK_VERSION=$(JDK_VERSION) .

#image-run: @ Run Docker container
image-run: image-stop
	@docker run --rm -p 8080:8080 --name spring-on-k8s andriykalashnykov/spring-on-k8s:latest

#image-stop: @ Stop Docker container
image-stop:
	@docker stop spring-on-k8s 2>/dev/null || true

#lint: @ Run code style checks
lint: deps
	@mvn checkstyle:check

#ci: @ Run full CI pipeline (deps, build, test, lint)
ci: deps
	@echo "=== Step 1/3: Build ===" && mvn clean package -DskipTests
	@echo "=== Step 2/3: Test ===" && mvn test
	@echo "=== Step 3/3: Lint ===" && mvn checkstyle:check
	@echo "CI pipeline completed successfully."

#ci-run: @ Run GitHub Actions workflow locally using act
ci-run: deps-act
	@act push --container-architecture linux/amd64 \
		--artifact-server-path /tmp/act-artifacts

#release: @ Create a release (usage: make release VERSION=1.2.3)
release: deps
	@if [ -z "$(VERSION)" ]; then echo "Error: VERSION is required (e.g., make release VERSION=1.2.3)"; exit 1; fi
	@if ! echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$'; then echo "Error: VERSION must be valid semver (e.g., 1.2.3)"; exit 1; fi
	@echo -n "Create release v$(VERSION)? [y/N] " && read ans && [ "$${ans:-N}" = y ] || { echo "Aborted."; exit 1; }
	@mvn versions:set -DnewVersion=$(VERSION) -DgenerateBackupPoms=false
	@git add pom.xml
	@git commit -m "release: v$(VERSION)"
	@git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	@echo "Release v$(VERSION) created. Push with: git push origin main --tags"

#renovate-bootstrap: @ Install nvm and npm for Renovate
renovate-bootstrap:
	@command -v node >/dev/null 2>&1 || { \
		echo "Installing nvm $(NVM_VERSION)..."; \
		curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$(NVM_VERSION)/install.sh | bash; \
		export NVM_DIR="$$HOME/.nvm"; \
		[ -s "$$NVM_DIR/nvm.sh" ] && . "$$NVM_DIR/nvm.sh"; \
		nvm install --lts; \
	}

#renovate-validate: @ Validate Renovate configuration
renovate-validate: renovate-bootstrap
	@npx --yes renovate --platform=local

.PHONY: help deps deps-check deps-act env-check clean build test run upgrade \
	image-build image-run image-stop lint ci ci-run release \
	renovate-bootstrap renovate-validate
