#!/usr/bin/env bash
# Pre-pull training images to save time and bandwidth on day 1.
# Usage: ./pull-images.sh          (idempotent; loads images into kind if the cluster exists)
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/versions.env"
if docker info >/dev/null 2>&1; then ENGINE=docker
elif podman info >/dev/null 2>&1; then ENGINE=podman
else echo "Neither docker nor podman responds" >&2; exit 1; fi
echo "engine: $ENGINE"

MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
IMAGES="$K8S_NODE_IMAGE $(curl -fsSL "$MANIFEST" | awk '/^ *image:/ {print $2}' | sort -u)"
for t in $PODINFO_TAGS; do IMAGES="$IMAGES $PODINFO_IMAGE:$t"; done

qualify() { # podman refuses short names: add docker.io/ when the first component is not a registry
  case "${1%%/*}" in *.*|*:*|localhost) echo "$1" ;; *) [ "$1" = "${1#*/}" ] && echo "docker.io/library/$1" || echo "docker.io/$1" ;; esac
}
for img in $IMAGES; do
  [ "$ENGINE" = podman ] && img="$(qualify "$img")"
  echo "pull $img"
  "$ENGINE" pull -q "$img" >/dev/null
done

if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  for img in $IMAGES; do
    case "$img" in kindest/*) continue ;; esac
    kind load docker-image "$img" --name "$CLUSTER_NAME" >/dev/null && echo "loaded $img"
  done
fi
echo "done"
