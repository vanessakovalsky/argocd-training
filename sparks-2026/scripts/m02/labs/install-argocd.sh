#!/usr/bin/env bash
# M02 - Create the kind cluster and install Argo CD (idempotent).
# Usage: ./install-argocd.sh
set -eu
DIR="$(cd "$(dirname "$0")/../../setup" && pwd)"
. "$DIR/versions.env"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "cluster $CLUSTER_NAME already exists"
else
  kind create cluster --config "$DIR/kind-config.yaml"
fi
kubectl config use-context "kind-$CLUSTER_NAME" >/dev/null

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" >/dev/null
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=600s
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s
kubectl get pods -n argocd
