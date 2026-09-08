#!/usr/bin/env bash
# Vor dem Vortrag ausfuehren. Prueft alles, was auf der Buehne scheitern kann.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OK=0; FEHLER=0

pruefe() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  \033[32mOK\033[0m    %s\n' "$name"; OK=$((OK+1))
  else
    printf '  \033[31mFEHLT\033[0m %s\n' "$name"; FEHLER=$((FEHLER+1))
  fi
}

echo
echo "Werkzeuge"
pruefe "minikube" command -v minikube
pruefe "kubectl"  command -v kubectl
pruefe "Cluster laeuft"  minikube status -p chatops-demo
pruefe "Agent (holmes)" command -v holmes

echo
echo "Cluster"
pruefe "Cluster erreichbar"   kubectl --context chatops-demo get ns
pruefe "Namensraum demo"      kubectl get ns demo
pruefe "checkout ist gesund"  bash -c \
  '[ "$(kubectl -n demo get deploy checkout -o jsonpath="{.status.readyReplicas}")" = "1" ]'

echo
echo "Rechte des Agenten"
pruefe "agent.kubeconfig vorhanden" test -f "$ROOT/agent.kubeconfig"
export KUBECONFIG="$ROOT/agent.kubeconfig"
pruefe "darf Pods lesen"          kubectl auth can-i get pods -n demo
pruefe "darf Logs lesen"          kubectl auth can-i get pods/log -n demo
pruefe "darf NICHT patchen"  bash -c \
  '! kubectl auth can-i patch deployments -n demo --quiet'
pruefe "darf KEIN exec"      bash -c \
  '! kubectl auth can-i create pods/exec -n demo --quiet'
pruefe "darf KEINE secrets"  bash -c \
  '! kubectl auth can-i get secrets -n demo --quiet'
unset KUBECONFIG

echo
echo "Git und Argo CD"
pruefe "Git-Remote gesetzt"  git -C "$ROOT" remote get-url origin
pruefe "Arbeitsbaum sauber"  test -z "$(git -C "$ROOT" status --porcelain)"
pruefe "Push moeglich"       git -C "$ROOT" push --dry-run
pruefe "Argo CD laeuft"      kubectl -n argocd get deploy argocd-server
pruefe "Anwendung Synced"    bash -c \
  '[ "$(kubectl -n argocd get app checkout -o jsonpath="{.status.sync.status}")" = "Synced" ]'
pruefe "Anwendung Healthy"   bash -c \
  '[ "$(kubectl -n argocd get app checkout -o jsonpath="{.status.health.status}")" = "Healthy" ]'
pruefe "selfHeal ist AUS"    bash -c \
  '[ "$(kubectl -n argocd get app checkout -o jsonpath="{.spec.syncPolicy.automated.selfHeal}")" != "true" ]'
pruefe "UI erreichbar"       bash -c \
  'IP=$(minikube ip -p chatops-demo 2>/dev/null); \
   curl -sf -o /dev/null --max-time 4 "http://$IP:30080" || \
   curl -sf -o /dev/null --max-time 4 "http://localhost:30080"'

echo
echo "Modellzugang"
if [ -n "${OPENAI_API_KEY:-}${ANTHROPIC_API_KEY:-}${GEMINI_API_KEY:-}" ]; then
  printf '  \033[32mOK\033[0m    API-Schluessel gesetzt\n'; OK=$((OK+1))
else
  printf '  \033[31mFEHLT\033[0m Kein API-Schluessel in der Umgebung\n'; FEHLER=$((FEHLER+1))
fi

echo
echo "Probelauf des Agenten (kostet einen echten Aufruf)"
if [ "${SKIP_AGENT:-0}" != "1" ]; then
  if timeout 90 "$ROOT/scripts/ask.sh" "wie viele Pods laufen im Namensraum demo?" \
      >/tmp/preflight-agent.log 2>&1; then
    printf '  \033[32mOK\033[0m    Agent antwortet (Ausgabe: /tmp/preflight-agent.log)\n'
    OK=$((OK+1))
  else
    printf '  \033[31mFEHLT\033[0m Agent antwortet nicht, siehe /tmp/preflight-agent.log\n'
    FEHLER=$((FEHLER+1))
  fi
else
  echo "  uebersprungen (SKIP_AGENT=1)"
fi

echo
echo "-----------------------------------------"
printf '  %d in Ordnung, %d Probleme\n' "$OK" "$FEHLER"
[ "$FEHLER" -eq 0 ] && echo "  Bereit." || echo "  Vor dem Vortrag beheben."
echo
exit $(( FEHLER > 0 ? 1 : 0 ))
