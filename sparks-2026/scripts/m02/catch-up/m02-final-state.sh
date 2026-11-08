#!/usr/bin/env bash
# M02 catch-up - bring the workstation to the M02 final state:
# cluster + Argo CD + argocd-server on NodePort 30443 (https://localhost:8443)
# + admin password set to $ARGOCD_ADMIN_PASSWORD + CLI logged in.
# Usage: ARGOCD_ADMIN_PASSWORD='<PASSWORD>' ./m02-final-state.sh
set -eu
: "${ARGOCD_ADMIN_PASSWORD:?set ARGOCD_ADMIN_PASSWORD (min 8 chars)}"
HERE="$(cd "$(dirname "$0")" && pwd)"
"$HERE/../labs/install-argocd.sh"

kubectl patch svc argocd-server -n argocd --type merge -p \
  '{"spec":{"type":"NodePort","ports":[{"name":"http","port":80,"protocol":"TCP","targetPort":8080,"nodePort":30080},{"name":"https","port":443,"protocol":"TCP","targetPort":8080,"nodePort":30443}]}}' >/dev/null
sleep 3

# Try the target password first (already set by a previous run)
if argocd login localhost:8443 --username admin --password "$ARGOCD_ADMIN_PASSWORD" --insecure >/dev/null 2>&1; then
  echo "admin password already set"
else
  INIT="$(argocd admin initial-password -n argocd | head -1)"
  argocd login localhost:8443 --username admin --password "$INIT" --insecure >/dev/null
  argocd account update-password --current-password "$INIT" --new-password "$ARGOCD_ADMIN_PASSWORD"
  argocd login localhost:8443 --username admin --password "$ARGOCD_ADMIN_PASSWORD" --insecure >/dev/null
fi
kubectl delete secret argocd-initial-admin-secret -n argocd --ignore-not-found >/dev/null
argocd account get-user-info
echo "M02 final state OK: https://localhost:8443"
