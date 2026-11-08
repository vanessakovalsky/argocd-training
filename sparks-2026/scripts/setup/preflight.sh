#!/usr/bin/env bash
# Preflight checks for the ArgoCD training workstation.
# Usage: ./preflight.sh            (run at D-7 and at the start of day 1)
# Output: one line per check, OK / KO / WARN. Exit code = number of KO.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=versions.env
. "$DIR/versions.env"

KO=0
ok()   { printf 'OK    %s\n' "$1"; }
ko()   { printf 'KO    %s\n' "$1"; KO=$((KO+1)); }
warn() { printf 'WARN  %s\n' "$1"; }

# 1. Hardware
cpu=$(nproc 2>/dev/null || echo 0)
[ "$cpu" -ge "$MIN_CPU" ] && ok "CPU: $cpu vCPU (min $MIN_CPU)" || ko "CPU: $cpu vCPU (min $MIN_CPU)"
mem=$(awk '/MemAvailable/ {printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)
[ "$mem" -ge "$MIN_MEM_GB" ] && ok "RAM available: ${mem} GB (min $MIN_MEM_GB)" \
  || ko "RAM available: ${mem} GB (min $MIN_MEM_GB)"

# 2. Container engine
if docker info >/dev/null 2>&1; then ok "Container engine: docker"
elif podman info >/dev/null 2>&1; then ok "Container engine: podman (set KIND_EXPERIMENTAL_PROVIDER=podman)"
else ko "Container engine: neither docker nor podman responds"; fi

# 3. Tools
check_tool() { # name, version command
  if command -v "$1" >/dev/null 2>&1; then ok "$1: $(eval "$2" 2>/dev/null | head -1)"
  else ko "$1: not installed"; fi
}
check_tool git     "git --version"
check_tool kind    "kind version"
check_tool kubectl "kubectl version --client 2>/dev/null | head -1"
check_tool argocd  "argocd version --client --short"
check_tool helm    "helm version --short"
check_tool kubectl-argo-rollouts "kubectl-argo-rollouts version --short"
check_tool kubeseal "kubeseal --version"
if command -v kind >/dev/null 2>&1; then
  kind version | grep -q "$KIND_VERSION" && ok "kind version $KIND_VERSION" \
    || warn "kind version differs from $KIND_VERSION"
fi
if command -v argocd >/dev/null 2>&1; then
  argocd version --client --short 2>/dev/null | grep -q "$ARGOCD_VERSION" \
    && ok "argocd CLI $ARGOCD_VERSION" || warn "argocd CLI differs from $ARGOCD_VERSION"
fi

# 4. Network (proxy, registries, Git hosting)
for url in https://raw.githubusercontent.com https://gitlab.com https://quay.io/v2/ \
           https://ghcr.io/v2/ https://public.ecr.aws; do
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$url" || echo 000)
  case "$code" in
    000) ko "Network: $url unreachable (proxy?)" ;;
    *)   ok "Network: $url (HTTP $code)" ;;
  esac
done

# 5. Local ports
for p in $PORTS; do
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$p\$"; then ko "Port $p already in use"
  else ok "Port $p free"; fi
done

echo "----"
[ "$KO" -eq 0 ] && echo "Result: workstation ready" || echo "Result: $KO blocking check(s)"
exit "$KO"
