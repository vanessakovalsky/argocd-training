#!/usr/bin/env bash
# M09 catch-up - flotte-web as Kustomize base + overlays (dev, recette, prod),
# flotte-api-dev deployed from the podinfo Helm chart with values stored in Git.
# Prerequisite: M08 final state. Same variables as m04-final-state.sh.
set -eu
: "${FLOTTE_PUSH_URL:?}" "${FLOTTE_REPO_URL:?}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
L="$ROOT/labs/m09"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

argocd proj add-source flotte https://stefanprodan.github.io/podinfo >/dev/null 2>&1 || true

git clone -q "$FLOTTE_PUSH_URL" "$WORK/repo"
cd "$WORK/repo"
# Flat files of M04-M08 replaced by the Kustomize structure
find apps/flotte-web -maxdepth 1 -type f -name '*.yaml' -exec git rm -q {} \; 2>/dev/null || true
[ -d apps/flotte-web-recette ] && git rm -rq apps/flotte-web-recette
mkdir -p apps/flotte-web helm argocd
cp -r "$L/apps/flotte-web/base" "$L/apps/flotte-web/overlays" apps/flotte-web/
cp -r "$L/helm/flotte-api" helm/
for f in flotte-web-dev flotte-web-recette flotte-api-dev; do
  sed "s|https://gitlab.com/<GITLAB_USER>/flotte-config.git|$FLOTTE_REPO_URL|" \
    "$L/argocd/$f.yaml" > "argocd/$f.yaml"
done
git add -A
if git diff --cached --quiet; then
  echo "flotte-config already up to date"
else
  git -c user.name="catch-up" -c user.email="catch-up@formation.invalid" \
    commit -qm "refactor: Kustomize base/overlays, flotte-api Helm (rattrapage M09)"
  git push -q "$FLOTTE_PUSH_URL" HEAD:main
fi
kubectl apply -f argocd/flotte-web-dev.yaml -f argocd/flotte-web-recette.yaml -f argocd/flotte-api-dev.yaml
for a in flotte-web-dev flotte-web-recette flotte-api-dev; do argocd app get "$a" --refresh >/dev/null; done
sleep 30
for env in dev recette; do
  kubectl argo rollouts promote flotte-web -n "flotte-$env" --full >/dev/null 2>&1 || true
done
argocd app wait flotte-web-dev flotte-web-recette flotte-api-dev --sync --health --timeout 300 \
  | grep -E "Sync Status|Health Status"
echo "M09 final state OK"
