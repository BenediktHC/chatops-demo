#!/usr/bin/env bash
# SCHRITT 2 der Vorfuehrung: den Agenten fragen.
#
# Laeuft ausschliesslich mit der eingeschraenkten kubeconfig. Alles, was hier
# passiert, sind lesende API-Aufrufe mit den Rechten aus 10-agent-rbac.yaml.
#
#   AGENT=holmes ./ask.sh                 (Standard)
#   AGENT=kubectl-ai ./ask.sh
#   AGENT=k8sgpt ./ask.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG="$ROOT/agent.kubeconfig"

AGENT="${AGENT:-holmes}"
FRAGE="${*:-warum startet der Pod checkout im Namensraum demo nicht?}"

[ -f "$KUBECONFIG" ] || { echo "agent.kubeconfig fehlt, erst scripts/setup.sh"; exit 1; }

echo "Agent: $AGENT   |   Rechte: agent-readonly   |   Frage: $FRAGE"
echo

case "$AGENT" in
  holmes)
    holmes ask "$FRAGE"
    ;;
  kubectl-ai)
    kubectl-ai "$FRAGE"
    ;;
  k8sgpt)
    k8sgpt analyze --explain --namespace demo
    ;;
  *)
    echo "Unbekannter Agent: $AGENT"; exit 1 ;;
esac
