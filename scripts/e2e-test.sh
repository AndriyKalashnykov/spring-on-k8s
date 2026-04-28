#!/usr/bin/env bash
# End-to-end smoke test against a running KinD deployment of spring-on-k8s.
#
# Assumes: `make kind-up` has succeeded — namespace `spring-on-k8s` exists,
# Deployment `app` is ready, Service `app` is type LoadBalancer, and the
# cloud-provider-kind controller has assigned it an external IP from the
# KinD Docker network subnet.

set -euo pipefail

NS=spring-on-k8s
SVC=app
EXPECTED_MESSAGE="Hello Kubernetes!"

echo "Waiting for LoadBalancer IP on svc/${SVC} in ns ${NS}..."
EXTERNAL_IP=""
for _ in $(seq 1 60); do
  EXTERNAL_IP=$(kubectl -n "${NS}" get svc "${SVC}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -n "${EXTERNAL_IP}" ]; then
    break
  fi
  sleep 2
done

if [ -z "${EXTERNAL_IP}" ]; then
  echo "FAIL: LoadBalancer IP not assigned after 120s"
  kubectl -n "${NS}" get svc "${SVC}" -o yaml
  exit 1
fi

echo "LoadBalancer IP: ${EXTERNAL_IP}"
BASE_URL="http://${EXTERNAL_IP}"

assert_contains() {
  local path="$1" expected="$2"
  local body
  body=$(curl -sSf --max-time 10 "${BASE_URL}${path}")
  if echo "${body}" | grep -qF "${expected}"; then
    echo "  PASS  GET ${path}  (contains '${expected}')"
  else
    echo "  FAIL  GET ${path}  (expected '${expected}', got: ${body})"
    exit 1
  fi
}

assert_status() {
  local path="$1" expected="$2"
  local status
  status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${BASE_URL}${path}")
  if [ "${status}" = "${expected}" ]; then
    echo "  PASS  GET ${path}  (status ${status})"
  else
    echo "  FAIL  GET ${path}  (status ${status}, expected ${expected})"
    exit 1
  fi
}

echo "Running e2e checks..."
assert_contains /             'Hello world'
assert_contains /v1/hello "${EXPECTED_MESSAGE}"
assert_contains /v1/bye   "${EXPECTED_MESSAGE}"
assert_contains /actuator/health/liveness  '"status":"UP"'
assert_contains /actuator/health/readiness '"status":"UP"'
assert_contains /actuator/prometheus       'jvm_memory_used_bytes'
assert_contains /actuator/prometheus       'http_server_requests_seconds_count'
assert_contains /v3/api-docs               '/v1/hello'
assert_status   /does-not-exist-abc 404

echo "All e2e checks passed."
