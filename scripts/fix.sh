#!/usr/bin/env bash
# SCHRITT 4 und 5: Freigabe durch einen Menschen, Anwendung ueber Git.
#
# Zeigt den Diff, wartet auf Bestaetigung, committet, pusht und laesst Argo CD
# synchronisieren. Der Agent hat an keiner Stelle Schreibrechte am Cluster.
#
#   ./fix.sh              ueber Git und Argo CD (Standard)
#   NO_ARGOCD=1 ./fix.sh  ohne Argo CD, direktes kubectl apply (Notfall)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATEI="$ROOT/manifests/20-checkout.yaml"
GUT="nginx:1.27-alpine"

blau() { printf '\n\033[36m%s\033[0m\n' "$1"; }

sed -i.bak "s|image: registry.local/checkout:v2.4.1|image: ${GUT}|" "$DATEI"
rm -f "$DATEI.bak"

if git -C "$ROOT" diff --quiet -- "$DATEI"; then
  echo "Keine Aenderung noetig, die Datei steht bereits auf ${GUT}."
  exit 0
fi

blau "Vorschlag des Agenten, als Diff:"
git -C "$ROOT" --no-pager diff --color -- "$DATEI"

echo
read -r -p "Freigeben? [j/N] " ANTWORT
[ "$ANTWORT" = "j" ] || { echo "Abgebrochen."; git -C "$ROOT" checkout -- "$DATEI"; exit 0; }

git -C "$ROOT" add "$DATEI"
git -C "$ROOT" commit -m "fix(checkout): Rollback auf ${GUT}, Tag v2.4.1 existiert nicht" >/dev/null
ZIEL="$(git -C "$ROOT" rev-parse HEAD)"
echo "Committet: $(git -C "$ROOT" rev-parse --short HEAD)"

if [ "${NO_ARGOCD:-0}" = "1" ]; then
  blau "Ohne Argo CD: direkt anwenden"
  kubectl apply -f "$DATEI" >/dev/null
else
  git -C "$ROOT" push
  blau "Gepusht. Argo CD synchronisiert."
  kubectl -n argocd annotate app checkout \
    argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true

  for _ in $(seq 1 60); do
    REV="$(kubectl -n argocd get app checkout -o jsonpath='{.status.sync.revision}' 2>/dev/null || true)"
    SYNC="$(kubectl -n argocd get app checkout -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    HEALTH="$(kubectl -n argocd get app checkout -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
    printf '\r    %s  Sync=%-10s Health=%-12s' "$(echo "${REV:-...}" | cut -c1-7)" "${SYNC:-…}" "${HEALTH:-…}"
    [ "$REV" = "$ZIEL" ] && [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ] && break
    sleep 3
  done
  echo
fi

kubectl -n demo rollout status deploy/checkout --timeout=120s
echo
kubectl -n demo get pods -l app=checkout
kubectl -n argocd get app checkout \
  -o custom-columns=APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status \
  2>/dev/null || true
