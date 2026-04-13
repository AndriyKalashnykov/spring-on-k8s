#!/usr/bin/env bash
# Install MetalLB in the running KinD cluster and configure an IP address pool
# within the docker 'kind' network subnet so LoadBalancer Services get reachable
# external IPs.
#
# Inputs:
#   METALLB_VERSION  required, e.g. 0.14.8

set -euo pipefail

: "${METALLB_VERSION:?METALLB_VERSION must be set}"

echo "Installing MetalLB ${METALLB_VERSION}..."
kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/v${METALLB_VERSION}/config/manifests/metallb-native.yaml"

echo "Waiting for MetalLB controller Deployment to roll out..."
kubectl -n metallb-system rollout status deployment/controller --timeout=180s

echo "Waiting for MetalLB speaker DaemonSet to roll out..."
kubectl -n metallb-system rollout status daemonset/speaker --timeout=180s

echo "Waiting for MetalLB pods to be ready..."
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=120s

# The kind docker network has both IPv4 and IPv6 subnets; pick the IPv4 one.
SUBNET=$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' \
  | tr ' ' '\n' \
  | grep -E '^[0-9]+\.' \
  | head -1)

if [ -z "${SUBNET}" ]; then
  echo "FAIL: could not determine IPv4 subnet of kind docker network"
  docker network inspect kind
  exit 1
fi

POOL_RANGE=$(echo "${SUBNET}" | awk -F. '{print $1"."$2".255.200-"$1"."$2".255.250"}')
echo "Configuring MetalLB IP pool: ${POOL_RANGE}"

kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - ${POOL_RANGE}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
  labels:
    app.kubernetes.io/name: metallb
spec:
  ipAddressPools:
    - default-pool
EOF

echo "MetalLB configured."
