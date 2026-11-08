#!/usr/bin/env bash
# Install the CLI tools of the ArgoCD training (Linux x86-64), checksums verified.
# Usage: ./install-tools.sh [INSTALL_DIR]     (default: ~/.local/bin, must be in PATH)
# Idempotent: a tool already present in the expected version is skipped.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/versions.env"
DEST="${1:-$HOME/.local/bin}"
mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

has() { # tool, version string expected in its version output
  [ -x "$DEST/$1" ] && "$DEST/$1" $3 2>/dev/null | grep -q -- "$2"
}
check() { # file, expected sha256
  echo "$2  $1" | sha256sum -c --quiet || { echo "checksum KO: $1"; exit 1; }
}

# kind
if has kind "$KIND_VERSION" version; then echo "kind ok"; else
  curl -fsSLO "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64"
  curl -fsSLO "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64.sha256sum"
  check kind-linux-amd64 "$(cut -d' ' -f1 kind-linux-amd64.sha256sum)"
  install -m 0755 kind-linux-amd64 "$DEST/kind"; echo "kind installed"
fi
# kubectl
if has kubectl "$KUBECTL_VERSION" "version --client"; then echo "kubectl ok"; else
  curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  check kubectl "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256")"
  install -m 0755 kubectl "$DEST/kubectl"; echo "kubectl installed"
fi
# argocd
if has argocd "$ARGOCD_VERSION" "version --client --short"; then echo "argocd ok"; else
  curl -fsSLO "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
  curl -fsSLO "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/cli_checksums.txt"
  check argocd-linux-amd64 "$(awk '$2=="argocd-linux-amd64"{print $1}' cli_checksums.txt)"
  install -m 0755 argocd-linux-amd64 "$DEST/argocd"; echo "argocd installed"
fi
# helm
if has helm "$HELM_VERSION" "version --short"; then echo "helm ok"; else
  curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
  check "helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    "$(curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" | cut -d' ' -f1)"
  tar -xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz" linux-amd64/helm
  install -m 0755 linux-amd64/helm "$DEST/helm"; echo "helm installed"
fi
# kubectl-argo-rollouts
if has kubectl-argo-rollouts "$ROLLOUTS_VERSION" "version --short"; then echo "kubectl-argo-rollouts ok"; else
  B=https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}
  curl -fsSLO "$B/kubectl-argo-rollouts-linux-amd64"
  curl -fsSLO "$B/argo-rollouts-checksums.txt"
  check kubectl-argo-rollouts-linux-amd64 \
    "$(awk '$2=="kubectl-argo-rollouts-linux-amd64"{print $1}' argo-rollouts-checksums.txt)"
  install -m 0755 kubectl-argo-rollouts-linux-amd64 "$DEST/kubectl-argo-rollouts"; echo "kubectl-argo-rollouts installed"
fi
# kubeseal
V="${SEALED_SECRETS_VERSION#v}"
if has kubeseal "$V" "--version"; then echo "kubeseal ok"; else
  B=https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}
  curl -fsSLO "$B/kubeseal-${V}-linux-amd64.tar.gz"
  curl -fsSLO "$B/sealed-secrets_${V}_checksums.txt"
  check "kubeseal-${V}-linux-amd64.tar.gz" \
    "$(awk -v f="kubeseal-${V}-linux-amd64.tar.gz" '$2==f{print $1}' "sealed-secrets_${V}_checksums.txt")"
  tar -xzf "kubeseal-${V}-linux-amd64.tar.gz" kubeseal
  install -m 0755 kubeseal "$DEST/kubeseal"; echo "kubeseal installed"
fi
echo "Tools installed in $DEST"
