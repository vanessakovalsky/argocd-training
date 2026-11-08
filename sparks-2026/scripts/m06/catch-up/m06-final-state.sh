#!/usr/bin/env bash
# M06 catch-up - flotte-web back to 6.16.0 in Git (after the 6.17.0 rollback),
# auto-sync re-enabled, separate RBAC permission for rollback enforced.
# Prerequisite: M05 final state. Same variables as m04-final-state.sh.
set -eu
: "${FLOTTE_PUSH_URL:?}" "${FLOTTE_REPO_URL:?}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone -q "$FLOTTE_PUSH_URL" "$WORK/repo"
cd "$WORK/repo"
A=apps/flotte-web
sed -i -E 's#(ghcr.io/stefanprodan/podinfo:)[0-9.]+#\16.16.0#' "$A/deployment.yaml"
sed -i -E 's#^(  PODINFO_UI_MESSAGE: ).*#\1"Hexa Mobilite - suivi de flotte"#' "$A/configmap.yaml"
sed "s|https://gitlab.com/<GITLAB_USER>/flotte-config.git|$FLOTTE_REPO_URL|" \
  "$ROOT/labs/m05/flotte-web-dev-auto.yaml" > argocd/flotte-web-dev.yaml
git add -A
if git diff --cached --quiet; then
  echo "flotte-config already up to date"
else
  git -c user.name="catch-up" -c user.email="catch-up@formation.invalid" \
    commit -qm "fix: retour a flotte-web 6.16.0 (rattrapage M06)"
  git push -q "$FLOTTE_PUSH_URL" HEAD:main
fi
kubectl patch cm argocd-cm -n argocd --type merge \
  -p '{"data":{"server.rbac.rollback.enforce.enable":"true"}}'
kubectl apply -f argocd/flotte-web-dev.yaml
argocd app get flotte-web-dev --refresh >/dev/null
argocd app wait flotte-web-dev --sync --health --timeout 300 | grep -E "Sync Status|Health Status"
kubectl get deploy flotte-web -n flotte-dev -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
echo "M06 final state OK"
