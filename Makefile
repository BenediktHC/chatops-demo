.PHONY: setup argocd ui preflight break ask wall fix reset probe stop destroy audit
setup:     ; ./scripts/setup.sh
argocd:    ; ./scripts/argocd.sh
ui:        ; ./scripts/ui.sh
preflight: ; ./scripts/preflight.sh
break:     ; ./scripts/break.sh
ask:       ; ./scripts/ask.sh
wall:      ; ./scripts/wall.sh
fix:       ; ./scripts/fix.sh
reset:     ; ./scripts/reset.sh
probe:     ; ./scripts/reset.sh && ./scripts/break.sh && ./scripts/ask.sh && ./scripts/wall.sh
stop:      ; minikube stop -p chatops-demo
destroy:   ; minikube delete -p chatops-demo
audit:     ; minikube -p chatops-demo ssh -- "sudo grep serviceaccount:demo:agent /var/log/kubernetes/audit.log | tail -5"
