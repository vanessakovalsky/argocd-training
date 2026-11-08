#!/usr/bin/env bash
# M08 catch-up - Argo Rollouts installed; flotte-web (dev) as a canary Rollout;
# flotte-web-recette (blue-green) created and synced.
# Prerequisite: M07 final state. Same variables as m04-final-state.sh.
set -eu
: "${FLOTTE_PUSH_URL:?}" "${FLOTTE_REPO_URL:?}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
L="$ROOT/labs/m08"
"$ROOT/scripts/m08/labs/install-rollouts.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone -q "$FLOTTE_PUSH_URL" "$WORK/repo"
cd "$WORK/repo"
A=apps/flotte-web
if [ -f "$A/deployment.yaml" ]; then
  git rm -q "$A/deployment.yaml"
  cp "$L/rollout-canary.yaml" "$A/rollout.yaml"
fi
mkdir -p apps/flotte-web-recette
cp "$L"/flotte-web-recette/*.yaml apps/flotte-web-recette/
sed "s|https://gitlab.com/<GITLAB_USER>/flotte-config.git|$FLOTTE_REPO_URL|" \
  "$L/flotte-web-recette-app.yaml" > argocd/flotte-web-recette.yaml
git add -A
if git diff --cached --quiet; then
  echo "flotte-config already up to date"
else
  git -c user.name="catch-up" -c user.email="catch-up@formation.invalid" \
    commit -qm "feat: Rollouts canari (dev) et bleu-vert (recette) (rattrapage M08)"
  git push -q "$FLOTTE_PUSH_URL" HEAD:main
fi
kubectl apply -f argocd/flotte-web-recette.yaml
for env in dev recette; do
  argocd app get "flotte-web-$env" --refresh >/dev/null
done
sleep 20
# A paused rollout (manual step) is fully promoted to reach the final state
for env in dev recette; do
  kubectl argo rollouts promote flotte-web -n "flotte-$env" --full >/dev/null 2>&1 || true
done
argocd app wait flotte-web-dev flotte-web-recette --sync --health --timeout 300 | grep -E "Sync Status|Health Status"
echo "M08 final state OK"
