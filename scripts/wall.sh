#!/usr/bin/env bash
# SCHRITT 3 der Vorfuehrung: die Berechtigungsgrenze.
#
# Zeigt zuerst, was das Dienstkonto darf, und versucht dann genau die Aenderung,
# die der Agent vorschlaegt. Die Ablehnung kommt vom API-Server, nicht von einem
# Skript. Kein Schauspiel: derselbe Aufruf mit der Admin-kubeconfig funktioniert.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_KC="$ROOT/agent.kubeconfig"

blau() { printf '\n\033[36m%s\033[0m\n' "$1"; }

blau "1) Was darf das Dienstkonto ueberhaupt?"
KUBECONFIG="$AGENT_KC" kubectl auth can-i get    deployments -n demo
KUBECONFIG="$AGENT_KC" kubectl auth can-i patch  deployments -n demo
KUBECONFIG="$AGENT_KC" kubectl auth can-i create pods/exec   -n demo
KUBECONFIG="$AGENT_KC" kubectl auth can-i get    secrets     -n demo

blau "2) Der Agent versucht die Korrektur anzuwenden:"
echo '   kubectl set image deploy/checkout checkout=nginx:1.27-alpine'
echo
set +e
KUBECONFIG="$AGENT_KC" kubectl -n demo set image deploy/checkout \
  checkout=nginx:1.27-alpine
RC=$?
set -e

echo
if [ $RC -ne 0 ]; then
  blau "Abgelehnt. Genau so soll es sein."
  echo "Die Ablehnung stammt aus manifests/10-agent-rbac.yaml, nicht aus diesem Skript."
else
  echo "WARNUNG: Der Aufruf war erfolgreich. Die ClusterRole ist zu weit gefasst."
  exit 1
fi

echo
echo "Jetzt Schritt 4: die Aenderung als Diff durch einen Menschen freigeben."
