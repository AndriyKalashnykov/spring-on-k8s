.DEFAULT_GOAL := help

SHELL := /bin/bash
SDKMAN := $(HOME)/.sdkman/bin/sdkman-init.sh
CURRENT_USER_NAME := $(shell whoami)

JAVA_VER  := 21-tem
MAVEN_VER := 25.0.2+10.0.LTS

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
	@clear
	@echo "Usage: make COMMAND"
	@echo
	@echo "Commands :"
	@echo
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-9s\033[0m - %s\n", $$1, $$2}'

build-deps-check:
	@. $(SDKMAN)
ifndef SDKMAN_DIR
	@curl -s "https://get.sdkman.io?rcupdate=false" | bash
	@source $(SDKMAN)
	ifndef SDKMAN_DIR
		SDKMAN_EXISTS := @echo "SDKMAN_VERSION is undefined" && exit 1
	endif
endif

	@. $(SDKMAN) && echo N | sdk install java $(JAVA_VER) && sdk use java $(JAVA_VER)
	@. $(SDKMAN) && echo N | sdk install gradle $(MAVEN_VER) && sdk use gradle $(MAVEN_VER)

#check-env: @ Check installed tools
check-env: build-deps-check

	@printf "\xE2\x9C\x94 "
	$(SDKMAN_EXISTS)
	@printf "\n"

#clean: @ Cleanup
clean:
	@ mvn clean

#test: @ Run project tests
test: build
	@ mvn test

#build: @ Build project
build: clean
	@ mvn package

#run: @ Run project
run: test
	@ mvn clean spring-boot:run -Djava.version=21

#upgrade: @ Upgrade Maven dependencies
upgrade:
	@ mvn versions:display-dependency-updates
	@ mvn versions:use-latest-releases
	@ mvn versions:commit

#image: @ Build and run Docker image for testing
image:
	docker build --load -t andriykalashnykov/spring-on-k8s:latest --build-arg JDK_VENDOR=eclipse-temurin --build-arg JDK_VERSION=21 .

