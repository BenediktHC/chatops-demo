# Vorführung: KI-gestützter Kubernetes-Betrieb

Begleitmaterial zum Vortrag, ab Folie 16. Fünf Schritte an einem defekten
Deployment, auf einem Wegwerf-Cluster.

Der Kern der Vorführung ist nicht, dass der Agent die Ursache findet. Das kann
jeder vorführen. Der Kern ist **Schritt 3**: der Agent will die Änderung anwenden
und wird vom API-Server abgelehnt, weil `manifests/10-agent-rbac.yaml` das Recht
nicht enthält.

---

## Voraussetzungen

| Werkzeug | Zweck | Installation |
|---|---|---|
| Docker | Unterbau für minikube | Docker Desktop oder Engine, alternativ hyperkit/kvm2 |
| minikube | Cluster | `brew install minikube` |
| kubectl | alles | `brew install kubectl` |
| HolmesGPT | der Agent | `brew tap robusta-dev/homebrew-holmesgpt && brew install holmesgpt` |
| API-Schlüssel | Modellzugang | `export ANTHROPIC_API_KEY=…` oder `OPENAI_API_KEY` |

Alternativen zum Agenten: `kubectl-ai` oder `k8sgpt`, beide werden von
`scripts/ask.sh` über die Variable `AGENT` unterstützt.

Ohne verlässliches Netz am Veranstaltungsort: ein lokales Modell über Ollama
verwenden. HolmesGPT und kubectl-ai unterstützen das. Das vorher testen, die
Antwortqualität ist bei kleinen Modellen deutlich schlechter.

---

## Einrichtung

Einmalig, mit dem Repository verbinden. Argo CD liest von GitHub, deshalb muss
der Remote stehen, bevor `setup.sh` läuft.

```bash
git init
git remote add origin https://github.com/BenediktHC/chatops-demo.git
git add -A && git commit -m "Ausgangszustand"
git push -u origin main

./scripts/setup.sh          # Cluster, Anwendung, Rechte, kubeconfig, Argo CD
./scripts/preflight.sh      # prüft alles, was auf der Bühne scheitern kann
```

`setup.sh` läuft fünf bis acht Minuten, davon der größere Teil auf Argo CD.
Der Cluster ist ein eigenes minikube-Profil `chatops-demo` und rührt bestehende
Profile nicht an.

Ohne Argo CD: `SKIP_ARGOCD=1 ./scripts/setup.sh`, dann `NO_ARGOCD=1` bei `fix.sh`.
Mit Audit-Log im API-Server: `AUDIT=1 ./scripts/setup.sh`, danach zeigt
`make audit` die Aufrufe des Agenten.

Danach:

| | |
|---|---|
| Cluster | minikube-Profil `chatops-demo` |
| Namensraum | `demo`, Deployment `checkout` gesund |
| Argo CD UI | `./scripts/ui.sh` gibt URL und Passwort aus |
| Agentenrechte | `agent.kubeconfig` |

**`agent.kubeconfig` ist der wichtigste Teil der Einrichtung.** Sie enthält ein
Token des Dienstkontos `agent` und sonst nichts. Der Agent läuft ausschließlich
damit. Ohne diesen Schritt würde er die Adminrechte deiner eigenen kubeconfig
erben, und Schritt 3 wäre gestellt statt echt.

Das Token läuft nach acht Stunden ab. Am Vortragstag neu erzeugen:

```bash
./scripts/agent-kubeconfig.sh
```

### Die Argo-CD-Oberfläche

```bash
./scripts/ui.sh
```

Bei minikube hängt der Zugang vom Treiber ab. Unter Linux mit Treiber `docker`
und bei den VM-Treibern ist der NodePort direkt über `minikube ip` erreichbar.
Unter macOS und Windows mit Treiber `docker` nicht — dort startet das Skript
automatisch einen `port-forward`.

**Prüfe das vor dem Vortrag.** Wenn ein Tunnel nötig ist, braucht er ein eigenes
Terminalfenster, das während der ganzen Vorführung offen bleibt.

### Drei Dinge, die man leicht falsch macht

**`selfHeal` muss ausgeschaltet bleiben.** Steht es auf `true`, dreht Argo CD
einen lokal erzeugten Fehler innerhalb von Sekunden zurück und die Vorführung
ist tot. `preflight.sh` prüft das.

**Argo CD synchronisiert nur `20-checkout.yaml`, nicht die RBAC-Datei.** Das ist
Absicht: der Agent kann seine eigenen Rechte auch über den Git-Weg nicht
erweitern. Guter Satz für die Fragerunde.

---

## Ablauf auf der Bühne

Zwei Terminalfenster nebeneinander: links die Befehle, rechts ein laufendes
`watch kubectl -n demo get pods`. Schriftgröße vorher auf Projektorabstand
prüfen, mindestens 18 pt.

### Schritt 1 — Fehler erzeugen

```bash
./scripts/break.sh
```

Committet den Image-Tag `registry.local/checkout:v2.4.1` nach GitHub, pusht und
stößt Argo CD an. Argo CD zieht den Stand, der Pod geht auf `ImagePullBackOff`.

Das ist die ehrliche Geschichte: **ein fehlerhafter Stand wurde gemerged.** Nur
so passt auch der Diff in Schritt 4, denn dort wird genau dieser Commit wieder
zurückgenommen.

Wenn du das Argo-CD-Fenster daneben offen hast, sieht das Publikum den Ablauf
selbst: neuer Commit, Sync, Degraded.

Ohne Netz: `./scripts/break.sh local` setzt das Image direkt. Argo CD zeigt dann
OutOfSync, dreht aber nichts zurück. In dem Fall `NO_ARGOCD=1 ./scripts/fix.sh`
verwenden.

Andere Fehlerbilder: `break.sh crash`, `break.sh oom`, `break.sh probe`.

### Schritt 2 — Frage stellen

```bash
./scripts/ask.sh
```

Die Werkzeugaufrufe laufen sichtbar durch. Sie beim Durchlaufen mitlesen und mit
dem Mitschnitt auf Folie 7 vergleichen: `pods_list`, `pod_describe`,
`events_list`, `pods_log`. Ausdrücklich sagen, dass jeder dieser Aufrufe lesend
ist.

Die Formulierung der Antwort ändert sich zwischen Durchläufen. Kündige die
Struktur an, nicht den Wortlaut.

### Schritt 3 — Grenze erreichen

Vorher kurz auf Folie 13 zurückspringen und die ClusterRole zeigen. Dann:

```bash
./scripts/wall.sh
```

Das Skript zeigt erst mit `kubectl auth can-i`, was das Dienstkonto darf, und
versucht dann genau die Korrektur, die der Agent vorschlägt. Die Ablehnung kommt
vom API-Server:

```
Error from server (Forbidden): deployments.apps "checkout" is forbidden:
User "system:serviceaccount:demo:agent" cannot patch resource "deployments"
```

Wenn du zeigen willst, dass nichts gestellt ist: derselbe Befehl ohne
`KUBECONFIG=agent.kubeconfig` funktioniert.

### Schritt 4 und 5 — Freigabe und Anwendung

```bash
./scripts/fix.sh
```

Nimmt den Image-Tag zurück, zeigt den Diff in Farbe, wartet auf deine
Bestätigung, committet, pusht und wartet, bis Argo CD wieder auf `Synced` und
`Healthy` steht.

Der Diff ist drei Zeilen lang. Genau das ist der Punkt: die verbleibende
menschliche Aufgabe ist eine Beurteilung, keine Diagnose.

Für Schritt 5 das Argo-CD-Fenster zeigen. Der Ablauf ist dort vollständig
sichtbar: neuer Commit, Sync, Progressing, Healthy. Kein Mensch und kein Agent
hat dabei `kubectl` gegen den Cluster ausgeführt.

### Zurücksetzen

```bash
./scripts/reset.sh            # zwischen den Proben, inklusive Git
LOCAL=1 ./scripts/reset.sh    # nur Cluster, ohne Push
minikube stop -p chatops-demo              # Pause, Zustand bleibt
minikube delete -p chatops-demo            # nach dem Vortrag
```

---

## Was schiefgehen kann

| Problem | Anzeichen | Gegenmaßnahme |
|---|---|---|
| Modell antwortet nicht | `ask.sh` hängt | Nach 30 Sekunden abbrechen und die Aufzeichnung zeigen. Nicht wartend dastehen. |
| Ratenbegrenzung | HTTP 429 | Zweiten API-Schlüssel bereithalten, vorher in der Umgebung testen |
| Token abgelaufen | `Unauthorized` | `./scripts/agent-kubeconfig.sh` |
| minikube startet nicht | Treiber nicht bereit | Docker Desktop vor dem Vortrag starten, nicht erst am Rednerpult |
| Zu wenig Speicher | Pods bleiben `Pending` | Docker Desktop mindestens 6 GB zuweisen, Argo CD braucht Luft |
| Image-Pull dauert ewig | Pod bleibt `Pending` | `setup.sh` lädt `nginx:1.27-alpine` vorab in das minikube-Profil |
| Agent gibt zu wenig aus | dünne Antwort | Frage konkreter stellen: `./scripts/ask.sh "welcher Pod im Namensraum demo ist nicht bereit und warum?"` |
| `wall.sh` schlägt nicht fehl | Ablehnung bleibt aus | Die ClusterRole ist zu weit gefasst. `manifests/10-agent-rbac.yaml` prüfen, `kubectl apply` erneut. |
| Fehler verschwindet von selbst | Pod wird gesund, ohne dass du etwas tust | `selfHeal` steht auf `true`. In `gitops/application.yaml` auf `false` setzen und neu anwenden. |
| Argo CD zieht den Commit nicht | Revision bleibt alt | `kubectl -n argocd annotate app checkout argocd.argoproj.io/refresh=hard --overwrite` |
| Push scheitert | `fix.sh` bricht ab | Zugangsdaten für GitHub vorher testen: `git push --dry-run` |
| Argo CD UI nicht erreichbar | Seite lädt nicht | `./scripts/ui.sh` erneut starten. Unter macOS mit Treiber `docker` ist der Tunnel zwingend. |
| Tunnel bricht ab | UI plötzlich tot | `ui.sh` im eigenen Fenster laufen lassen, nicht im Hintergrund |

**Nimm die ganze Vorführung vorher auf.** Ein Live-Modellaufruf über
Konferenz-WLAN ist das größte Einzelrisiko des Vortrags. `asciinema rec` reicht.

---

## Proben

Mindestens zweimal komplett durchlaufen, davon einmal am Tag des Vortrags:

```bash
make probe    # reset, break, ask, wall  —  danach fix.sh von Hand
```

Beim zweiten Durchlauf mitstoppen. Realistisch sind 8 bis 12 Minuten für alle
fünf Schritte, wenn du zwischendurch erklärst. Für 15 Minuten Vorführung ist das
genug Puffer.

---

## Aufbau des Repos

```
minikube/audit-policy.yaml   optionale Audit-Regeln, nur bei AUDIT=1
manifests/10-agent-rbac.yaml Dienstkonto und Rechte  <- entspricht Folie 13
manifests/20-checkout.yaml   die Anwendung           <- der Schreibweg in Schritt 4
gitops/application.yaml      Argo-CD-Anwendung, selfHeal bewusst aus
scripts/setup.sh             Cluster aufbauen, ruft argocd.sh mit auf
scripts/argocd.sh            Argo CD installieren und Anwendung registrieren
scripts/agent-kubeconfig.sh  eingeschränkte kubeconfig erzeugen
scripts/ui.sh                Zugang zur Argo-CD-Oberfläche
scripts/preflight.sh         Prüfung vor dem Vortrag
scripts/break.sh             Schritt 1
scripts/ask.sh               Schritt 2
scripts/wall.sh              Schritt 3
scripts/fix.sh               Schritt 4 und 5, ueber Git und Argo CD
scripts/reset.sh             zurücksetzen
```

Das Repo eignet sich als Link auf der Schlussfolie: es enthält die ClusterRole,
die während des Vortrags gezeigt wird.
