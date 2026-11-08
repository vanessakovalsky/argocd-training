#!/usr/bin/env bash
# M07 catch-up - progress deadline 60 s, webhook receiver, notifications (flotte-deployed,
# flotte-degraded) subscribed by flotte-web-dev.
# Prerequisite: M06 final state. Same variables as m04-final-state.sh.
# Optional: WITH_PROMETHEUS=1 also deploys the minimal Prometheus.
set -eu
: "${FLOTTE_PUSH_URL:?}" "${FLOTTE_REPO_URL:?}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
L="$ROOT/labs/m07"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

kubectl create namespace flotte-ops --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f "$L/webhook-receiver.yaml"
kubectl patch cm argocd-notifications-cm -n argocd --type merge --patch-file "$L/argocd-notifications-cm-patch.yaml"
[ "${WITH_PROMETHEUS:-0}" = "1" ] && kubectl apply -f "$L/prometheus-minimal.yaml"

git clone -q "$FLOTTE_PUSH_URL" "$WORK/repo"
cd "$WORK/repo"
D=apps/flotte-web/deployment.yaml
grep -q progressDeadlineSeconds "$D" || \
  sed -i -E 's/^(  replicas: [0-9]+)$/\1\n  progressDeadlineSeconds: 60/' "$D"
sed "s|https://gitlab.com/<GITLAB_USER>/flotte-config.git|$FLOTTE_REPO_URL|" \
  "$L/flotte-web-dev-notif.yaml" > argocd/flotte-web-dev.yaml
git add -A
if git diff --cached --quiet; then
  echo "flotte-config already up to date"
else
  git -c user.name="catch-up" -c user.email="catch-up@formation.invalid" \
    commit -qm "feat: supervision et notifications (rattrapage M07)"
  git push -q "$FLOTTE_PUSH_URL" HEAD:main
fi
kubectl apply -f argocd/flotte-web-dev.yaml
kubectl rollout status deploy/alertes-receiver -n flotte-ops --timeout=180s
argocd app get flotte-web-dev --refresh >/dev/null
argocd app wait flotte-web-dev --sync --health --timeout 300 | grep -E "Sync Status|Health Status"
echo "M07 final state OK"
