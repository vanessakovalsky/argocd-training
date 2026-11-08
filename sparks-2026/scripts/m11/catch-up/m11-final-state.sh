#!/usr/bin/env bash
# M11 catch-up - Sealed Secrets controller installed; flotte-web-secrets sealed for flotte-dev
# and referenced by the Rollout (optional secretRef); project role ci-deployer.
# Prerequisites: M10 final state, kubeseal CLI. Same variables as m04-final-state.sh.
set -eu
: "${FLOTTE_PUSH_URL:?}" "${FLOTTE_REPO_URL:?}"
DIR="$(cd "$(dirname "$0")/../../setup" && pwd)"
. "$DIR/versions.env"
kubectl apply --server-side \
  -f "https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/controller.yaml" >/dev/null
kubectl rollout status deploy/sealed-secrets-controller -n kube-system --timeout=300s
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone -q "$FLOTTE_PUSH_URL" "$WORK/repo"
cd "$WORK/repo"
R=apps/flotte-web/base/rollout.yaml
if ! grep -q 'name: flotte-web-secrets' "$R"; then
  sed -i 's/^                name: flotte-web-config$/                name: flotte-web-config\n            - secretRef:\n                name: flotte-web-secrets\n                optional: true/' "$R"
fi
O=apps/flotte-web/overlays/dev
if [ ! -f "$O/sealed-secret.yaml" ]; then
  # The value is a training placeholder; sealing uses the public key of THIS cluster
  kubectl create secret generic flotte-web-secrets -n flotte-dev \
    --from-literal=FLOTTE_API_KEY=hexa-dev-0001 --dry-run=client -o yaml \
    | kubeseal --format yaml > "$O/sealed-secret.yaml"
  (cd "$O" && kustomize edit add resource sealed-secret.yaml 2>/dev/null) \
    || sed -i 's#^- ../../base$#- ../../base\n- sealed-secret.yaml#' "$O/kustomization.yaml"
fi
git add -A
if git diff --cached --quiet; then
  echo "flotte-config already up to date"
else
  git -c user.name="catch-up" -c user.email="catch-up@formation.invalid" \
    commit -qm "feat: secret scelle pour dev (rattrapage M11)"
  git push -q "$FLOTTE_PUSH_URL" HEAD:main
fi
argocd proj role create flotte ci-deployer \
  --description "Pipeline CI : synchronisation des applications du projet" >/dev/null 2>&1 || true
argocd proj role add-policy flotte ci-deployer --action get --permission allow --object '*' >/dev/null 2>&1 || true
argocd proj role add-policy flotte ci-deployer --action sync --permission allow --object 'flotte-*' >/dev/null 2>&1 || true
argocd app get flotte-web-dev --refresh >/dev/null
sleep 40
kubectl argo rollouts promote flotte-web -n flotte-dev --full >/dev/null 2>&1 || true
argocd app wait flotte-web-dev --sync --health --timeout 300 | grep -E "Sync Status|Health Status"
kubectl get secret flotte-web-secrets -n flotte-dev
echo "M11 final state OK"
