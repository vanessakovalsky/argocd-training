#!/usr/bin/env bash
# M04 catch-up - push the flotte-web manifests to flotte-config, create and sync flotte-web-dev.
# Prerequisite: M03 final state (project flotte, repository declared, CLI logged in as admin).
# Usage:
#   FLOTTE_PUSH_URL=https://oauth2:<TOKEN>@gitlab.com/<GITLAB_USER>/flotte-config.git \
#   FLOTTE_REPO_URL=https://gitlab.com/<GITLAB_USER>/flotte-config.git ./m04-final-state.sh
set -eu
: "${FLOTTE_PUSH_URL:?}" "${FLOTTE_REPO_URL:?}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="$ROOT/labs/flotte-config"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone -q "$FLOTTE_PUSH_URL" "$WORK/repo" 2>/dev/null || { mkdir -p "$WORK/repo"; git -C "$WORK/repo" init -q -b main; }
mkdir -p "$WORK/repo/apps/flotte-web" "$WORK/repo/argocd"
cp "$SRC"/apps/flotte-web/*.yaml "$WORK/repo/apps/flotte-web/"
sed "s|https://gitlab.com/<GITLAB_USER>/flotte-config.git|$FLOTTE_REPO_URL|" \
  "$SRC/argocd/flotte-web-dev.yaml" > "$WORK/repo/argocd/flotte-web-dev.yaml"
[ -f "$WORK/repo/README.md" ] || cp "$SRC/README.md" "$WORK/repo/"
cd "$WORK/repo"
git add -A
if git diff --cached --quiet; then
  echo "flotte-config already up to date"
else
  git -c user.name="catch-up" -c user.email="catch-up@formation.invalid" \
    commit -qm "feat: flotte-web 6.15.0 (rattrapage M04)"
  git push -q "$FLOTTE_PUSH_URL" HEAD:main
fi

kubectl apply -f argocd/flotte-web-dev.yaml
argocd app sync flotte-web-dev >/dev/null
argocd app wait flotte-web-dev --health --timeout 300 | grep -E "Sync Status|Health Status"
echo "M04 final state OK"
