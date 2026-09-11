# Helm + ArgoCD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Helm-chart (`charts/learncicd`) + ArgoCD Application (`argocd/application.yaml`) opleveren en de app via SSH deployen op de K3s-node (192.168.2.46), met pod `Running` en `/health` OK als bewijs.

**Architecture:** Chart-bestanden exact zoals lokaal bewezen (`helm lint` schoon, `helm template` correcte selectors/probes/resources), daarna Application-manifest (server-dry-run geaccepteerd op het cluster), dan PR-validatie + merge, tot slot SSH-deploy: menselijke prerequisites (ArgoCD-repo-credential + imagePullSecret) eerst, daarna `kubectl apply`, sync-wait en health-check. Cluster-feiten (2026-09-11 bewezen): K3s met werkende ArgoCD + image-updater; repo-credentials per repo (bv. `repo-bgjobs-api`); SSH als `lvdberg` zonder wachtwoord.

**Tech Stack:** Helm v3.16.4 (lokaal aanwezig), ArgoCD Application `argoproj.io/v1alpha1`, K3s/kubectl via SSH naar 192.168.2.46, image `go.berg-connect.nl/beheerder/learncicd:latest`.

## Global Constraints

- Chart-naam exact `learncicd`; `Chart.yaml`: `apiVersion: v2`, `type: application`, `version: 0.1.0` (handmatig bumpen bij chart-wijzigingen staat in spec; deze taak zet de startwaarde).
- Image exact `repository: go.berg-connect.nl/beheerder/learncicd`, `tag: latest`, `pullPolicy: IfNotPresent` (met values-comment dat `Always` hoort bij strict `latest`-volgen).
- `replicaCount: 1`; Service `ClusterIP`, `port: 8080`, `targetPort: http`; containerpoort `8080` met naam `http`.
- Probes exact: liveness HTTP-GET `/health` (`initialDelaySeconds: 20`, `periodSeconds: 20`, `timeoutSeconds: 2`, `failureThreshold: 3`); readiness HTTP-GET `/health` (`initialDelaySeconds: 5`, `periodSeconds: 10`, `timeoutSeconds: 2`, `failureThreshold: 3`); beide aan/uit via `enabled: true`.
- Resources exact: `requests: {cpu: 50m, memory: 64Mi}`, `limits: {cpu: 500m, memory: 256Mi}`.
- `securityContext.runAsNonRoot: true` op pod-niveau; geen privileged flags, geen host-volumes.
- `imagePullSecrets` default exact `[{name: gitea-registry}]` (goedgekeurde afwijking van spec-§1 "default leeg" — zonder naam geen draaiende pod op een privé-registry; de mens maakt dit secret aan).
- Helpers exact `learncicd.labels` + `learncicd.selectorLabels` (`app.kubernetes.io/name: <chart>`, `app.kubernetes.io/instance: <release>`); Deployment-naam, Service-naam en alle selectors gebruiken ze — nooit hardcoded labels.
- Application exact: `name: learncicd`, namespace `argocd`, `project: default`, `repoURL: https://github.com/bergconnect/LearnCICD.git`, `targetRevision: HEAD`, `path: charts/learncicd`, `destination.server: https://kubernetes.default.svc`, `destination.namespace: default`, `syncPolicy.automated: {prune: true, selfHeal: true}`.
- Nooit credentials in repo, logs of output (secret-namen wel — waarden nooit).
- `helm lint` schoon (alleen de bekende `icon is recommended`-info is oké); `yamllint` waar zinvol.
- Werk op feature-branch `feat/helm-argocd`; merge naar `main` uitsluitend via PR met groene checks (branch protection); conventionele commits.
- SSH naar 192.168.2.46 uitsluitend met bestaande sleutel-authenticatie (BatchMode — nooit wachtwoorden, nooit host-key-checks omzeilen); alleen lees- of apply-operaties uit dit plan.

---

## File Structure

| Bestand | Verantwoordelijkheid |
|---|---|
| `charts/learncicd/Chart.yaml` | Chart-metadata (nieuw) |
| `charts/learncicd/values.yaml` | Alle configureerbare waarden (nieuw) |
| `charts/learncicd/templates/_helpers.tpl` | Label-helpers (nieuw) |
| `charts/learncicd/templates/deployment.yaml` | Deployment met probes/resources/security (nieuw) |
| `charts/learncicd/templates/service.yaml` | ClusterIP-service (nieuw) |
| `argocd/application.yaml` | ArgoCD Application (nieuw) |

Bestaande repo-bestanden blijven onaangeraakt (alleen ADD-operaties in git).

---

### Task 1: Chart-metadata, values en helpers

**Files:**
- Create: `charts/learncicd/Chart.yaml`
- Create: `charts/learncicd/values.yaml`
- Create: `charts/learncicd/templates/_helpers.tpl`

**Interfaces:**
- Consumes: niets (nieuwe bestanden).
- Produces: `helm lint` schone basis + values-contract dat Taken 2–4 gebruiken (sleutelnamen exact als hieronder — latere taken lezen deze waarden, verzin geen andere).

- [ ] **Step 1: Create `charts/learncicd/Chart.yaml`**

```yaml
apiVersion: v2
name: learncicd
description: LearnCICD minimal API
type: application
version: 0.1.0
appVersion: "0.1"
```

- [ ] **Step 2: Create `charts/learncicd/values.yaml`**

```yaml
replicaCount: 1
image:
  repository: go.berg-connect.nl/beheerder/learncicd
  tag: latest
  # IfNotPresent haalt eenzelfde tag niet opnieuw op bij digest-wissel;
  # use Always voor strict latest-volgen.
  pullPolicy: IfNotPresent
imagePullSecrets:
  - name: gitea-registry
service:
  type: ClusterIP
  port: 8080
probes:
  liveness:
    enabled: true
    path: /health
    initialDelaySeconds: 20
    periodSeconds: 20
    timeoutSeconds: 2
    failureThreshold: 3
  readiness:
    enabled: true
    path: /health
    initialDelaySeconds: 5
    periodSeconds: 10
    timeoutSeconds: 2
    failureThreshold: 3
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

- [ ] **Step 3: Create `charts/learncicd/templates/_helpers.tpl`**

```tpl
{{- define "learncicd.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "learncicd.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
```

- [ ] **Step 4: Lint and commit**

Run:

```bash
helm lint charts/learncicd
```

Expected: `1 chart(s) linted, 0 chart(s) failed` (alleen de `icon is recommended`-info is oké).

Run:

```bash
git add charts/learncicd/Chart.yaml charts/learncicd/values.yaml charts/learncicd/templates/_helpers.tpl
git commit -m "feat: add Helm chart metadata, values and helpers for learncicd"
```

### Task 2: Deployment + Service templates

**Files:**
- Create: `charts/learncicd/templates/deployment.yaml`
- Create: `charts/learncicd/templates/service.yaml`

**Interfaces:**
- Consumes: values-sleutels + helpers uit Task 1 (exacte namen — bij twijfel Task-1-bestanden lezen, nooit zelf verzinnen).
- Produces: renderende chart; `helm template` toont Deployment (1 replica, probes, resources, runAsNonRoot, pull-secret) + Service (ClusterIP 8080) met matchende selectors. Task 3 verwijst hiernaar vanuit de Application; Task 4 deployt dit.

- [ ] **Step 1: Create `charts/learncicd/templates/deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-learncicd
  labels:
    {{- include "learncicd.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "learncicd.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "learncicd.selectorLabels" . | nindent 8 }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      securityContext:
        runAsNonRoot: true
      containers:
        - name: api
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 8080
          {{- if .Values.probes.liveness.enabled }}
          livenessProbe:
            httpGet:
              path: {{ .Values.probes.liveness.path }}
              port: http
            initialDelaySeconds: {{ .Values.probes.liveness.initialDelaySeconds }}
            periodSeconds: {{ .Values.probes.liveness.periodSeconds }}
            timeoutSeconds: {{ .Values.probes.liveness.timeoutSeconds }}
            failureThreshold: {{ .Values.probes.liveness.failureThreshold }}
          {{- end }}
          {{- if .Values.probes.readiness.enabled }}
          readinessProbe:
            httpGet:
              path: {{ .Values.probes.readiness.path }}
              port: http
            initialDelaySeconds: {{ .Values.probes.readiness.initialDelaySeconds }}
            periodSeconds: {{ .Values.probes.readiness.periodSeconds }}
            timeoutSeconds: {{ .Values.probes.readiness.timeoutSeconds }}
            failureThreshold: {{ .Values.probes.readiness.failureThreshold }}
          {{- end }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

- [ ] **Step 2: Create `charts/learncicd/templates/service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-learncicd
  labels:
    {{- include "learncicd.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    {{- include "learncicd.selectorLabels" . | nindent 4 }}
```

- [ ] **Step 3: Lint, render, verify selectors, commit**

Run:

```bash
helm lint charts/learncicd
helm template test-release charts/learncicd --namespace default > /tmp/opencode/render-check.yaml 2>&1; echo "render-exit=$?"
```

Expected: lint schoon (alleen icon-info); render exit 0.

Run (selectors moeten matchen — alle drie groepen identiek):

```bash
grep -A2 "matchLabels:" /tmp/opencode/render-check.yaml; grep -B1 -A3 "selector:" /tmp/opencode/render-check.yaml | head -20; rm -f /tmp/opencode/render-check.yaml
```

Expected: Deployment `selector.matchLabels`, pod-template `labels` en Service `selector` tonen alle drie `app.kubernetes.io/name: learncicd` + `app.kubernetes.io/instance: test-release`.

Run:

```bash
git add charts/learncicd/templates/deployment.yaml charts/learncicd/templates/service.yaml
git commit -m "feat: add learncicd Deployment and Service templates"
```

### Task 3: ArgoCD Application + PR-validatie + merge

**Files:**
- Create: `argocd/application.yaml`

**Interfaces:**
- Consumes: chart-pad `charts/learncicd` uit Taken 1–2.
- Produces: mergebare PR met groene checks; `main` bevat chart + Application na merge. Task 4 deployt vanaf `main`.

- [ ] **Step 1: Create `argocd/application.yaml`**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: learncicd
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/bergconnect/LearnCICD.git
    targetRevision: HEAD
    path: charts/learncicd
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

- [ ] **Step 2: Push and open a PR `feat/helm-argocd` → `main`**

Run:

```bash
git push -u origin feat/helm-argocd
```

Open daarna de PR (github.com of API). Titel: `feat: add Helm chart and ArgoCD Application for learncicd`. Niet mergen vóór Step 4.

- [ ] **Step 3: Confirm PR checks**

Expected op de PR: `Test (.NET)` ✅, `Version` ✅, `Security scan` ✅ (`Docker build` bestaat niet meer; `Publish image` **skipped** — correct gedrag, geen fout).

- [ ] **Step 4: Merge and sync local state**

Merge de PR via GitHub, daarna lokaal:

```bash
git checkout main
git pull
git fetch --prune origin
git branch -d feat/helm-argocd
git log --oneline -3
```

Expected: `main` bevat de drie chart-commits plus merge; `git status --short` leeg.

### Task 4: Deployen via SSH + bewijzen

**Files:**
- Geen (SSH-/kubectl-operaties; hooguit mensenwerk-voorbereiding)

**Interfaces:**
- Consumes: `argocd/application.yaml` op `main` uit Task 3; SSH-sleuteltoegang tot 192.168.2.46 als `lvdberg` (bestaat — BatchMode, nooit wachtwoorden).
- Produces: draaiende app in namespace `default` (pod `Running`, `/health` OK) als eindbewijs.

- [ ] **Step 1: Human prerequisites (BLOCKED als ontbrekend — eerst dit, dan pas Step 2)**

De mens maakt vooraf aan (buiten git, buiten dit plan om te verifiëren behalve via effect):
1. ArgoCD-repository-credential voor `https://github.com/bergconnect/LearnCICD.git` (HTTPS-user + token met repo-leesrechten; zónder `insecure`-vlag — github.com heeft geldige certificaten), analoog aan bestaande `repo-*`-secrets in namespace `argocd`.
2. ImagePullSecret `gitea-registry` (type `kubernetes.io/dockerconfigjson`, Gitea-credentials) in namespace `default`.

Zonder (1) kan ArgoCD de repo niet lezen (sync-fout); zonder (2) komen pods in `ImagePullBackOff`. Als één van beide ontbreekt: STOP, rapporteer BLOCKED met welke — verzin geen workarounds (zeker geen credentials in bestanden/logs).

- [ ] **Step 2: Apply the Application via SSH**

Run (vanaf de controller-machine; alles BatchMode, geen wachtwoorden):

```bash
git show main:argocd/application.yaml > /tmp/opencode/application.yaml
scp -o BatchMode=yes /tmp/opencode/application.yaml 192.168.2.46:/tmp/learncicd-application.yaml
ssh -o BatchMode=yes 192.168.2.46 'kubectl apply -f /tmp/learncicd-application.yaml && rm -f /tmp/learncicd-application.yaml'
rm -f /tmp/opencode/application.yaml
```

Expected: `application.argoproj.io/learncicd created` (of `unchanged` bij herhaling).

- [ ] **Step 3: Wait for sync and prove health**

Run (poll, maximaal ~5 minuten):

```bash
for i in $(seq 1 30); do S=$(ssh -o BatchMode=yes 192.168.2.46 'kubectl -n argocd get application learncicd -o jsonpath="{.status.sync.status} {.status.health.status} {.status.operationState.phase}" 2>/dev/null'); echo "$i: $S"; echo "$S" | grep -q "Synced Healthy" && break; sleep 10; done
```

Expected: binnen de polling `Synced Healthy` (geen `operationState.phase=Failed/Error`).

Run daarna (selector op chart-naam — release-onafhankelijk):

```bash
ssh -o BatchMode=yes 192.168.2.46 'kubectl -n default get pods -l app.kubernetes.io/name=learncicd -o jsonpath="{.items[*].status.phase}"; echo; POD=$(kubectl -n default get pods -l app.kubernetes.io/name=learncicd -o jsonpath="{.items[0].metadata.name}"); kubectl -n default exec "$POD" -- wget -qO- http://localhost:8080/health; echo'
```

Expected: pod-fase `Running`; `/health`-body bevat `Healthy`. (Als `wget` in de minimale image ontbreekt, fallback via port-forward vanaf de node:)

```bash
ssh -o BatchMode=yes 192.168.2.46 'SVC=$(kubectl -n default get svc -l app.kubernetes.io/name=learncicd -o jsonpath="{.items[0].metadata.name}"); kubectl -n default port-forward svc/"$SVC" 18080:8080 >/tmp/pf.log 2>&1 & echo $! >/tmp/pf.pid; sleep 3; curl -s http://localhost:18080/health; echo; kill $(cat /tmp/pf.pid); rm -f /tmp/pf.pid /tmp/pf.log'
```

Expected: body bevat `Healthy`.

- [ ] **Step 4: Clean up local branch state**

Alleen als Step 3 groen is. Remote branch verwijderen (API of UI), daarna lokaal:

```bash
git fetch --prune origin
git branch -d feat/helm-argocd
git log --oneline -3
```

Expected: `main` op merge-commit; `git status --short` leeg; `git branch -a` toont alleen `main` + `origin/main` (+ PR-refs).
