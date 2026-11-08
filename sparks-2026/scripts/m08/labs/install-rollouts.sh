#!/usr/bin/env bash
# M08 - Install the Argo Rollouts controller (idempotent). Plugin: see setup-environnement.md.
set -eu
DIR="$(cd "$(dirname "$0")/../../setup" && pwd)"
. "$DIR/versions.env"
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -n argo-rollouts --server-side --force-conflicts \
  -f "https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}/install.yaml" >/dev/null
kubectl rollout status deploy/argo-rollouts -n argo-rollouts --timeout=300s
kubectl get crd | grep -E 'rollouts|analysis|experiments'
