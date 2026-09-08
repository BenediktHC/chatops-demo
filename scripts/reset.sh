#!/usr/bin/env bash
# Setzt Repository und Cluster auf den gesunden Ausgangszustand zurueck.
# Zwischen den Proben und nach der Vorfuehrung ausfuehren.
#
#   ./reset.sh          Datei zuruecksetzen, committen, pushen, Argo CD abgleichen
#   LOCAL=1 ./reset.sh  nur den Cluster, ohne Git (schnell, ohne Netz)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATEI="$ROOT/manifests/20-checkout.yaml"
GUT="nginx:1.27-alpine"

sed -i.bak "s|image: registry.local/checkout:v2.4.1|image: ${GUT}|" "$DATEI"
rm -f "$DATEI.bak"

if [ "${LOCAL:-0}" = "1" ]; then
  git -C "$ROOT" checkout -- "$DATEI" 2>/dev/null || true
  kubectl apply -f "$DATEI" >/dev/null
else
  if ! git -C "$ROOT" diff --quiet -- "$DATEI"; then
    git -C "$ROOT" add "$DATEI"
    git -C "$ROOT" commit -m "chore: Ausgangszustand fuer die naechste Probe" >/dev/null
    git -C "$ROOT" push
  fi
  kubectl -n argocd annotate app checkout \
    argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
  sleep 5
fi

kubectl -n demo rollout status deploy/checkout --timeout=120s
echo
kubectl -n demo get pods -l app=checkout
kubectl -n argocd get app checkout \
  -o custom-columns=APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status \
  2>/dev/null || true
echo
echo "Zurueckgesetzt."
