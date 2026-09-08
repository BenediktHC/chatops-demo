#!/usr/bin/env bash
# Baut den Demo-Cluster von Null auf.
# Laufzeit ca. 5 bis 8 Minuten, davon der groessere Teil auf Argo CD.
#
#   ./setup.sh                 Standard
#   AUDIT=1 ./setup.sh         zusaetzlich Audit-Log im API-Server
#   SKIP_ARGOCD=1 ./setup.sh   ohne Argo CD
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFIL="chatops-demo"
K8S_VERSION="${K8S_VERSION:-v1.31.0}"

say() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }

for bin in minikube kubectl git; do
  command -v "$bin" >/dev/null || { echo "FEHLT: $bin"; exit 1; }
done

if ! git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
  cat <<'HINWEIS'

  Kein Git-Remote gesetzt. break.sh und fix.sh pushen aber nach GitHub,
  weil Argo CD von dort liest. Einmalig einrichten:

    git init
    git remote add origin https://github.com/BenediktHC/chatops-demo.git
    git add -A && git commit -m "Ausgangszustand"
    git push -u origin main

HINWEIS
  exit 1
fi

EXTRA=()
if [ "${AUDIT:-0}" = "1" ]; then
  say "Audit-Regeln in die minikube-VM legen"
  MHOME="${MINIKUBE_HOME:-$HOME/.minikube}"
  mkdir -p "$MHOME/files/etc/kubernetes/audit"
  cp "$ROOT/minikube/audit-policy.yaml" "$MHOME/files/etc/kubernetes/audit/policy.yaml"
  EXTRA+=(
    --extra-config=apiserver.audit-policy-file=/etc/kubernetes/audit/policy.yaml
    --extra-config=apiserver.audit-log-path=/var/log/kubernetes/audit.log
    --extra-config=apiserver.audit-log-maxage=1
  )
fi

if minikube status -p "$PROFIL" >/dev/null 2>&1; then
  say "Profil '$PROFIL' laeuft bereits, wird uebersprungen"
else
  say "Cluster starten (Kubernetes $K8S_VERSION)"
  minikube start -p "$PROFIL" \
    --kubernetes-version="$K8S_VERSION" \
    --cpus=2 --memory=4096 \
    "${EXTRA[@]}"
fi

kubectl config use-context "$PROFIL" >/dev/null

say "Images vorab laden (wichtig bei schlechtem WLAN)"
# Der kaputte Tag existiert absichtlich nicht und wird nicht geladen.
minikube -p "$PROFIL" image pull nginx:1.27-alpine >/dev/null 2>&1 \
  || docker pull nginx:1.27-alpine >/dev/null 2>&1 \
  && minikube -p "$PROFIL" image load nginx:1.27-alpine >/dev/null 2>&1 || true

say "Anwendung und Namensraum anlegen"
kubectl apply -f "$ROOT/manifests/20-checkout.yaml"

say "Dienstkonto und Rechte des Agenten anlegen"
kubectl apply -f "$ROOT/manifests/10-agent-rbac.yaml"

say "Auf gesunden Zustand warten"
kubectl -n demo rollout status deploy/checkout --timeout=180s

"$ROOT/scripts/agent-kubeconfig.sh"

if [ "${SKIP_ARGOCD:-0}" = "1" ]; then
  say "Argo CD uebersprungen (SKIP_ARGOCD=1)"
else
  "$ROOT/scripts/argocd.sh"
fi

say "Fertig. Naechster Schritt: scripts/preflight.sh"
