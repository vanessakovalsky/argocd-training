#!/bin/sh
# Update the image of flotte-web in the dev overlay of flotte-config, then push.
# Used by the GitLab CI job "update-config" (and by the Jenkins demo).
set -eu
: "${CONFIG_REPO_URL:?URL of flotte-config (https://...)}"
: "${CONFIG_TOKEN:?token with write_repository on flotte-config}"
: "${NEW_IMAGE:?image to deploy (registry/name:tag)}"
COMMIT_AUTHOR="${COMMIT_AUTHOR:-flotte-ci}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# Token injected in the URL (https://oauth2:<token>@host/path), never printed
URL="$(printf '%s' "$CONFIG_REPO_URL" | sed -E "s#^(https?://)#\1oauth2:${CONFIG_TOKEN}@#")"
git clone -q --depth 1 "$URL" "$WORK/flotte-config"
cd "$WORK/flotte-config/apps/flotte-web/overlays/dev"
kustomize edit set image "ghcr.io/stefanprodan/podinfo=${NEW_IMAGE}"
git add kustomization.yaml
if git diff --cached --quiet; then
  echo "image already set to ${NEW_IMAGE}, nothing to commit"
  exit 0
fi
git -c user.name="$COMMIT_AUTHOR" -c user.email="${COMMIT_AUTHOR}@ci.invalid" \
  commit -q -m "ci: flotte-web dev -> ${NEW_IMAGE}"
git push -q origin HEAD
echo "flotte-config updated: ${NEW_IMAGE}"
