#!/usr/bin/env bash
# M12 catch-up - ApplicationSet flotte-web generating flotte-web-<overlay> (prod excluded),
# file committed in flotte-config/argocd/.
# Prerequisite: M11 final state. Same variables as m04-final-state.sh.
set -eu
: "${FLOTTE_PUSH_URL:?}" "${FLOTTE_REPO_URL:?}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone -q "$FLOTTE_PUSH_URL" "$WORK/repo"
cd "$WORK/repo"
sed "s|https://gitlab.com/<GITLAB_USER>/flotte-config.git|$FLOTTE_REPO_URL|g" \
  "$ROOT/labs/m12/applicationset-flotte-web.yaml" > argocd/applicationset-flotte-web.yaml
git add -A
if git diff --cached --quiet; then
  echo "flotte-config already up to date"
else
  git -c user.name="catch-up" -c user.email="catch-up@formation.invalid" \
    commit -qm "feat: ApplicationSet flotte-web (rattrapage M12)"
  git push -q "$FLOTTE_PUSH_URL" HEAD:main
fi
kubectl apply -f argocd/applicationset-flotte-web.yaml
sleep 15
kubectl get applicationset flotte-web -n argocd \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
argocd app list | awk 'NR==1 || /flotte-web/ {print $1, $5, $6}'
echo "M12 final state OK"
