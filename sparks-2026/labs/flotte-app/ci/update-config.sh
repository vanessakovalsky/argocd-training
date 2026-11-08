#!/bin/sh
# Update the image of flotte-web in the dev overlay of flotte-config, then push.
# Used by the GitLab CI job "update-config" (and by the Jenkins demo).
X
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
