#!/usr/bin/env bash
# SCHRITT 1 der Vorfuehrung: den Fehler erzeugen.
#
#   ./break.sh              GIT-WEG (Standard).
#                           Committet einen kaputten Image-Tag und pusht.
#                           Argo CD zieht die Aenderung, der Pod faellt aus.
#                           Das ist die ehrliche Geschichte: ein fehlerhafter
#                           Stand wurde gemerged. Der Diff in Schritt 4 passt
#                           dann auch wirklich.
#
#   ./break.sh local        OHNE NETZ. Direktes kubectl set image.
#                           Argo CD zeigt OutOfSync, dreht aber nichts zurueck
#                           (selfHeal ist aus). Notloesung ohne Internet.
#
#   ./break.sh crash|oom|probe   andere Fehlerbilder, jeweils lokal
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS=demo
DATEI="$ROOT/manifests/20-checkout.yaml"
KAPUTT="registry.local/checkout:v2.4.1"
MODE="${1:-git}"

warte_auf_argocd() {
  echo "Argo CD zum sofortigen Abgleich anstossen (statt 3 Minuten Poll) ..."
  kubectl -n argocd annotate app checkout \
    argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
  ZIEL="$(git -C "$ROOT" rev-parse HEAD)"
  for _ in $(seq 1 40); do
    REV="$(kubectl -n argocd get app checkout \
      -o jsonpath='{.status.sync.revision}' 2>/dev/null || true)"
    printf '\r    Argo CD steht auf %s' "$(echo "${REV:-...}" | cut -c1-7)"
    [ "$REV" = "$ZIEL" ] && break
    sleep 3
  done
  echo
}

case "$MODE" in
  git)
    command -v git >/dev/null || { echo "git fehlt"; exit 1; }
    sed -i.bak "s|image: nginx:1.27-alpine|image: ${KAPUTT}|" "$DATEI"
    rm -f "$DATEI.bak"
    grep -q "$KAPUTT" "$DATEI" || { echo "Ersetzung fehlgeschlagen, Datei pruefen"; exit 1; }

    git -C "$ROOT" add "$DATEI"
    git -C "$ROOT" commit -m "feat(checkout): Rollout auf v2.4.1" >/dev/null
    git -C "$ROOT" push
    echo "Committet und gepusht: $(git -C "$ROOT" rev-parse --short HEAD)"
    warte_auf_argocd
    ;;

  local)
    kubectl -n "$NS" set image deploy/checkout checkout="$KAPUTT"
    echo "Direkt gesetzt. Argo CD wird gleich OutOfSync anzeigen."
    ;;

  crash)
    kubectl -n "$NS" set image deploy/checkout checkout=busybox:1.36
    kubectl -n "$NS" patch deploy/checkout --type=json -p='[
      {"op":"add","path":"/spec/template/spec/containers/0/command",
       "value":["/bin/sh","-c","echo starte; sleep 2; exit 1"]},
      {"op":"remove","path":"/spec/template/spec/containers/0/readinessProbe"}
    ]' >/dev/null
    ;;

  oom)
    kubectl -n "$NS" patch deploy/checkout --type=json -p='[
      {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory",
       "value":"8Mi"}
    ]' >/dev/null
    ;;

  probe)
    kubectl -n "$NS" patch deploy/checkout --type=json -p='[
      {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path",
       "value":"/gibt-es-nicht"},
      {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port",
       "value":8080}
    ]' >/dev/null
    ;;

  *)
    echo "Unbekannter Modus: $MODE  (git|local|crash|oom|probe)"; exit 1 ;;
esac

echo
echo "Warte auf sichtbaren Zustand ..."
sleep 6
kubectl -n "$NS" get pods -l app=checkout
echo
kubectl -n argocd get app checkout \
  -o custom-columns=APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status \
  2>/dev/null || true
echo
echo "Jetzt Schritt 2: scripts/ask.sh"
