# acc-omgeving Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Voeg een `acc`-omgeving toe die uitsluitend via de handmatige `Promote`-workflow te promoten is.

**Architecture:** Centraal (`v8`): env-allowlist uitbreiden. Lokaal (één branch/PR): promote-optie, values-bestanden, ArgoCD-apps, scaffolding, docs-aanraking niet nodig (bestaat). Daarna: GitHub-Environment, cluster-bootstrap, live bewijs-promote.

**Tech Stack:** GitHub Actions (reusable workflows, `workflow_dispatch`, Environments), Helm values, ArgoCD, SealedSecrets, k3s.

## Global Constraints

- Max 80 tekens per regel in workflows/actions; `run: >` (NOOIT `run: |` bij multi-line `$(...)`).
- Caller-workflows: géén top-level `concurrency`, géén job `name:`; `secrets: inherit`.
- Nooit versies mixen: na `v8` moet `grep -rn "cicd-workflows/.github/workflows/.*@v7" .github/workflows/` leeg zijn (zelfde voor actions-refs met `@v8`-filter).
- `yamllint`: alleen `missing document start` + `truthy` op `on:` zijn oké.
- NOOIT direct naar `main`: feature-branch + PR, conventionele commits, `m_state: clean` vóór merge.
- Zwevende major-tag `v8` wordt nieuw aangemaakt (nooit oude tags herschrijven).
- Naamgeving: namespace `acc`, bestanden `values_acc.yaml`, apps `*-acc`, placeholder-tag `0.0.0-niet-bestaand`, poort `8081`.

---

## File Structure

Centraal (na `git clone https://github.com/bergconnect/cicd-workflows.git`):

- `.github/workflows/promote-template.yml` — allowlist `[dev, prd]` → `[dev, prd, acc]` (Task 1)

Lokaal (`LearnCICD`, één branch `feat/acc-environment` vanaf `origin/main`, één PR):

- `.github/workflows/promote.yml:21` — options `[dev, prd]` → `[dev, prd, acc]` (Task 2)
- Create: `.infra/learncicd/values_acc.yaml` — port 8081, placeholder-tag (Task 2)
- Create: `.infra/learncicd-worker/values_acc.yaml` — port 8081, placeholder-tag (Task 2)
- Create: `argocd/applications/learncicd-acc.yaml` — kopie prd-manifest (Task 3)
- Create: `argocd/applications/learncicd-worker-acc.yaml` — kopie prd-manifest (Task 3)
- Modify: `scripts/new-project.sh:37-52` — `acc` in beide ENV-lussen (Task 4)

Cluster/GitHub (geen files; live-acties):

- GitHub Environment `acc` zonder reviewers (Task 5)
- Namespace `acc` + apps toepassen + secret-verificatie (Task 5)
- Bewijs-promote + pull-bewijs (Task 6)

---

### Task 1: Centraal — allowlist uitbreiden + tag v8

**Files:**
- Modify (centraal): `.github/workflows/promote-template.yml` (allowlist)

**Interfaces:**
- Consumes: niets (eerste taak)
- Produces: centrale tag `v8` met `acc` in allowlist; v1–v7 ongewijzigd

- [ ] **Step 1: Clone en lees template**

```bash
git clone https://github.com/bergconnect/cicd-workflows.git /tmp/opencode/cicd-wf8
git checkout -b feat/allow-acc
```

Lees VOLLEDIG: `/tmp/opencode/cicd-wf8/.github/workflows/promote-template.yml`.
Noteer de exacte allowlist-regel (`dev|prd`, uit v7-review bekend in de
`validate`-job: non-empty project, `dev|prd` allowlist, SemVer-regex).

- [ ] **Step 2: Breid allowlist uit naar acc**

Vervang exact `dev|prd` door `dev|prd|acc` op de allowlist-plek.
Als de allowlist op meerdere plekken staat (validate + copy-gate),
alle plekken aanpassen — bewijs met:

```bash
grep -rn "dev|prd" .github/workflows/promote-template.yml && echo REST-antenne || echo "allowlist schoon"
```

Verwacht: `allowlist schoon` (geen `dev|prd`-zonder-acc meer).

- [ ] **Step 3: yamllint + commit + push (geen PR nog)**

```bash
yamllint .github/workflows/promote-template.yml   # alleen 2 bekende warnings oké
git add .github/workflows/promote-template.yml
git commit -m "feat: sta acc toe als promote-doel"
git push -u origin feat/allow-acc
```

- [ ] **Step 4: PR, merge, tag v8**

PR aanmaken (`feat: sta acc toe als promote-doel`, base `main`),
`m_state: clean` afwachten, mergen (merge-methode `merge`;
403 → BLOCKED melden, niet omzeilen). Daarna:

```bash
git fetch origin && git checkout origin/main
git tag v8 origin/main && git push origin v8
git ls-remote --tags origin | grep -E "refs/tags/v[78]$"
```

Verwacht: `v8` op de merge-commit; v7-SHA ongewijzigd
(v7 = `e539578b54d1d7f3fa03ee2406a845b879182965`).

---

### Task 2: Lokaal — promote-optie + values_acc-bestanden

**Files:**
- Modify: `.github/workflows/promote.yml:21` (`[dev, prd]` → `[dev, prd, acc]`)
- Create: `.infra/learncicd/values_acc.yaml`
- Create: `.infra/learncicd-worker/values_acc.yaml`

**Interfaces:**
- Consumes: Task 1 (`v8` bestaat; deze taak pint nog NIET om — pins volgen in Task 4-eindcontrole)
- Produces: promote-optie + placeholder-values op branch `feat/acc-environment` (NIET pushen tot Task 4 compleet is; alle lokale commits gaan in één PR)

- [ ] **Step 1: Branch + promote-optie**

```bash
git fetch origin && git checkout -b feat/acc-environment origin/main
```

Edit `.github/workflows/promote.yml:21` exact:

```yaml
        options: [dev, prd, acc]
```

- [ ] **Step 2: values_acc.yaml aanmaken (exacte inhoud)**

`.infra/learncicd/values_acc.yaml`:

```yaml
service:
  port: 8081
image:
  tag: "0.0.0-niet-bestaand"
  repository: 192.168.2.100:3003/beheerder/learncicd-api
```

`.infra/learncicd-worker/values_acc.yaml`:

```yaml
service:
  port: 8081
image:
  tag: "0.0.0-niet-bestaand"
  repository: 192.168.2.100:3003/beheerder/learncicd-worker
```

(Repository-regels byte-identiek aan de `values_prd.yaml`-evenknie;
alleen port en tag wijken af.)

- [ ] **Step 3: Valideer + commit (niet pushen)**

```bash
python3 -c "import yaml;[yaml.safe_load(open(f)) for f in ['.infra/learncicd/values_acc.yaml','.infra/learncicd-worker/values_acc.yaml']]; print('yaml OK')"
git add .github/workflows/promote.yml .infra/learncicd/values_acc.yaml .infra/learncicd-worker/values_acc.yaml
git commit -m "feat: acc als promote-doel met placeholder-values"
```

---

### Task 3: Lokaal — ArgoCD-apps voor acc

**Files:**
- Create: `argocd/applications/learncicd-acc.yaml`
- Create: `argocd/applications/learncicd-worker-acc.yaml`

**Interfaces:**
- Consumes: Task 2 (zelfde branch `feat/acc-environment`)
- Produces: beide acc-apps op dezelfde branch (NIET pushen)

- [ ] **Step 1: Apps afleiden van prd-manifesten**

Kopieer exact en hernoem ALLEEN `prd` → `acc` (3 plekken per
bestand: `metadata.name`, `valueFiles`-regel, `destination.namespace`).
Resultaat `learncicd-acc.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: learncicd-acc
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/bergconnect/LearnCICD.git
    targetRevision: HEAD
    path: .infra/learncicd
    helm:
      valueFiles:
        - $values/.infra/learncicd/values.yaml
        - $values/.infra/learncicd/values_acc.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: acc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Zelfde voor `learncicd-worker-acc.yaml` met `path: .infra/learncicd-worker`
en `$values/.infra/learncicd-worker/values_acc.yaml`.

- [ ] **Step 2: Diff-bewijs + commit (niet pushen)**

```bash
diff <(sed 's/prd/acc/g' argocd/applications/learncicd-prd.yaml) argocd/applications/learncicd-acc.yaml && echo "api-app exact"
diff <(sed 's/prd/acc/g' argocd/applications/learncicd-worker-prd.yaml) argocd/applications/learncicd-worker-acc.yaml && echo "worker-app exact"
git add argocd/applications/learncicd-acc.yaml argocd/applications/learncicd-worker-acc.yaml
git commit -m "feat: ArgoCD-apps voor acc"
```

Verwacht: tweemaal `exact` (geen enkel ander verschil).

---

### Task 4: Lokaal — scaffolding + pins + PR

**Files:**
- Modify: `scripts/new-project.sh:37-52` (beide ENV-lussen + case-branches)
- Modify: `.github/workflows/promote.yml` (pin `promote-template.yml@v7` → `@v8`)
- Modify: `.github/workflows/cd.yml` + `ci.yml` (alleen ALS ze nog op `@v7` staan: mee naar `@v8`; centraal v8 raakt alleen promote-template, maar nooit mixen)

**Interfaces:**
- Consumes: Task 1 (v8), Task 2+3 (branch met 2 commits)
- Produces: PR met alle lokale wijzigingen, `m_state: clean`, NIET zelf mergen

- [ ] **Step 1: acc in new-project.sh**

In BEIDE `for ENV in dev prd`-lussen (`scripts/new-project.sh:37` en `:41`):
`dev prd` → `dev prd acc`, plus case-branches:
lus 1: `acc) PORT=8081; VFILE=values_acc.yaml;;`
lus 2: `acc) VFILE=values_acc.yaml;;`.
De python-vervanging blijft generiek (`-dev`→`-$ENV`,
`values_dev.yaml`→`$VFILE`, `namespace: dev`→`namespace: $ENV`)
en werkt daardoor ook voor acc. NIET de echo-hints onderaan wijzigen.

- [ ] **Step 2: Droogtest scaffolding**

```bash
bash -n scripts/new-project.sh && echo "syntax OK"
scripts/new-project.sh WegwerpAcc >/dev/null 2>&1
grep -A2 "valueFiles" argocd/applications/wegwerpacc-acc.yaml | head -3
grep "namespace: acc" argocd/applications/wegwerpacc-acc.yaml
ls .infra/wegwerpacc/values_acc.yaml && grep -E "port: 8081|0.0.0" .infra/wegwerpacc/values_acc.yaml
```

Verwacht: valueFiles met `values_acc.yaml`, `namespace: acc`,
values-bestand met port 8081. Daarna VOLLEDIG opruimen:

```bash
git clean -fd src/WegwerpAcc tests/WegwerpAcc.Tests .infra/wegwerpacc
git checkout -- LearnCICD.sln .github/projects.json
rm -f argocd/applications/wegwerpacc-*.yaml
git status --short
```

Verwacht: alleen `M scripts/new-project.sh` (+ Task 2/3-commits al vast).

- [ ] **Step 3: Pins naar @v8 + commit + push + PR**

```bash
git add scripts/new-project.sh
git commit -m "feat: scaffolding genereert acc-artefacten"
```

Pin-edits (`@v7` → `@v8` op alle drie callers: cd, promote, ci),
proof-greps, commit `chore: pin cicd-workflows op v8`, push, PR
(base `main`), wacht `m_state: clean`. NIET mergen (owner).

---

### Task 5: GitHub-Environment + cluster-bootstrap

**Files:** Geen (live-acties; vereist gemergde PR uit Task 4)

**Interfaces:**
- Consumes: Task 4 gemerged (main bevat acc-bestanden)
- Produces: namespace `acc` + beide apps live; secret beheerd en correct

- [ ] **Step 1: Environment acc aanmaken (zonder reviewers)**

```bash
PAT=$(git credential fill <<'EOF' 2>/dev/null | grep '^password=' | cut -d= -f2-
protocol=https
host=github.com
path=bergconnect/LearnCICD
EOF
)
curl -s -X PUT -H "Authorization: Bearer $PAT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/bergconnect/LearnCICD/environments/acc \
  -d '{"wait_timer":0,"reviewers":[]}' | python3 -c "import json,sys; print(json.load(sys.stdin).get('name'))"
```

Verwacht: `acc`.

- [ ] **Step 2: Apps toepassen op cluster**

```bash
scp argocd/applications/learncicd-acc.yaml argocd/applications/learncicd-worker-acc.yaml 192.168.2.46:/tmp/
ssh -o ConnectTimeout=10 192.168.2.46 'kubectl apply -f /tmp/learncicd-acc.yaml && kubectl apply -f /tmp/learncicd-worker-acc.yaml && shred -u /tmp/learncicd-acc.yaml /tmp/learncicd-worker-acc.yaml'
```
(`CreateNamespace=true` in de apps
maakt namespace `acc` automatisch; `selfHeal` houdt sync vast.)
Wacht 90s, controleer:

```bash
ssh 192.168.2.46 'kubectl get applications -n argocd | grep -E "acc|NAME"'
```

Verwacht: beide acc-apps zichtbaar (health Degraded/ImagePull op
placeholder-tag is verwacht, geen blokker).

- [ ] **Step 3: Secret-verificatie**

Per namespace `acc` (beide charts delen het object per namespace;
check één keer volstaat, check beide bij twijfel): secret
`gitea-registry` bestaat, type `kubernetes.io/dockerconfigjson`,
bevat BEIDE registries, ownerRef `SealedSecret`, SealedSecret
`Synced=True`. Analoog aan de dev/prd-verificatie uit de
vorige sessie (decode `.dockerconfigjson`, vergelijk keys).

---

### Task 6: Bewijs-promote naar acc + pull-bewijs

**Files:** Geen (live verificatie)

**Interfaces:**
- Consumes: Task 5 (bootstrap compleet)
- Produces: acc draait echte versie; pull-bewijs

- [ ] **Step 1: Handmatige Promote-dispatch naar acc**

Actions-tab → `Promote` → Run workflow: `project=Api`,
`version=<huidige dev-tag uit origin/main:.infra/learncicd/values_dev.yaml>`,
`environment=acc`. Wacht: validatie groen → bump-PR →
automerge. Noteer run-ID + PR-nummer.

- [ ] **Step 2: Pull-bewijs**

```bash
ssh -o ConnectTimeout=10 192.168.2.46 'kubectl -n acc get pods -o json' | python3 -c "
import json,sys
for p in json.load(sys.stdin)['items']:
    print(p['metadata']['name'], '|', p['spec']['containers'][0]['image'].split(':')[-1], '|', p['status']['phase'])"
```

Verwacht: pod draait de gepromote tag, `Running`.
Herhaal voor Worker met de Worker-dev-tag.

- [ ] **Step 3: Rapporteer**

Meld: Environment `acc` live, beide apps gesynct na promote,
pod-tags + fases, run-IDs. Resterende minors voor final review.

---

### Task 7: Afronding

**Files:** Geen

**Interfaces:**
- Consumes: Task 6 (bewijs compleet)
- Produces: schone repo

- [ ] **Step 1: Verifieer eindstand**

```bash
git checkout main && git pull -q origin main && git status --short
grep -rnE "@v[1-7]" .github/workflows/ | grep -v "@v8" && echo OUD-GEVONDEN || echo "geen oude pins"
```

Verwacht: lege status, geen oude pins.

- [ ] **Step 2: Ruim branches/clones op**

Verwijder `feat/acc-environment` (na merge), `/tmp/opencode/cicd-wf8`.
Laat worktrees van ander werk met rust.
