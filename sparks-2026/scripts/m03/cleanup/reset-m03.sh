#!/usr/bin/env bash
# Remove M03 objects (project, repository, accounts, RBAC policy). Settings keys kept.
set -eu
kubectl delete appproject flotte -n argocd --ignore-not-found
kubectl delete secret repo-flotte-config -n argocd --ignore-not-found
kubectl patch cm argocd-rbac-cm -n argocd --type merge -p '{"data":{"policy.csv":"","policy.default":""}}'
kubectl patch cm argocd-cm -n argocd --type merge -p \
  '{"data":{"accounts.dev-alice":null,"accounts.ops-bob":null,"accounts.audit-claire":null,"accounts.ci-gitlab":null}}'
echo "M03 objects removed"
