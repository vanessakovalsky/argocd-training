#!/usr/bin/env bash
# Remove the recette application and the Argo Rollouts controller.
# flotte-web (dev) must be switched back to a Deployment in Git BEFORE removing the controller.
set -eu
argocd app delete flotte-web-recette --yes 2>/dev/null || echo "flotte-web-recette not found"
kubectl delete namespace flotte-recette --ignore-not-found --wait=false
echo "To remove the controller: kubectl delete -n argo-rollouts -f <install.yaml> ; kubectl delete namespace argo-rollouts"
