# CD-promotie met approvals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-omgeving image-tags met een `promote.yml`-workflow die via GitHub Environment-gates (required reviewers) en sequentie-checks promoties naar acceptatie/productie poort, terwijl DevTest automatisch blijft meelopen.

**Architecture:** `image.tag` verhuist van base-`values.yaml` naar de drie overlays; CD schrijft nieuwe tags alleen nog naar DevTest; `promote.yml` (workflow_dispatch) valideert, wacht op environment-approval, checkt acc→prod-volgorde en opent een promotie-PR; ArgoCD automated sync deployt na merge ongewijzigd.

**Tech Stack:** GitHub Actions (workflow_dispatch, environments), yq, skopeo, helm, yamllint, GitHub REST API.

## Global Constraints

- NOOIT direct committen of pushen naar `main` — altijd via feature-branch + PR met groene checks.
- Conventionele commit-messages (`feat:`, `fix:`, `ci:`, `chore:`, `docs:`).
- Deployment-template gebruikt `"{{ .Values.image.repository }}:{{ .Values.image.tag }}"` ZONDER default — elke overlay MOET `image.tag` definiëren zodra de base-tag weg is; Task 1 is daarom atomair (4 bestanden, 1 commit).
- Huidige live tag overal: `0.1.76` (dit is de startwaarde in alle drie overlays).
- Runner heeft `yq` en `skopeo` (bewezen door bestaande CD-jobs); `GITEA_USER`/`GITEA_TOKEN`-secrets bestaan al en zijn herbruikbaar voor `skopeo inspect`.
- Promotie-branchvorm: `ci/promote-<env>-<versie>` (force-push-patroon zoals `update-image-tag`).
- Bekend risico (Task 6 bewijst): single-user repo waarin dispatcher = approver — als GitHub zelf-approval bij environments blokkeert, deadlockt de flow en is een fallback nodig.

---

### Task 1: image.tag per omgeving (atomair)

**Files:**
- Modify: `charts/learncicd/values.yaml` (verwijder `tag: 0.1.76`-regel, behoud repository + pullPolicy-commentaar)
- Modify: `charts/learncicd/values-devtest.yaml`, `charts/learncicd/values-acceptatie.yaml`, `charts/learncicd/values-productie.yaml` (voeg elk `image.tag: "0.1.76"` toe — quotes verplicht: NBGV-tags als `0.1.76` parsen als string, maar expliciete quotes voorkomen float-misparse bij tags als `1.10`)

**Interfaces:**
- Consumes: niets (eerste task).
- Produces: per-env `image.tag` die Task 2 (CD-schrijflocatie), Task 3 (promotie-bump-doel) en ArgoCD-renders gebruiken.

- [ ] **Step 1: Verwijder tag uit base, voeg toe aan overlays**

Base wordt (alleen tag-regel weg):
```yaml
image:
  repository: go.berg-connect.nl/beheerder/learncicd
  # IfNotPresent haalt eenzelfde tag niet opnieuw op bij digest-wissel;
  # use Always voor strict latest-volgen.
  pullPolicy: IfNotPresent
```
Elke overlay wordt (voorbeeld devtest; acceptatie/productie analoog met eigen port):
```yaml
service:
  port: 8080
image:
  tag: "0.1.76"
```

- [ ] **Step 2: Verifieer renders per omgeving**

Run:
```bash
for env in devtest acceptatie productie; do helm template test-release charts/learncicd -f charts/learncicd/values.yaml -f charts/learncicd/values-$env.yaml --namespace $env | grep 'image:'; done
```
Expected: drie regels `image: "go.berg-connect.nl/beheerder/learncicd:0.1.76"`.

Run: `helm lint charts/learncicd`
Expected: `1 chart(s) linted, 0 chart(s) failed`.

- [ ] **Step 3: Commit**

```bash
git add charts/learncicd/values.yaml charts/learncicd/values-devtest.yaml charts/learncicd/values-acceptatie.yaml charts/learncicd/values-productie.yaml
git commit -m "feat: image.tag per omgeving voor promotieflow"
```

---

### Task 2: CD schrijft nieuwe tags naar DevTest

**Files:**
- Modify: `.github/workflows/cd.yml` (job `update-image-tag`: `charts/learncicd/values.yaml` → `charts/learncicd/values-devtest.yaml` op beide plekken — de `yq`-regel én de `git add`-regel; commit-message `ci: update image tag to $VERSION` ongewijzigd)

**Interfaces:**
- Consumes: Task 1 (`values-devtest.yaml` bevat `image.tag`).
- Produces: DevTest-autoflow die Task 6 end-to-end bewijst.

- [ ] **Step 1: Retarget de twee paden**

Exacte wijzigingen in `.github/workflows/cd.yml`:
```yaml
# was: yq -i '.image.tag = strenv(TAG)' charts/learncicd/values.yaml
yq -i '.image.tag = strenv(TAG)' charts/learncicd/values-devtest.yaml
```
```bash
# was: git add charts/learncicd/values.yaml;
git add charts/learncicd/values-devtest.yaml;
```

- [ ] **Step 2: Verifieer workflow + yq-gedrag**

Run: `yamllint .github/workflows/cd.yml`
Expected: exit 0 (alleen de 2 bekende warnings zijn oké).

Run (droog, op een kopie — bewijst dat yq de overlay-tag bijwerkt zonder de rest te raken):
```bash
cp charts/learncicd/values-devtest.yaml /tmp/opencode/probe-values.yaml && TAG=9.9.9 yq -i '.image.tag = strenv(TAG)' /tmp/opencode/probe-values.yaml && cat /tmp/opencode/probe-values.yaml && rm /tmp/opencode/probe-values.yaml
```
Expected: `service.port` ongewijzigd, `image.tag: "9.9.9"`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/cd.yml
git commit -m "ci: CD-tag-update naar DevTest-overlay"
```

---

### Task 3: promote.yml-workflow (validate → gate → promotie-PR)

**Files:**
- Create: `.github/workflows/promote.yml`

**Interfaces:**
- Consumes: Task 1 (per-env tags als bump-doel en sequentie-bron).
- Produces: dispatchbare promotieflow die Task 4 (environments) poort en Task 6 bewijst.

- [ ] **Step 1: Schrijf `.github/workflows/promote.yml`**

```yaml
name: Promote

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Doelomgeving'
        required: true
        type: choice
        options: [acceptatie, productie]
      version:
        description: 'Image-versie (SemVer2, bv. 0.1.77)'
        required: true
        type: string

permissions: {}

concurrency:
  group: promote-${{ inputs.environment }}
  cancel-in-progress: false

jobs:
  validate:
    name: Validate
    runs-on: [self-hosted]
    timeout-minutes: 5
    permissions:
      contents: read
    outputs:
      version: ${{ steps.check.outputs.version }}
    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Check version exists as image tag
        id: check
        env:
          IMAGE: ${{ secrets.GITEA_HOST }}/beheerder/learncicd
          GITEA_USER: ${{ secrets.GITEA_USER }}
          GITEA_TOKEN: ${{ secrets.GITEA_TOKEN }}
        run: >
          VERSION="${{ inputs.version }}";
          case "$VERSION" in ''|*[!0-9.]*)
            echo "::error::Ongeldige version-input '$VERSION' (alleen cijfers en punten)"; exit 1;; esac;
          skopeo inspect --raw
          --creds "$GITEA_USER:$GITEA_TOKEN"
          docker://$IMAGE:$VERSION > /dev/null
          || { echo "::error::Image-tag $VERSION bestaat niet in $IMAGE"; exit 1; };
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"

  promote:
    name: Promote to ${{ inputs.environment }}
    runs-on: [self-hosted]
    needs: [validate]
    timeout-minutes: 10
    environment: ${{ inputs.environment }}
    permissions:
      contents: write
      pull-requests: write
    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Sequence check and bump tag
        env:
          ENV: ${{ inputs.environment }}
          VERSION: ${{ needs.validate.outputs.version }}
        run: >
          FILE="charts/learncicd/values-$ENV.yaml";
          CURRENT="$(yq '.image.tag' "$FILE")";
          if [ "$CURRENT" = "$VERSION" ]; then
            echo "Omgeving $ENV staat al op $VERSION — niets te doen"; exit 0; fi;
          if [ "$ENV" = "productie" ]; then
            ACC="$(yq '.image.tag' charts/learncicd/values-acceptatie.yaml)";
            if [ "$ACC" != "$VERSION" ]; then
              echo "::error::Sequentie-schending: acceptatie staat op $ACC, gevraagd $VERSION voor productie";
              exit 1; fi; fi;
          yq -i '.image.tag = strenv(VERSION)' "$FILE"

      - name: Commit and push promotion branch
        id: bump
        env:
          ENV: ${{ inputs.environment }}
          VERSION: ${{ needs.validate.outputs.version }}
          BRANCH: ci/promote-${{ inputs.environment }}-${{ needs.validate.outputs.version }}
        run: >
          FILE="charts/learncicd/values-$ENV.yaml";
          if git diff --quiet "$FILE"; then
            echo "Geen wijziging — klaar"; echo "changed=false" >> "$GITHUB_OUTPUT"; exit 0; fi;
          git config user.name "gitea-actions[bot]";
          git config user.email "gitea-actions[bot]@users.noreply.gitea";
          git switch -C "$BRANCH";
          git add "$FILE";
          git commit -m "ci: promote $ENV to $VERSION";
          git push --force origin "$BRANCH";
          echo "changed=true" >> "$GITHUB_OUTPUT"

      - name: Open promotion PR via API
        if: steps.bump.outputs.changed == 'true'
        env:
          ENV: ${{ inputs.environment }}
          VERSION: ${{ needs.validate.outputs.version }}
          BRANCH: ci/promote-${{ inputs.environment }}-${{ needs.validate.outputs.version }}
          TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: >
          STATUS=$(curl -s -o response.json -w "%{http_code}"
          -X POST "${{ github.api_url }}/repos/${{ github.repository }}/pulls"
          -H "Authorization: token $TOKEN"
          -H "Content-Type: application/json"
          -d "{\"title\":\"ci: promote $ENV
          to $VERSION\",\"body\":\"Promotie van image $VERSION
          naar $ENV (sequentie gecontroleerd).\",\"head\":\"$BRANCH\",\"base\":\"main\"}");
          cat response.json;
          if [ "$STATUS" != "201" ] && ! grep -q "already exists" response.json;
          then echo "::error::Failed to open PR (HTTP $STATUS)"; exit 1; fi
```

Vaste keuzes (niet afwijken zonder plan-update): `cancel-in-progress: false`; idempotentie-guard (`CURRENT = VERSION` → exit 0 vóór enige git-actie) plus `changed`-flag van bump-stap als `if:` op de PR-stap (een worktree-vs-HEAD-check na de commit zou de PR altijd overslaan); `already exists`-tolerantie identiek aan `update-image-tag`; `environment: ${{ inputs.environment }}` exact (geen prefix/suffix — moet overeenkomen met de environment-namen uit Task 4).

- [ ] **Step 2: Verifieer workflow**

Run: `yamllint .github/workflows/promote.yml`
Expected: exit 0 (alleen de 2 bekende warnings zijn oké).

Run: `python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/promote.yml')); print(d['name'], '|', sorted(d['jobs'].keys()))"`
Expected: `Promote | ['promote', 'validate']`.

Run (droogtest sequentie-logica op kopieën — bewijst alle drie paden):
```bash
mkdir -p /tmp/opencode/promtest/charts/learncicd && cp charts/learncicd/values-acceptatie.yaml charts/learncicd/values-productie.yaml /tmp/opencode/promtest/charts/learncicd/ && cd /tmp/opencode/promtest && echo "-- pad 1: prod 0.1.75 terwijl acc 0.1.76 (moet falen):" && (ACC="$(yq '.image.tag' charts/learncicd/values-acceptatie.yaml)"; [ "$ACC" != "0.1.75" ] && echo "FAIL-zoals-verwacht (acc=$ACC)" || echo "PROBLEEM"); echo "-- pad 2: idempotent (zelfde versie):" && ([ "0.1.76" = "0.1.76" ] && echo "niets-te-doen-zoals-verwacht"); echo "-- pad 3: bump werkt:" && VERSION=0.1.77 yq -i '.image.tag = strenv(VERSION)' charts/learncicd/values-acceptatie.yaml && yq '.image.tag' charts/learncicd/values-acceptatie.yaml; cd - > /dev/null && rm -rf /tmp/opencode/promtest
```
Expected: `FAIL-zoals-verwacht (acc=0.1.76)`, `niets-te-doen-zoals-verwacht`, `0.1.77`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/promote.yml
git commit -m "feat: promotie-workflow met environment-gates en sequentie-check"
```

---

### Task 4: GitHub Environments acceptatie + productie (controller, geen code)

**Files:** geen (repo-instelling via API; geen commit).

**Interfaces:**
- Consumes: Task 3 (workflow refereert `environment: acceptatie|productie` — zonder deze task pauzeert er niets en faalt de run op een ontbrekende environment).
- Produces: werkende harde gates voor Task 6.

- [ ] **Step 1: Eigen user-ID resolven**

Run:
```bash
TOKEN=$(sed -n 's#^https://[^:]*:\([^@]*\)@github\.com$#\1#p' ~/.git-credentials | head -1) && curl -s -H "Authorization: Bearer $TOKEN" https://api.github.com/user | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['id'], d['login'])"
```
Expected: `<numerieke-id> <login>` (ID noteren voor stap 2; token daarna `unset TOKEN`).

- [ ] **Step 2: Beide environments aanmaken met required reviewer**

Run (per env, met ID uit stap 1):
```bash
TOKEN=$(...) && curl -s -X PUT -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $TOKEN" "https://api.github.com/repos/bergconnect/LearnCICD/environments/acceptatie" -d '{"reviewers":[{"type":"User","id":<ID>}]}' | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('name'), '| reviewers:', [(r.get('reviewer') or {}).get('login') for r in d.get('protection_rules',[]) if r.get('type')=='required_reviewers'] or d.get('protection_rules'))"; unset TOKEN
```
Zelfde voor `productie`. Expected: per env de naam + required_reviewers-regel met eigen login.

- [ ] **Step 3: Verifieer via GET**

Run: `GET /repos/bergconnect/LearnCICD/environments/acceptatie` en `.../productie`.
Expected: beide bestaan, elk met exact één `required_reviewers`-regel.

---

### Task 5: Valideren via GitHub-PR en mergen

**Files:** geen nieuwe wijzigingen (push + PR + merge van Tasks 1–3).

**Interfaces:**
- Consumes: Tasks 1–3 (commits op feature-branch).
- Produces: `promote.yml` + per-env tags op `main` (vereist voor Task 6 — dispatches draaien tegen `main`).

- [ ] **Step 1: Push en PR**

Run: `git push -u origin feat/cd-promotion` en open PR via API (titel `feat: CD-promotie met approvals`, base `main`).
Expected: PR-nummer; `git ls-remote origin` toont de branch.

- [ ] **Step 2: Poll checks tot groen**

Run: check-runs op de PR-SHA.
Expected: `Change detection` success; `Test (.NET)` + `Security scan` SKIPPED (charts/workflows-only — bewezen patroon uit PR #61); CodeQL + Analyze success; PR `mergeable: clean`.

- [ ] **Step 3: Merge + cleanup**

Run: merge via API, delete remote branch (verwacht HTTP 204), `checkout main`, `pull`, `fetch --prune`, `branch -d`, tree clean.
Expected: `main` op merge-commit; geen lokale/remote feature-branch.

---

### Task 6: Live bewijs van gates op de cluster (controller, geen code)

**Files:** geen (dispatches + approvals via API/UI; geen commit).

**Interfaces:**
- Consumes: Task 4 (environments bestaan) + Task 5 (`promote.yml` op `main`).
- Produces: bewezen gate-mechanica (Definition of Done).

- [ ] **Step 1: Negatief — ongeldige versie faalt vóór approval**

Dispatch `promote.yml` op `main` met `environment: acceptatie`, `version: 0.0.0-nonexistent`.
Expected: `validate` faalt met `Image-tag ... bestaat niet`; `promote` start NOOIT (geen approval gevraagd); geen branch/PR.

- [ ] **Step 2: Negatief — sequentie-schending faalt ná approval**

Bepaal een oudere bestaande tag via Gitea-API (tag ≠ huidige acc-tag; bv. `0.1.75` indien aanwezig).
Dispatch met `environment: productie`, die versie. Observeer dat de run pauzeert op de environment-gate
(pending approval — DIT bewijst de harde gate), approve via API
(`POST /repos/bergconnect/LearnCICD/actions/runs/<run-id>/pending_deployments`,
`{"environment_ids":[<id>],"state":"approved"}`) of UI.
Expected: na approval faalt `promote` met `Sequentie-schending`; geen branch/PR.
Bijsturen: als GitHub zelf-approval blokkeert (dispatcher = approver), is dit het bewezen risico uit
Global Constraints — STOP, rapporteer exact gedrag, fallback ontwerpen (geen workarounds verzinnen
buiten het plan).

- [ ] **Step 3: Positief — idempotente promotie + bewijs DevTest-autoflow**

Dispatch met `environment: acceptatie`, huidige live versie (`0.1.76` of nieuwer indien CD inmiddels
publiceerde). Approve. Expected: `promote` slaagt met `staat al op ... — niets te doen` (of opent een
PR indien acc achterloopt — dan PR mergen en ArgoCD-sync bewijzen: app Synced/Healthy, pod-image is
de gepromote tag, `/health` 200).
DevTest-bewijs: `yq '.image.tag' charts/learncicd/values-devtest.yaml` op `main` volgt nieuwe
CD-publicaties automatisch (zichtbaar bij de eerstvolgende image-tag-PR na deze merge).

**Definition of Done:** 3/3 dispatches met verwacht gedrag + transcripten in het task-rapport;
geen ongewenste branches/PRs/clusterwijzigingen achtergebleven.
