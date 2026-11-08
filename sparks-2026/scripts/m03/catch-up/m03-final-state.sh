#!/usr/bin/env bash
# M03 catch-up - settings, accounts, RBAC, AppProject flotte, repository flotte-config.
# Prerequisite: M02 final state (CLI logged in as admin on localhost:8443).
# Usage:
#   GITLAB_USER=<user> GITLAB_DEPLOY_USER=<gitlab+deploy-token-N> GITLAB_DEPLOY_TOKEN=<token> \
#   ARGOCD_ADMIN_PASSWORD='<pwd>' ./m03-final-state.sh
set -eu
: "${GITLAB_USER:?}" "${GITLAB_DEPLOY_USER:?}" "${GITLAB_DEPLOY_TOKEN:?}" "${ARGOCD_ADMIN_PASSWORD:?}"
L="$(cd "$(dirname "$0")/../labs" && pwd)"
subst() { sed -e "s|\${GITLAB_USER}|$GITLAB_USER|g" -e "s|\${GITLAB_DEPLOY_USER}|$GITLAB_DEPLOY_USER|g" \
              -e "s|\${GITLAB_DEPLOY_TOKEN}|$GITLAB_DEPLOY_TOKEN|g" "$1"; }

kubectl patch cm argocd-cm -n argocd --type merge -p \
  '{"data":{"url":"https://localhost:8443","ui.bannercontent":"Cluster de formation - Hexa Mobilite","statusbadge.enabled":"true"}}'
kubectl patch cm argocd-cm -n argocd --type merge --patch-file "$L/argocd-cm-accounts.yaml"
kubectl apply --server-side --force-conflicts -f "$L/argocd-rbac-cm.yaml"
subst "$L/appproject-flotte.yaml" | kubectl apply -f -
subst "$L/repo-flotte-config.yaml" | kubectl apply -f -
sleep 3

argocd login localhost:8443 --username admin --password "$ARGOCD_ADMIN_PASSWORD" --insecure >/dev/null
for u in dev-alice ops-bob audit-claire; do
  # Password = Mdp-<account>-2026 (training only); re-setting it is harmless
  argocd account update-password --account "$u" \
    --current-password "$ARGOCD_ADMIN_PASSWORD" --new-password "Mdp-$u-2026"
done
argocd account list
argocd repo list
echo "M03 final state OK"
