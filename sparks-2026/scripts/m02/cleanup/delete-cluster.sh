#!/usr/bin/env bash
# Delete the training kind cluster (end of training, or full reset).
# Usage: ./delete-cluster.sh
set -eu
DIR="$(cd "$(dirname "$0")/../../setup" && pwd)"
. "$DIR/versions.env"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  kind delete cluster --name "$CLUSTER_NAME"
else
  echo "cluster $CLUSTER_NAME not found, nothing to delete"
fi
