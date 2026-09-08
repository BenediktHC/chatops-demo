#!/usr/bin/env bash
# Erzeugt eine kubeconfig, die ausschliesslich das eingeschraenkte Dienstkonto
# verwendet. Der Agent laeuft NUR damit. Ohne diesen Schritt wuerde er die
# Adminrechte der eigenen kubeconfig erben und Schritt 3 waere gestellt.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KONTEXT="chatops-demo"   # bei minikube = Profilname
OUT="$ROOT/agent.kubeconfig"
DURATION="${TOKEN_DURATION:-8h}"

SERVER="$(kubectl config view --minify --context "$KONTEXT" \
  -o jsonpath='{.clusters[0].cluster.server}')"
CA="$(kubectl config view --raw --minify --context "$KONTEXT" \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
TOKEN="$(kubectl -n demo create token agent --duration="$DURATION")"

cat > "$OUT" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: demo
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA}
contexts:
  - name: agent
    context:
      cluster: demo
      user: agent
      namespace: demo
current-context: agent
users:
  - name: agent
    user:
      token: ${TOKEN}
EOF

chmod 600 "$OUT"
echo "kubeconfig des Agenten: $OUT  (Token gueltig ${DURATION})"
echo
echo "Gegenprobe der Rechte:"
KUBECONFIG="$OUT" kubectl auth can-i --list -n demo 2>/dev/null \
  | grep -E 'pods|deployments|events' || true
