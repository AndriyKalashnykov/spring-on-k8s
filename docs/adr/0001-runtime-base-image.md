# ADR-0001: Runtime base image — Eclipse Temurin 21 JRE on Alpine

- **Status:** Accepted — landed 2026-05-11 (pilot branch `chore/pilot-temurin-jre-alpine` merged); runtime subsequently bumped to Java 25 LTS — see Addendum
- **Date:** 2026-05-11
- **Deciders:** Andriy Kalashnykov
- **Supersedes:** prior implicit choice of `gcr.io/distroless/java21-debian13:nonroot`

## Context

The runtime image was `gcr.io/distroless/java21-debian13:nonroot`, digest-pinned in
`Dockerfile`. The image is minimal (no shell, no package manager) and runs as a
non-root user — strong baseline posture for a Kubernetes workload.

The trigger for revisiting this choice was the 2026-05-11 scheduled CI failure
(run [25651901458](https://github.com/AndriyKalashnykov/spring-on-k8s/actions/runs/25651901458),
issue #223): a HIGH-severity CVE in `liblcms2-2` (CVE-2026-41254) blocked the
`docker` job's Trivy gate. The fix has been available upstream in Debian 13
(`2.16-2+deb13u2`) for days, but Google's distroless rebuild had not yet
picked it up. The `.trivyignore` already carried five distroless-base
suppressions for similar upstream-rebuild lag (`CVE-2026-0861`,
`CVE-2026-25210`, `CVE-2026-33416`, `CVE-2026-33636`, `CVE-2023-45853`).
The pattern was repeating: real upstream fixes available, gated on Google's
distroless rebuild cadence, requiring time-boxed suppressions to keep the
release pipeline green.

The question became: is there a base image that combines (a) faster CVE
turnaround, (b) Java 21 LTS, (c) no commercial-tier requirement, (d) compatible
with the existing nonroot K8s posture and cosign signing flow?

## Decision

Switch the runtime stage to **`eclipse-temurin:21-jre-alpine`**, digest-pinned
to a Renovate-tracked index digest. Create an unprivileged user at UID/GID
65532 (matching the distroless convention) so K8s `securityContext` and any
future PodSecurity / OPA-Gatekeeper rule keep working unchanged.

```dockerfile
FROM eclipse-temurin:21-jre-alpine@sha256:704db3c4...e7238b AS runtime

RUN addgroup -g 65532 -S nonroot \
 && adduser  -u 65532 -S nonroot -G nonroot -h /home/nonroot -s /sbin/nologin
USER 65532:65532
```

## Options considered

### A. Stay on Google distroless (`gcr.io/distroless/java21-debian13:nonroot`)

- **Pro:** Smallest attack surface (no shell, no coreutils, no apk/apt), Java
  21 LTS, free.
- **Pro:** Already adopted; zero migration cost.
- **Con:** CVE rebuild cadence is gated on Google's distroless release schedule
  — multi-day lag is routine, and the project has accumulated five active
  suppressions for upstream-fixed CVEs awaiting that rebuild.
- **Con:** No shell means `kubectl exec` requires temporarily swapping the
  image tag to `:debug` (documented in `Dockerfile` comments).

### B. Chainguard JRE (`cgr.dev/chainguard/jre:latest`)

- **Pro:** Daily rebuilds, Wolfi-based, pre-signed with sigstore (fits existing
  cosign flow), SBOM by default. Best-in-class CVE response.
- **Pro:** Free public registry tag (no auth required).
- **Con — disqualifying:** The free public `latest` tag tracks the **current**
  Java release, not LTS. As of 2026-05-11 it ships **Java 26**, not Java 21
  LTS. Pinning to `openjdk-21` requires the paid Chainguard Directory.
- **Con:** Java 21 bytecode runs forward on Java 26, but adopting a non-LTS
  runtime moves the project off the LTS support commitment it currently makes
  in `pom.xml` (`<java.version>21</java.version>`) and `.mise.toml`.

### C. Amazon Corretto Alpine (`amazoncorretto:21-alpine`)

- **Pro:** Java 21 LTS, AWS-stewarded, Alpine-based.
- **Pro:** Comparable rebuild cadence to Temurin.
- **Con:** Less neutral than the Adoptium/Temurin stewardship — Corretto is
  AWS-branded; the team has no AWS-specific reason to prefer it.
- **Con:** Smaller community than Temurin for Java 21.

### D. Eclipse Temurin 21 JRE on Alpine (`eclipse-temurin:21-jre-alpine`) — **chosen**

- **Pro:** Adoptium-official Java 21 LTS (currently `21.0.11+10-LTS`),
  stewarded by the same project that produces the JDK used in CI's build
  image — a single trust root for both build and runtime.
- **Pro:** Alpine 3.23 base. Renovate's `dockerfile` manager tracks the
  `FROM` line natively, and Adoptium publishes new Alpine images frequently —
  upstream-fixed Alpine CVEs land in days, not the multi-week distroless lag.
- **Pro:** Has BusyBox shell — `kubectl exec` for troubleshooting works
  without swapping image tags. Trade-off accepted: slightly larger attack
  surface in exchange for operational ergonomics.
- **Pro:** Image size ~80 MB compressed, comparable to distroless-debian13.
- **Pro:** Free, no vendor account required, no rate-limited registry.
- **Con:** Larger surface than distroless (shell present). Mitigations:
  read-only root filesystem at the K8s level if/when added, no package manager
  available at runtime (apk is present but unused; can be removed at build
  time if posture review requires).
- **Con:** Alpine uses musl libc instead of glibc. For a JVM-only workload
  with no JNI native dependencies, this is a non-issue. Flagged for future
  awareness if native libs are ever introduced.
- **Con:** Alpine ships no nonroot user by default — we create one explicitly
  at UID/GID 65532 to keep the K8s posture identical to distroless.

## Consequences

### Positive

- Faster CVE-fix turnaround. CVE-2026-41254 (the trigger) is already absent
  from `eclipse-temurin:21-jre-alpine` because Alpine's `lcms2` package
  shipped its fix before the Debian 13 base picked it up.
- Drop all five Debian-base suppressions from `.trivyignore` — those CVEs do
  not apply to Alpine packages.
- `kubectl exec` works out of the box for debugging; remove the
  "swap to `:debug` tag" workaround documented in the `Dockerfile`.
- Single Adoptium trust root for build + runtime (build stage was already
  `maven:3.9.x-eclipse-temurin-21`).

### Negative

- Marginally larger attack surface (presence of BusyBox shell + apk binary).
  Acceptable given the K8s posture (nonroot, restricted PSA, read-only root
  filesystem candidate).
- New Alpine-specific CVEs may surface that distroless masked or didn't ship.
  These will be visible to Trivy and addressed by Renovate-driven base bumps.
- musl libc — non-issue for current code; documented constraint for any
  future native dependencies.

### Neutral

- Cosign signing flow unchanged — image is signed at publish time regardless
  of base.
- `k8s/deployment.yml` unchanged — UID 65532 matches distroless convention.
- Multi-stage build structure unchanged. Build image and JAR extraction step
  are identical.

## Rollout

The pilot PR bundles all the changes together so the branch is mergeable as a
single self-contained unit:

1. **In this PR** (`chore/pilot-temurin-jre-alpine`):
   - `Dockerfile` runtime stage swap + explicit nonroot user creation
   - `.trivyignore` cleanup — five Debian-base distroless suppressions removed
   - `CLAUDE.md` Build Configuration Notes updated; `:debug`-tag-swap
     workaround note dropped
   - This ADR
   - Local smoke (`make image-build && make image-run`) verified
   - Local Trivy scan: zero HIGH/CRITICAL on Alpine layer + JAR layers
2. **Merge gate:** all CI jobs green on PR, including Trivy gate with HIGH/
   CRITICAL = 0 against the rebuilt image.
3. **Follow-ups after merge** (separate PRs as needed):
   - Update README.md if its architecture diagrams or prose mention
     distroless explicitly
   - Close issue [#223](https://github.com/AndriyKalashnykov/spring-on-k8s/issues/223)
4. **Rollback:** revert the `Dockerfile`, `.trivyignore`, and `CLAUDE.md`
   changes. The image is published to GHCR by digest, and previous
   distroless-based digests remain pullable.

## Verification

Local pilot results (2026-05-11):

- [x] `docker buildx build` succeeds; image 347 MB uncompressed (~102 MB
      compressed) vs prior distroless ~95 MB compressed — within the expected
      tolerance for a shell-bearing Alpine variant
- [x] Container starts as `65532:65532`; `/actuator/health/readiness` returns
      `UP`; `/v1/hello`, `/v1/bye`, `/actuator/prometheus` all respond
- [x] Trivy `--severity HIGH,CRITICAL --scanners vuln`: **zero** findings
      across Alpine 3.23 OS layer and every bundled JAR
- [ ] CI `docker` job green on the PR (gates Trivy + smoke + DAST end-to-end)
- [ ] `make e2e` green on the PR (KinD-based; verifies ConfigMap override
      still reaches the app under the new base)

## References

- Issue: [#223 — Scheduled CI failing: HIGH CVE-2026-41254 (liblcms2-2)](https://github.com/AndriyKalashnykov/spring-on-k8s/issues/223)
- Failing run: [25651901458](https://github.com/AndriyKalashnykov/spring-on-k8s/actions/runs/25651901458)
- Eclipse Temurin: <https://hub.docker.com/_/eclipse-temurin>
- Adoptium containers source: <https://github.com/adoptium/containers>
- Chainguard JRE (free tier — current-release Java): <https://images.chainguard.dev/directory/image/jre/overview>

## Addendum (2026-05): runtime bumped to Java 21 → 25 LTS

Shortly after this ADR landed, the runtime base image was bumped from
`eclipse-temurin:21-jre-alpine` to `eclipse-temurin:25-jre-alpine`
(digest-pinned `25.0.3_9-jre-alpine@sha256:c707…`) via a routine Renovate
`dockerfile`-manager update. The decision recorded above — distroless →
Adoptium Temurin JRE on Alpine — is unchanged; only the Java LTS line moved
forward. Java 25 is the current LTS; the build target stays Java 21
(`pom.xml` `<java.version>21</java.version>`, `.mise.toml` `temurin-21`,
`maven:3.9.x-eclipse-temurin-21` build stage), and Java 21 bytecode runs
forward on the Java 25 runtime — verified by the CI `docker` job's smoke
test on every push. The ADR title and Decision/Options body retain "21" as
the historically accurate record of the decision as made on 2026-05-11.
