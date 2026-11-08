#!/usr/bin/env bash
# M05 catch-up - auto-sync (prune, self-heal), 3 replicas, sync wave -1 on the ConfigMap,
# PreSync migration and PostSync smoke test hooks.
# Prerequisite: M04 final state. Same variables as m04-final-state.sh.
set -eu
: "${FLOTTE_PUSH_URL:?}" "${FLOTTE_REPO_URL:?}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
L="$ROOT/labs/m05"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone -q "$FLOTTE_PUSH_URL" "$WORK/repo"
cd "$WORK/repo"
A=apps/flotte-web
cp "$L/hook-presync-migration.yaml" "$L/hook-postsync-smoke-test.yaml" "$A/"
sed -i 's/replicas: 2$/replicas: 3/' "$A/deployment.yaml"
grep -q 'sync-wave' "$A/configmap.yaml" || \
  sed -i 's/^  name: flotte-web-config$/  name: flotte-web-config\n  annotations:\n    argocd.argoproj.io\/sync-wave: "-1"/' "$A/configmap.yaml"
sed "s|https://gitlab.com/<GITLAB_USER>/flotte-config.git|$FLOTTE_REPO_URL|" \
  "$L/flotte-web-dev-auto.yaml" > argocd/flotte-web-dev.yaml
git add -A
if git diff --cached --quiet; then
  echo "flotte-config already up to date"
else
  git -c user.name="catch-up" -c user.email="catch-up@formation.invalid" \
    commit -qm "feat: synchronisation automatique, hooks, vague -1 (rattrapage M05)"
  git push -q "$FLOTTE_PUSH_URL" HEAD:main
fi
kubectl apply -f argocd/flotte-web-dev.yaml
argocd app get flotte-web-dev --refresh >/dev/null
argocd app wait flotte-web-dev --sync --health --timeout 300 | grep -E "Sync Status|Health Status"
echo "M05 final state OK"
