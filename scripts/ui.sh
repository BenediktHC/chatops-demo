#!/usr/bin/env bash
# Oeffnet den Zugang zur Argo-CD-Oberflaeche.
#
# Bei minikube haengt das vom Treiber ab:
#   - Treiber docker unter Linux      -> NodePort ueber die minikube-IP erreichbar
#   - Treiber docker unter macOS/Win  -> NICHT erreichbar, es braucht einen Tunnel
#   - Treiber hyperkit, kvm2, hyperv  -> ueber die minikube-IP erreichbar
#
# Dieses Skript probiert erst den direkten Weg und faellt sonst auf
# port-forward zurueck. Das Fenster dann waehrend des Vortrags offen lassen.
set -euo pipefail

PROFIL="chatops-demo"
PORT=30080

pw() {
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo '(bereits geaendert)'
}

IP="$(minikube ip -p "$PROFIL" 2>/dev/null || true)"

if [ -n "$IP" ] && curl -sf -o /dev/null --max-time 4 "http://${IP}:${PORT}"; then
  cat <<EOF

  Argo CD erreichbar:

    URL         http://${IP}:${PORT}
    Benutzer    admin
    Passwort    $(pw)

  Dieses Fenster kann geschlossen werden.

EOF
  exit 0
fi

cat <<EOF

  Direkter Zugriff ueber die minikube-IP nicht moeglich
  (typisch fuer den Treiber docker unter macOS und Windows).
  Tunnel wird gestartet:

    URL         http://localhost:${PORT}
    Benutzer    admin
    Passwort    $(pw)

  Dieses Fenster waehrend des Vortrags offen lassen. Beenden mit Strg-C.

EOF

exec kubectl -n argocd port-forward svc/argocd-server "${PORT}:80" --address 127.0.0.1
