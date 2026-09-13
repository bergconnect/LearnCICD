# GitHub Workflows Parity with Gitea Example Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trek `ci.yml`, `cd.yml` en `promote.yml` in deze GitHub-repo gelijk met het Gitea-voorbeeld (`/home/lvdberg/Projects/LearnCICD_Gitea/LearnCICD/.github/workflows`), met behoud van alle GitHub-eigen constructies.

**Architecture:** Drie gerichte workflow-edits (geen code-, chart- of ArgoCD-wijzigingen): CI krijgt de per-env `paths-ignore`-breaker, CD en Promote krijgen de robuustere PR-open-vorm (`API`/`REPO`-env + `PR_NUMBER`-lookup) plus `run-name`/job-naam, terwijl `runs-on`, secrets, `environment`-gate en merge-flow GitHub-native blijven.

**Tech Stack:** GitHub Actions (pull_request/push/workflow_dispatch, environments), bash + `yq`/`jq`/`curl`, yamllint, GitHub REST API voor pulls.

## Global Constraints

- NOOIT direct committen of pushen naar `main` — werk op feature-branch `ci/github-parity-gitea`, merge uitsluitend via GitHub PR met groene checks.
- Conventionele commit-messages (`ci:`, `chore:`, `feat:`).
- `runs-on: [self-hosted]` blijft overal staan — `ubuntu-latest` uit het Gitea-voorbeeld wordt NIET overgenomen (runner is `github-runner`, unprivileged LXC met nesting).
- Secrets blijven `GITEA_HOST` / `GITEA_USER` / `GITEA_TOKEN` — `REGISTRY_HOST` + `GH_PAT` + hardcoded `beheerder` uit het Gitea-voorbeeld worden NIET overgenomen (zie `docs/superpowers/specs/2026-09-11-gitea-publish-design.md`).
- `promote.yml` behoudt `environment: ${{ inputs.environment }}` (GitHub approval-gate) — de Gitea-`NOTE`-comment en het weglaten van `environment` worden NIET overgenomen.
- Geen `Enable auto-merge`-stap met Gitea-payload `{"Do":"merge","merge_when_checks_succeed":true}` — die payload is ongeldig op de GitHub REST API; merges blijven handmatig via branch protection (spec zegt "mens mergt").
- Bot-identiteit `gitea-actions[bot]` blijft ongewijzigd (gelijk aan voorbeeld; alleen git-config, geen auth-effect).
- `repoURL` in `argocd/` blijft `https://github.com/bergconnect/LearnCICD.git`; chart `image.tag`-waarden worden NIET gesynchroniseerd (alleen levende versies, geen logica).
- Bestanden behouden POSIX-newline op EOF (het Gitea-voorbeeld mist deze op `ci.yml`; wij houden de newline).
- `yamllint` exit 0 met hooguit de 2 bekende warnings per bestand (`missing document start`, `truthy` op `on:`); geen regels langer dan nodig (bestaande `run: >`-folding hergebruiken).
- Validatie vóór PR (zelfde als CI): `dotnet restore`, `dotnet build -c Release --no-restore /p:TreatWarningsAsErrors=true`, `dotnet test -c Release --no-build --coverage --coverage-output-format cobertura` alleen indien code geraakt (hier niet — workflows-only), plus `yamllint` op alle drie workflows.

---

## File Structure

| Bestand | Verantwoordelijkheid |
|---|---|
| `.github/workflows/ci.yml` | Alleen PR-trigger uitbreiden met per-env `paths-ignore`-breaker (Task 1). |
| `.github/workflows/cd.yml` | Alleen `update-image-tag` / `Open update PR`-stap robuuster maken: `API`/`REPO`-env + `PR_NUMBER`-lookup (Task 2). Geen auto-merge. |
| `.github/workflows/promote.yml` | `run-name` + job-naam uit voorbeeld overnemen, `Open promotion PR`-stap idem robuuster maken (Task 3). `environment`-gate blijft. |

`charts/*` en `argocd/*` worden NIET aangeraakt. `docs/superpowers/plans/2026-09-13-github-workflows-parity.md` is dit planbestand zelf.

---

### Task 1: ci.yml — per-env values-breaker op PR-trigger

**Files:**
- Modify: `.github/workflows/ci.yml:3-5` (triggerblok)
- Test: `yamllint .github/workflows/ci.yml` + `python3 -c "import yaml; ..."`-parse

**Interfaces:**
- Consumes: niets (eerste task).
- Produces: PR-trigger die tag-only PRs (`ci/image-tag-update`, `ci/promote-*`) niet opnieuw volledig test; Task 4 vertrouwt hierop voor groene checks.

- [ ] **Step 1: Voeg paths-ignore toe aan de pull_request-trigger**

Huidig (`ci.yml:3-5`):
```yaml
on:
  pull_request:
    branches: [main]
```

Wordt (exact, overgenomen uit Gitea-voorbeeld, newline behouden):
```yaml
on:
  pull_request:
    branches: [main]
    paths-ignore:
      - 'charts/learncicd/values-devtest.yaml'
      - 'charts/learncicd/values-acceptatie.yaml'
      - 'charts/learncicd/values-productie.yaml'
```

Reden: `update-image-tag` schrijft naar `values-devtest.yaml` en `promote` naar `values-<env>.yaml`; zonder deze breaker triggert elke tag-PR opnieuw `test`/`security` zonder noodzaak. Dit is de tweede verdedigingslinie naast de `changes`-job (zie `docs/superpowers/specs/2026-09-11-path-triggers-design.md` sectie 2). `runs-on` blijft `[self-hosted]` — niet wijzigen.

- [ ] **Step 2: Verifieer YAML**

Run:
```bash
yamllint .github/workflows/ci.yml; echo "exit=$?"
```
Expected: `exit=0` plus alleen de 2 bekende warnings (`missing document start`, `truthy`).

Run:
```bash
python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/ci.yml')); print(d['on']['pull_request']['paths-ignore'])"
```
Expected: `['charts/learncicd/values-devtest.yaml', 'charts/learncicd/values-acceptatie.yaml', 'charts/learncicd/values-productie.yaml']`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: skip CI op per-env values-breaker zoals Gitea-voorbeeld"
```

---

### Task 2: cd.yml — robuuste Open-update-PR (zonder Gitea auto-merge)

**Files:**
- Modify: `.github/workflows/cd.yml:128-144` (stap `Open update PR via API`)
- Test: `yamllint .github/workflows/cd.yml` + `bash -n`-equivalent via `python3 -c` YAML-parse + `jq --version`-check

**Interfaces:**
- Consumes: Task 1 (onafhankelijk — geen code-afhankelijkheid, alleen zelfde branch).
- Produces: `update-image-tag`-job die bij `already exists` het bestaande PR-nummer resolveert naar `steps.open_pr.outputs.pr_number`; Task 4 bewijst groene `Version`-check op de PR.

- [ ] **Step 1: Hernoem stap en voeg API/REPO-env + PR_NUMBER-lookup toe**

Huidig (`cd.yml:128-144`):
```yaml
      - name: Open update PR via API
        env:
          BRANCH: ci/image-tag-update
          TOKEN: ${{ secrets.GH_PAT }}
        run: >
          VERSION="${{ needs.version.outputs.semVer }}";
          STATUS=$(curl -s -o response.json -w "%{http_code}"
          -X POST "${{ github.api_url }}/repos/${{ github.repository }}/pulls"
          -H "Authorization: token $TOKEN"
          -H "Content-Type: application/json"
          -d "{\"title\":\"ci: update image tag
          to $VERSION\",\"body\":\"Automated tag update
          for image published from
          ${{ github.sha }}.\",\"head\":\"$BRANCH\",\"base\":\"main\"}");
          cat response.json;
          if [ "$STATUS" != "201" ] && ! grep -q "already exists" response.json;
          then echo "::error::Failed to open PR (HTTP $STATUS)"; exit 1; fi
```

Wordt (vorm overgenomen uit Gitea-voorbeeld; secrets, runs-on, bot-naam en `IMAGE`-env ongewijzigd; géén `Enable auto-merge`-stap erachter):
```yaml
      - name: Open update PR
        id: open_pr
        env:
          BRANCH: ci/image-tag-update
          TOKEN: ${{ secrets.GH_PAT }}
          API: ${{ github.api_url }}
          REPO: ${{ github.repository }}
        run: >
          VERSION="${{ needs.version.outputs.semVer }}";
          STATUS=$(curl -s -o response.json -w "%{http_code}"
          -X POST "$API/repos/$REPO/pulls"
          -H "Authorization: token $TOKEN"
          -H "Content-Type: application/json"
          -d "{\"title\":\"ci: update image tag
          to $VERSION\",\"body\":\"Automated tag update
          for image published from
          ${{ github.sha }}.\",\"head\":\"$BRANCH\",\"base\":\"main\"}");
          cat response.json;
          if [ "$STATUS" != "201" ] && ! grep -q "already exists" response.json;
          then echo "::error::Failed to open PR (HTTP $STATUS)"; exit 1; fi;
          PR_NUMBER=$(jq -r '.number // empty' response.json);
          if [ -z "$PR_NUMBER" ]; then
          PR_NUMBER=$(curl -s -H "Authorization: token $TOKEN"
          "$API/repos/$REPO/pulls?state=open"
          | jq -r --arg BRANCH "$BRANCH"
          '.[] | select(.head.ref == $BRANCH) | .number' | head -n1); fi;
          if [ -z "$PR_NUMBER" ]; then
          echo "::error::PR number not found"; exit 1; fi;
          echo "pr_number=$PR_NUMBER" >> "$GITHUB_OUTPUT"
```

Bewust NIET overgenomen: de Gitea-stap `Enable auto-merge` met `-d '{"Do":"merge","merge_when_checks_succeed":true}'` — GitHub kent geen `Do`-veld op `POST /pulls/{n}/merge` en zou `422 Validation Failed` geven. Handmatige merge via branch protection blijft de flow.

- [ ] **Step 2: Verifieer workflow + jq-aanwezigheid**

Run:
```bash
yamllint .github/workflows/cd.yml; echo "exit=$?"
```
Expected: `exit=0`, alleen de 2 bekende warnings.

Run:
```bash
python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/cd.yml')); s=[s for s in d['jobs']['update-image-tag']['steps'] if s.get('id')=='open_pr']; print(s[0]['name'], '|', sorted(s[0]['env'].keys()))"
```
Expected: `Open update PR | ['API', 'BRANCH', 'REPO', 'TOKEN']`.

Run:
```bash
jq --version
```
Expected: `jq-1.x` (aanwezig op runner én lokaal; nodig voor de lookup).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/cd.yml
git commit -m "ci: robuuste update-PR met PR-nummer-lookup zoals Gitea-voorbeeld"
```

---

### Task 3: promote.yml — run-name, job-naam en robuuste PR-open (met GitHub environment-gate)

**Files:**
- Modify: `.github/workflows/promote.yml:1` (voeg `run-name` toe), `.github/workflows/promote.yml:53-54` (job-naam), `.github/workflows/promote.yml:106-126` (stap `Open promotion PR via API`)
- Test: `yamllint .github/workflows/promote.yml` + YAML-parse van `run-name`, job-naam en `environment`

**Interfaces:**
- Consumes: Task 2 (zelfde PR-open-patroon — namen en env-sleutels identiek: `API`, `REPO`, `TOKEN`, output `pr_number`).
- Produces: dispatchbare `promote.yml` met betere Actions-lijstweergave (`run-name`) en bestaande-PR-tolerantie; `environment`-gate blijft de harde approval-poort voor Task 4-bewijs.

- [ ] **Step 1: Voeg run-name toe onder name**

Huidig (`promote.yml:1`):
```yaml
name: Promote
```

Wordt (exact uit Gitea-voorbeeld):
```yaml
name: Promote

run-name: Promote ${{ inputs.environment }} to ${{ inputs.version }}
```

- [ ] **Step 2: Hernoem promote-job (behoud environment-gate)**

Huidig:
```yaml
  promote:
    name: Promote to ${{ inputs.environment }}
    runs-on: [self-hosted]
    needs: [validate]
    timeout-minutes: 10
    environment: ${{ inputs.environment }}
```

Wordt (alleen `name` wijzigt; `runs-on: [self-hosted]` en `environment:` blijven):
```yaml
  promote:
    name: Promote ${{ inputs.environment }} to ${{ inputs.version }}
    runs-on: [self-hosted]
    needs: [validate]
    timeout-minutes: 10
    environment: ${{ inputs.environment }}
```

De Gitea-`NOTE`-comment over `environment` wordt NIET overgenomen — die geldt alleen voor Gitea Actions; op GitHub is `environment:` juist de vereiste harde gate (zie `docs/superpowers/specs/2026-09-12-cd-promotion-design.md` sectie 1).

- [ ] **Step 3: Herwerk Open-promotion-PR-stap**

Huidig (`promote.yml:106-126`):
```yaml
      - name: Open promotion PR via API
        if: steps.bump.outputs.changed == 'true'
        env:
          ENV: ${{ inputs.environment }}
          VERSION: ${{ needs.validate.outputs.version }}
          BRANCH: "ci/promote-${{ inputs.environment }}-\
            ${{ needs.validate.outputs.version }}"
          TOKEN: ${{ secrets.GH_PAT }}
        run: >
          STATUS=$(curl -s -o response.json -w "%{http_code}"
          -X POST "${{ github.api_url }}/repos/${{ github.repository }}/pulls"
          -H "Authorization: token $TOKEN"
          -H "Content-Type: application/json"
          -d "{\"title\":\"ci: promote $ENV
          to $VERSION\",\"body\":\"Promotie van image $VERSION
          naar $ENV
          (sequentie
          gecontroleerd).\",\"head\":\"$BRANCH\",\"base\":\"main\"}");
          cat response.json;
          if [ "$STATUS" != "201" ] && ! grep -q "already exists" response.json;
          then echo "::error::Failed to open PR (HTTP $STATUS)"; exit 1; fi
```

Wordt (env `IMAGE`/`GITEA_USER`/`GITEA_TOKEN` in `validate` blijven `GITEA_HOST`-vorm; géén `Enable auto-merge`):
```yaml
      - name: Open promotion PR
        id: open_pr
        if: steps.bump.outputs.changed == 'true'
        env:
          ENV: ${{ inputs.environment }}
          VERSION: ${{ needs.validate.outputs.version }}
          BRANCH: "ci/promote-${{ inputs.environment }}-\
            ${{ needs.validate.outputs.version }}"
          TOKEN: ${{ secrets.GH_PAT }}
          API: ${{ github.api_url }}
          REPO: ${{ github.repository }}
        run: >
          STATUS=$(curl -s -o response.json -w "%{http_code}"
          -X POST "$API/repos/$REPO/pulls"
          -H "Authorization: token $TOKEN"
          -H "Content-Type: application/json"
          -d "{\"title\":\"ci: promote $ENV
          to $VERSION\",\"body\":\"Promotie van image $VERSION
          naar $ENV
          (sequentie
          gecontroleerd).\",\"head\":\"$BRANCH\",\"base\":\"main\"}");
          cat response.json;
          if [ "$STATUS" != "201" ] && ! grep -q "already exists" response.json;
          then echo "::error::Failed to open PR (HTTP $STATUS)"; exit 1; fi;
          PR_NUMBER=$(jq -r '.number // empty' response.json);
          if [ -z "$PR_NUMBER" ]; then
          PR_NUMBER=$(curl -s -H "Authorization: token $TOKEN"
          "$API/repos/$REPO/pulls?state=open"
          | jq -r --arg BRANCH "$BRANCH"
          '.[] | select(.head.ref == $BRANCH) | .number' | head -n1); fi;
          if [ -z "$PR_NUMBER" ]; then
          echo "::error::PR number not found"; exit 1; fi;
          echo "pr_number=$PR_NUMBER" >> "$GITHUB_OUTPUT"
```

- [ ] **Step 4: Verifieer workflow**

Run:
```bash
yamllint .github/workflows/promote.yml; echo "exit=$?"
```
Expected: `exit=0`, alleen de 2 bekende warnings.

Run:
```bash
python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/promote.yml')); print(d.get('run-name')); print(d['jobs']['promote']['name']); print(d['jobs']['promote'].get('environment'))"
```
Expected:
```
Promote ${{ inputs.environment }} to ${{ inputs.version }}
Promote ${{ inputs.environment }} to ${{ inputs.version }}
${{ inputs.environment }}
```

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/promote.yml
git commit -m "ci: promote-parity met Gitea-voorbeeld met behoud van environment-gate"
```

---

### Task 4: Valideren, pushen en PR naar main

**Files:**
- Geen inhoudelijke wijzigingen (git-operaties + API-stappen op branch `ci/github-parity-gitea`).

**Interfaces:**
- Consumes: Tasks 1–3 (drie workflow-commits op de feature-branch).
- Produces: gemergde parity op `main`; geen clusterwijziging (workflows-only PR → alle jobs draaien, `publish`/`update-image-tag` skippen op PR-event zoals bewezen in PR #61-patroon).

- [ ] **Step 1: Volledige lokale validatie**

Run:
```bash
yamllint .github/workflows/ci.yml .github/workflows/cd.yml .github/workflows/promote.yml; echo "exit=$?"
```
Expected: `exit=0`, per bestand alleen de 2 bekende warnings.

Run (bewijst dat er geen Gitea-artefacten zijn gelekt):
```bash
grep -rn "ubuntu-latest" .github/workflows/ && echo "LEK" || echo "OK: geen ubuntu-latest"; grep -rn "REGISTRY_HOST" .github/workflows/ && echo "LEK" || echo "OK: geen REGISTRY_HOST"; grep -rn '"Do":"merge"' .github/workflows/ && echo "LEK" || echo "OK: geen Gitea auto-merge"; grep -rn "runs-on: \[self-hosted\]" .github/workflows/
```
Expected: twee keer `OK`, geen `LEK`, en 7 regels `runs-on: [self-hosted]` (3 in ci, 3 in cd, 2 in promote — validate + promote).

- [ ] **Step 2: Push branch en open PR**

Run:
```bash
git push -u origin ci/github-parity-gitea
```
Expected: branch zichtbaar via `git ls-remote origin ci/github-parity-gitea`.

Open daarna de PR `ci/github-parity-gitea` → `main` (titel `ci: GitHub-workflows parity met Gitea-voorbeeld`, body vermeldt: paths-ignore-breaker, PR-lookup zonder auto-merge, behoud van self-hosted/secrets/environment). Niet mergen vóór Step 3.

- [ ] **Step 3: Bevestig checks en merge**

Expected op de PR: `Change detection` ✅ (workflows geraakt → `workflows=true`), `Test (.NET)` ✅, `Security scan` ✅, `Version` ✅ (bestaat als verplichte check op PR-niveau); `Publish image` en `Update image tag` correct geskipt (push-only keten). PR `mergeable: clean`, branch up-to-date met `main` (strict-beleid).

Merge via GitHub-UI of API, verwijder daarna lokaal en remote op:
```bash
git checkout main && git pull && git fetch --prune origin && git branch -d ci/github-parity-gitea && git status --short
```
Expected: `main` op merge-commit, `git status --short` leeg.

---

## Self-Review

**1. Spec coverage:** CI-breaker (`path-triggers-design` sectie 2 + `image-tag-update-design` loop-breaker, nu per-env) → Task 1. Robuuste PR-open met `already exists`-tolerantie (`cd-promotion-design` sectie 3: "bestaande PR hergebruiken") → Tasks 2–3. GitHub-gates (`cd-promotion-design` sectie 1–2: `environment:` + menselijke merge) → Task 3 behoudt `environment`, Task 2–3 slaan Gitea auto-merge bewust over. Secrets-conventie (`gitea-publish-design` sectie 3: `GITEA_*`) → Global Constraints + Task 3. Geen openstaande eis zonder task.

**2. Placeholder scan:** geen `TBD`/`TODO`, geen "voeg validatie toe" zonder commando, geen "zoals Task N" zonder herhaalde code — elke stap bevat exacte YAML/commando's plus `Expected`.

**3. Type consistency:** env-sleutels `API`/`REPO`/`TOKEN` en output `pr_number` identiek in Task 2 en 3; `BRANCH`-vormen (`ci/image-tag-update`, `ci/promote-<env>-<versie>`) ongewijzigd; `run-name` en job-`name` in Task 3 gebruiken beide `${{ inputs.environment }} to ${{ inputs.version }}`.
