#!/usr/bin/env bash
# Installiert Argo CD im Cluster und registriert die Anwendung.
# Laufzeit ca. 2 bis 3 Minuten, ueberwiegend Image-Pulls.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="https://github.com/BenediktHC/chatops-demo.git"

say() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }

say "Argo CD installieren"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml >/dev/null

say "Auf HTTP umstellen (sonst meckert der Browser auf der Buehne)"
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"server.insecure":"true"}}' >/dev/null

say "UI auf NodePort 30080 legen"
kubectl -n argocd patch svc argocd-server --type merge -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {"name":"http","port":80,"targetPort":8080,"nodePort":30080,"protocol":"TCP"},
      {"name":"https","port":443,"targetPort":8080,"protocol":"TCP"}
    ]
  }
}' >/dev/null

kubectl -n argocd rollout restart deploy/argocd-server >/dev/null
say "Warten, bis Argo CD bereit ist"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s

say "Anwendung registrieren"
kubectl apply -f "$ROOT/gitops/application.yaml" >/dev/null

say "Auf ersten Abgleich warten"
for _ in $(seq 1 60); do
  SYNC="$(kubectl -n argocd get app checkout -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  HEALTH="$(kubectl -n argocd get app checkout -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  printf '\r    Sync=%-10s Health=%-12s' "${SYNC:-…}" "${HEALTH:-…}"
  [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ] && break
  sleep 3
done
echo

cat <<EOF

  Argo CD steht. Anwendung ist registriert.

    Repository  ${REPO}
    Oberflaeche ./scripts/ui.sh   (ermittelt die passende URL fuer deinen
                                   minikube-Treiber und startet notfalls
                                   einen Tunnel)

  Hinweis: selfHeal ist bewusst ausgeschaltet. Sonst wuerde Argo CD den
  Fehler aus "break.sh local" sofort zurueckdrehen.

EOF
