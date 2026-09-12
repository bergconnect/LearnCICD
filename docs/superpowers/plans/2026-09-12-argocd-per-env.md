# ArgoCD per Omgeving Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drie ArgoCD-Applications (devtest/acceptatie/productie) met eigen namespace, poort en values-file, plus cluster-brede pull-secret; oude `default`-deploy opruimen.

**Architecture:** Nieuwe Application-manifesten + verwijderd oud manifest in git (PR-flow), SealedSecret opnieuw versleuteld zónder namespace-binding, daarna SSH-deploy: 3 apps applyen, health per omgeving bewijzen, pas dan oude app met cascade deleten. Cluster-feiten (eerder bewezen): K3s + ArgoCD + sealed-secrets-controller gezond; `kubectl apply --dry-run=server` accepteert Application-manifesten; SSH-sleuteltoegang als `lvdberg` zonder wachtwoord.

**Tech Stack:** ArgoCD Application `argoproj.io/v1alpha1` + `CreateNamespace=true`, kubeseal (`--scope cluster-wide`), SealedSecret-annotatie `sealedsecrets.bitnami.com/cluster-wide: "true"`, kubectl via SSH naar 192.168.2.46.

## Global Constraints

- Drie nieuwe bestanden `argocd/applications/learncicd-{devtest,acceptatie,productie}.yaml`, exacte inhoud hieronder (alleen `<env>` en poort-file verschillen); `argocd/application.yaml` wordt verwijderd (`git rm`).
- Per app exact: `name: learncicd-<env>`, `namespace: argocd`, `project: default`, `repoURL: https://github.com/bergconnect/LearnCICD.git`, `targetRevision: HEAD`, `path: charts/learncicd`, `helm.valueFiles` exact `[$values/charts/learncicd/values.yaml, $values/charts/learncicd/values-<env>.yaml]`, `destination.server: https://kubernetes.default.svc`, `destination.namespace: <env>`, `syncPolicy.automated: {prune: true, selfHeal: true}`, `syncOptions: [CreateNamespace=true]`.
- SealedSecret-wijziging exact: annotatie `sealedsecrets.bitnami.com/cluster-wide: "true"` in `metadata`; géén `namespace`-velden (noch in `metadata`, noch in `template.metadata` — ArgoCD vult doel-namespace in); verse blob via kubeseal `--scope cluster-wide` (exacte procedure hieronder); `template.type: kubernetes.io/dockerconfigjson` + `template.metadata.name: gitea-registry` blijven.
- Nooit credentials in repo, logs of output (alleen de opaque blob wordt gecommit; token alleen via stdin-pipe, nergens opgeslagen; temp-bestanden altijd opruimen).
- `yamllint` waar zinvol (geen regels >80 behalve de versleutelde blob-regel met bestaande disable-comment).
- Werk op feature-branch `feat/argocd-per-env`; merge naar `main` uitsluitend via PR met groene checks (branch protection); conventionele commits.
- SSH naar 192.168.2.46 uitsluitend met bestaande sleutel-authenticatie (BatchMode — nooit wachtwoorden, nooit host-key-checks omzeilen).

---

## File Structure

| Bestand | Verantwoordelijkheid |
|---|---|
| `argocd/applications/learncicd-devtest.yaml` | Application devtest (nieuw) |
| `argocd/applications/learncicd-acceptatie.yaml` | Application acceptatie (nieuw) |
| `argocd/applications/learncicd-productie.yaml` | Application productie (nieuw) |
| `argocd/application.yaml` | Oude single-env app (verwijderen) |
| `charts/learncicd/templates/pullsecret.yaml` | SealedSecret cluster-breed maken (annotatie + ns weg + nieuwe blob) |

Bestaande chart, values en workflow-bestanden blijven onaangeraakt.

---

### Task 1: Drie Applications + oude app-bestand weg

**Files:**
- Create: `argocd/applications/learncicd-devtest.yaml`
- Create: `argocd/applications/learncicd-acceptatie.yaml`
- Create: `argocd/applications/learncicd-productie.yaml`
- Delete: `argocd/application.yaml` (via `git rm`)

**Interfaces:**
- Consumes: overlay-values uit subproject 1 (bestaan op `main`).
- Produces: drie merge-klare manifesten. Task 3 valideert op GitHub; Task 4 deployt vanaf `main`.

- [ ] **Step 1: Create `argocd/applications/learncicd-devtest.yaml`**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: learncicd-devtest
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/bergconnect/LearnCICD.git
    targetRevision: HEAD
    path: charts/learncicd
    helm:
      valueFiles:
        - $values/charts/learncicd/values.yaml
        - $values/charts/learncicd/values-devtest.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: devtest
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

- [ ] **Step 2: Create `argocd/applications/learncicd-acceptatie.yaml`**

Identiek aan Step 1 met exact drie vervangingen: `learncicd-devtest` → `learncicd-acceptatie` (1×, metadata.name), `values-devtest.yaml` → `values-acceptatie.yaml` (1×), `namespace: devtest` → `namespace: acceptatie` (1×, destination).

- [ ] **Step 3: Create `argocd/applications/learncicd-productie.yaml`**

Identiek aan Step 1 met exact drie vervangingen: `learncicd-devtest` → `learncicd-productie`, `values-devtest.yaml` → `values-productie.yaml`, `namespace: devtest` → `namespace: productie`.

- [ ] **Step 4: Delete the old Application file and validate**

Run:

```bash
git rm argocd/application.yaml
for ENV in devtest acceptatie productie; do echo "--- $ENV ---"; python3 -c "import yaml; d=yaml.safe_load(open('argocd/applications/learncicd-$ENV.yaml')); print(d['metadata']['name'], '|', d['spec']['destination']['namespace'], '|', d['spec']['source']['helm']['valueFiles'])"; done
```

Expected per env: `learncicd-<env> | <env> | ['$values/charts/learncicd/values.yaml', '$values/charts/learncicd/values-<env>.yaml']`. (Valt `python3 -c` met PyYAML weg wegens ontbrekende module: gebruik `grep -E "name:|namespace:|valueFiles" -A3` als fallback en vergelijk visueel.)

- [ ] **Step 5: Server-side dry-run via SSH (CRD-validatie zonder iets aan te maken)**

Run (vanaf controller-machine; hele directory in één keer overzetten is niet nodig — bestanden één voor één):

```bash
for ENV in devtest acceptatie productie; do scp -o BatchMode=yes argocd/applications/learncicd-$ENV.yaml 192.168.2.46:/tmp/app-$ENV.yaml; done
ssh -o BatchMode=yes 192.168.2.46 'for ENV in devtest acceptatie productie; do kubectl apply --dry-run=server -f /tmp/app-$ENV.yaml; done; rm -f /tmp/app-devtest.yaml /tmp/app-acceptatie.yaml /tmp/app-productie.yaml'
```

Expected: driemaal `application.argoproj.io/learncicd-<env> created (server dry run)`.

- [ ] **Step 6: Helm lint + per-env render**

Run:

```bash
helm lint charts/learncicd 2>&1 | tail -1
for ENV in devtest acceptatie productie; do echo "--- $ENV ---"; helm template learncicd-$ENV charts/learncicd -f charts/learncicd/values.yaml -f charts/learncicd/values-$ENV.yaml --namespace $ENV --show-only templates/service.yaml | grep -E "^\s+- port:"; helm template learncicd-$ENV charts/learncicd -f charts/learncicd/values.yaml -f charts/learncicd/values-$ENV.yaml --namespace $ENV --show-only templates/deployment.yaml | grep -E "name: learncicd-$ENV" | head -1; done
```

Expected: lint `0 chart(s) failed` (alleen icon-info oké); per env eerst `- port: 8080`/`8081`/`8082` in volgorde, daarna een regel met `name: learncicd-<env>`.

- [ ] **Step 7: Commit**

Run:

```bash
git add argocd/applications/ argocd/application.yaml
git commit -m "feat: add per-environment ArgoCD Applications, remove single-env app"
```

### Task 2: Cluster-brede SealedSecret (met eenmalige mens-input)

**Files:**
- Modify: `charts/learncicd/templates/pullsecret.yaml` (annotatie + namespaces weg + nieuwe blob)

**Interfaces:**
- Consumes: Task 1 (zelfde branch); eenmalige Gitea-leestoken van de mens (alleen via stdin-pipe gebruiken — nergens opslaan, loggen of tonen).
- Produces: SealedSecret die in elke namespace ontsleutelt. Task 4 bewijst adoptie per omgeving.

- [ ] **Step 1: Request the one-time token and STOP if absent (wachtpunt)**

Vraag de mens om een eenmalige Gitea-token (alleen `read:package` nodig). Zonder werkende token: STOP, rapporteer BLOCKED met wat geprobeerd is — verzin geen workarounds (zeker geen credentials in bestanden/logs/output).

- [ ] **Step 2: Re-encrypt cluster-wide on the node (token alleen via stdin)**

Run (vanaf controller-machine; `<TOKEN>` is de geplakte waarde, nooit in een bestand):

```bash
printf '%s' "<TOKEN>" | ssh -o BatchMode=yes 192.168.2.46 'TOKEN=$(cat); kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o jsonpath="{.data.tls\.crt}" | base64 -d > /tmp/seal-cert.pem && kubectl create secret docker-registry gitea-registry --docker-server=go.berg-connect.nl --docker-username=beheerder --docker-password="$TOKEN" --dry-run=client -o yaml > /tmp/plain-secret.yaml; unset TOKEN; kubeseal --scope cluster-wide --cert /tmp/seal-cert.pem --format yaml < /tmp/plain-secret.yaml > /tmp/sealed-new.yaml 2>/tmp/kubeseal-err.log; echo "SEAL_EXIT=$?"; rm -f /tmp/seal-cert.pem /tmp/plain-secret.yaml /tmp/kubeseal-err.log'
```

Expected: `SEAL_EXIT=0`. Bij non-zero exit of een lege `sealed-new.yaml`: STOP als BLOCKED (cert/key-probleem — geen plaintext tonen bij diagnose).

- [ ] **Step 3: Transfer and embed (annotatie + namespaces corrigeren)**

Run:

```bash
scp -o BatchMode=yes 192.168.2.46:/tmp/sealed-new.yaml /tmp/opencode/sealed-new.yaml
ssh -o BatchMode=yes 192.168.2.46 'rm -f /tmp/sealed-new.yaml && echo node-cleaned'
```

Bouw daarna `charts/learncicd/templates/pullsecret.yaml` exact zo op (behoud de yamllint-disable + commentaar-header, aangevuld met één cluster-wide-regel; `<BLOB>` = de volledige `.dockerconfigjson`-waarde uit `/tmp/opencode/sealed-new.yaml`, exact overnemen):

```yaml
# yamllint disable rule:line-length
# SealedSecret voor Gitea registry-pull, cluster-breed inzetbaar.
# Gegenereerd met kubeseal --scope cluster-wide tegen de cluster-key; bevat geen plaintext.
---
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: gitea-registry
  annotations:
    sealedsecrets.bitnami.com/cluster-wide: "true"
spec:
  encryptedData:
    .dockerconfigjson: <BLOB>
  template:
    metadata:
      name: gitea-registry
    type: kubernetes.io/dockerconfigjson
```

Verwijder daarna `/tmp/opencode/sealed-new.yaml` lokaal.

- [ ] **Step 4: Render-check and commit**

Run:

```bash
helm template test-release charts/learncicd --namespace default | grep -B2 -A3 "kind: SealedSecret"; echo "---"; helm lint charts/learncicd 2>&1 | tail -1
```

Expected: SealedSecret rendert met annotatie en zonder `namespace`-velden; lint schoon (alleen icon-info).

Run:

```bash
git add charts/learncicd/templates/pullsecret.yaml
git commit -m "feat: make pull secret cluster-wide for per-env namespaces"
```

### Task 3: Valideren via GitHub-PR en mergen

**Files:**
- Geen (git-operaties + API-stappen)

**Interfaces:**
- Consumes: Task 1 + 2 op branch `feat/argocd-per-env` (schoon, gepusht).
- Produces: groene CI op PR als bewijs; `main` bevat alles na merge; branches opgeruimd. Task 4 deployt vanaf `main`.

- [ ] **Step 1: Push and open a PR `feat/argocd-per-env` → `main`**

Run:

```bash
git push -u origin feat/argocd-per-env
```

Open daarna de PR (github.com of API). Titel: `feat: ArgoCD Applications per omgeving met cluster-brede pull-secret`. Niet mergen vóór Step 3.

- [ ] **Step 2: Confirm PR checks**

Expected op de PR: `Test (.NET)` ✅, `Version` ✅, `Security scan` ✅ (`Docker build` bestaat niet meer; `Publish image` **skipped** — event is `pull_request`, correct gedrag). Let op: deze PR raakt `charts/**` + `argocd/**` — met actieve path-gates draaien `test`/`security`/`version` als `skipped` en blijft de PR mergebaar; zonder gates draait alles groen. Beide uitkomsten zijn acceptabel bewijs.

- [ ] **Step 3: Merge and clean up**

Merge de PR via GitHub, verwijder de remote branch, daarna lokaal:

```bash
git checkout main
git pull
git fetch --prune origin
git branch -d feat/argocd-per-env
git log --oneline -3
```

Expected: `main` bevat de implementatie-commits plus merge; `git status --short` leeg.

### Task 4: Deployen via SSH + bewijzen (volgorde-kritisch)

**Files:**
- Geen (SSH-/kubectl-operaties)

**Interfaces:**
- Consumes: Task 3 gemergd op `main`; menselijke prerequisites uit Task 2 (token) zijn verbruikt — geen nieuwe inputs nodig.
- Produces: 3× `Synced Healthy`, 3 Running-pods met `/health` OK, oude `default`-deploy weg.

- [ ] **Step 1: Apply the three Applications via SSH**

Run (vanaf controller-machine; BatchMode, geen wachtwoorden):

```bash
for ENV in devtest acceptatie productie; do git show main:argocd/applications/learncicd-$ENV.yaml > /tmp/opencode/app-$ENV.yaml; scp -o BatchMode=yes /tmp/opencode/app-$ENV.yaml 192.168.2.46:/tmp/learncicd-app-$ENV.yaml; done
ssh -o BatchMode=yes 192.168.2.46 'for ENV in devtest acceptatie productie; do kubectl apply -f /tmp/learncicd-app-$ENV.yaml; done; rm -f /tmp/learncicd-app-*.yaml'
rm -f /tmp/opencode/app-*.yaml
```

Expected: driemaal `application.argoproj.io/learncicd-<env> created`.

- [ ] **Step 2: Wait for triple Synced Healthy (maximaal ~5 minuten)**

Run:

```bash
for i in $(seq 1 30); do S=$(ssh -o BatchMode=yes 192.168.2.46 'for ENV in devtest acceptatie productie; do kubectl -n argocd get application learncicd-$ENV -o jsonpath="{.status.sync.status}/{.status.health.status} "; done 2>/dev/null'); echo "$i: $S"; echo "$S" | grep -q "Synced Healthy Synced Healthy Synced Healthy" && break; echo "$S" | grep -qE "Degraded|Error|Unknown" && break; sleep 10; done
```

Expected: `Synced Healthy` driemaal. Bij `Degraded`/`Error`: STOP — eerst pods/events per namespace inspecteren (`kubectl -n <env> get pods`, `kubectl -n <env> get events --sort-by=.lastTimestamp | tail`), geen verdere stappen.

- [ ] **Step 3: Prove pods Running + /health OK per namespace (poorten 8080/8081/8082)**

Run:

```bash
ssh -o BatchMode=yes 192.168.2.46 'kubectl get pods -A -l app.kubernetes.io/name=learncicd -o jsonpath="{range .items[*]}{.metadata.namespace}/{.metadata.name} {.status.phase}{\"\\n\"}{end}" 2>/dev/null'
```

Expected: drie regels, elk `Running` (één pod per namespace `devtest`, `acceptatie`, `productie`).

Run daarna per omgeving (voorbeeld devtest, poort 8080; herhaal met 8081/acceptatie en 8082/productie):

```bash
ssh -o BatchMode=yes 192.168.2.46 'SVC=$(kubectl -n devtest get svc -l app.kubernetes.io/name=learncicd -o jsonpath="{.items[0].metadata.name}"); kubectl -n devtest port-forward svc/"$SVC" 18080:8080 >/tmp/pf.log 2>&1 & echo $! >/tmp/pf.pid; sleep 4; curl -s http://localhost:18080/health; echo; kill $(cat /tmp/pf.pid); rm -f /tmp/pf.pid /tmp/pf.log'
```

Expected per omgeving: body bevat `Healthy`.

- [ ] **Step 4: Delete the old stack LAST (pas bij 3× groen uit Step 3)**

Alleen als alle drie omgevingen bewezen gezond zijn. Run:

```bash
ssh -o BatchMode=yes 192.168.2.46 'kubectl -n argocd delete application learncicd 2>&1; sleep 20; kubectl -n default get deployment learncicd-learncicd 2>&1 | head -2; kubectl -n default get secret gitea-registry 2>&1 | head -1 && kubectl -n default delete secret gitea-registry 2>&1'
```

Expected: app verwijderd; deployment weg (`NotFound` — prune/cascade bewijs); handmatige secret verwijderd (niets in `default` verwijst er meer naar; de SealedSecret-versies in de env-namespaces blijven beheerd).

- [ ] **Step 5: Clean up local branch state**

```bash
git fetch --prune origin
git log --oneline -3
git status --short
```

Expected: `main` op merge-commit; tree clean; `git branch -a` toont alleen `main` + `origin/main` (+ PR-refs).
