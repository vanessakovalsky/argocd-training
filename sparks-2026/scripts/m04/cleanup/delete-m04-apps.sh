#!/usr/bin/env bash
# Delete the M04 Applications (cascade) and their namespaces.
set -eu
for app in flotte-web-dev flotte-web-helm flotte-web-kustomize; do
  argocd app delete "$app" --yes 2>/dev/null && echo "deleted $app" || echo "$app not found"
done
kubectl delete namespace flotte-dev flotte-preview flotte-kust --ignore-not-found --wait=false
