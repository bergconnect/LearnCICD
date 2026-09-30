# CD env-gates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CD-template deployt sequentieel dev (auto) → acc (gate) → prd (gate); Promote-workflow verdwijnt.

**Architecture:** `cd-dev-template.yml` hernoemd naar `cd-template.yml` + twee nieuwe matrix-jobs (`promote-acc`, `promote-prd`) als kopie van `update-tag` plus copy-stap; `environment:` per job dwingt de gate af via het platform. Reviewers-namen volgen later (overgang: gate zonder wachters).

**Tech Stack:** GitHub Actions (reusable workflows, environments, matrices), skopeo, bump-image-tag-composite, GitHub API (geen `gh` CLI).

## Global Constraints

- Max 80 tekens per regel in workflows/actions; `run: >` (NOOIT `run: |` bij multi-line `$(...)`).
- Caller-workflows: géén top-level `concurrency`, géén job `name:`; `secrets: inherit`.
- Template-jobs MOGEN `name:`, eigen `concurrency`, `environment:` hebben (bestaand patroon).
- Composites erven GEEN secrets: `token`/`gpg-key`/`key-id` ALTIJD expliciet.
- `yamllint`: alleen `missing document start` + `truthy` op `on:` zijn oké.
- NOOIT direct naar `main`: feature-branch + PR, conventionele commits, `m_state: clean` vóór merge.
- Centraal (`bergconnect/cicd-workflows`): GEEN commits (vendored, harde fork).
- PR #322 (spec) is open; dit plan hoort erbij (zelfde of nieuwe PR — zie Task 2).

---

## File Structure

- Rename: `.github/workflows/cd-dev-template.yml` → `.github/workflows/cd-template.yml` (git mv, historie behouden)
- Modify: `cd-template.yml` (+2 jobs), `.github/workflows/cd.yml` (`uses:`-regel), `.github/projects.json` (tracking)
- Delete: `.github/workflows/promote.yml`, `.github/workflows/promote-template.yml`
- Geen: bump-composite, charts, values, ArgoCD-manifesten, secrets

---

### Task 1: Hernoem + promote-acc/promote-prd-jobs

**Files:**
- Rename: `.github/workflows/cd-dev-template.yml` → `.github/workflows/cd-template.yml`
- Modify: `cd-template.yml` (2 nieuwe jobs aan het eind)
- Modify: `.github/workflows/cd.yml` (`uses:` → `./cd-template.yml`)
- Modify: `.github/projects.json` (`cd-dev-template.yml` → `cd-template.yml` in `select-all`; `promote-template.yml`-entry VERWIJDEREN)

**Interfaces:**
- Consumes: niets (eerste taak)
- Produces: keten dev→acc→prd op branch (nog zonder reviewers = pass-through); NIET pushen tot Task 2 erbij zit

- [ ] **Step 1: Branch + hernoem**

```bash
git fetch origin && git checkout -b feat/cd-env-gates origin/main
git mv .github/workflows/cd-dev-template.yml .github/workflows/cd-template.yml
```

- [ ] **Step 2: Lees update-tag volledig als mal**

Lees `update-tag` (r178-248 van het HERNOEMDE bestand) regel voor
regel. De twee nieuwe jobs zijn er een kopie van met exact deze
delta's (niets anders):

`promote-acc` (na `update-tag` invoegen):

```yaml
  promote-acc:
    name: Promote to acc
    runs-on: [self-hosted]
    needs: [publish, detect, determine-version, update-tag]
    environment: acc
    if: >
      always() &&
      needs.update-tag.result == 'success' &&
      needs.detect.outputs.matrix != '' &&
      needs.detect.outputs.matrix != '[]' &&
      needs.determine-version.result == 'success'
    timeout-minutes: 10
    permissions:
      contents: write
      pull-requests: write
    strategy:
      fail-fast: false
      matrix:
        release: ${{ fromJSON(needs.detect.outputs.matrix) }}
    env:
      PROJECT: ${{ matrix.release.project }}
      IMAGE_NAME: ${{ matrix.release.image }}
      REGISTRY: ${{ vars.GITEA_LOCAL }}
      REPOSITORY: ${{ vars.GITEA_SOURCE_REPOSITORY }}
      VER_MAP: ${{ needs.determine-version.outputs.versions }}
```

(`needs` KRIJGT `update-tag` erbij (sequentie!); `environment: acc`
is de gate; `if` eist `update-tag == success` (dev geslaagd).)

Steps = kopie van update-tag-steps met deze delta's:
`Set version` identiek; `Check published image exists` identiek;
DAARNA copy-stap overnemen uit `promote-template.yml`
(tag-copy-vorm, GEEN digest-logica — lees dat bestand eerst en
neem de skopeo-copy + DST-env over met `GITEA_DST_TOKEN` en
dest-vars); bump-step via composite met `env-name: acc`,
`branch: ci/promote-<image>-acc-<VER>`-vorm (uniek per env!),
commit/PR-titels met `acc` achteraan (`... to acc`).

`promote-prd`: identiek aan `promote-acc`, met `acc`→`prd`
overal (environment, needs KRIJGT `promote-acc` erbij i.p.v.
`update-tag`, `if` eist `promote-acc == success`, branch/titels
met `prd`).

- [ ] **Step 3: Caller + tracking**

`cd.yml`: `uses:` → `./cd-template.yml` (1 regel, rest identiek).
`projects.json`: `cd-dev-template.yml` → `cd-template.yml`;
`promote-template.yml`-entry verwijderen (bestand verdwijnt in
Task 2). JSON valideren (`python3 -c "import json;..."`).

- [ ] **Step 4: Valideer + commit (niet pushen)**

```bash
yamllint .github/workflows/cd-template.yml   # alleen 2 bekende warnings oké
awk 'length>80 {print FNR": "length}' .github/workflows/cd-template.yml
git add -A && git commit -m "feat: CD-keten dev-acc-prd met env-gates"
```

Verwacht: geen >80-regels, yamllint schoon. NIET pushen
(Task 2 hoort bij dezelfde PR).

---

### Task 2: Promote verwijderen + PR

**Files:**
- Delete: `.github/workflows/promote.yml`, `.github/workflows/promote-template.yml`

**Interfaces:**
- Consumes: Task 1 (zelfde branch `feat/cd-env-gates`)
- Produces: PR, `m_state: clean`, NIET zelf mergen

- [ ] **Step 1: Verwijderen + referentiecheck**

```bash
git rm -q .github/workflows/promote.yml .github/workflows/promote-template.yml
grep -rn "promote-template\|promote\.yml" .github/ docs/nieuwe-service.md AGENTS.md 2>/dev/null; echo "(alleen historische specs/plans mogen overblijven)"
```

Verwacht: geen levende refs (specs/plans onder `docs/superpowers/`
zijn geschiedenis en blijven staan). `docs/nieuwe-service.md`:
als die een promote-paragraaf heeft → herschrijven naar
CD-keten-beschrijving (kleine edit, zelfde commit).

- [ ] **Step 2: Commit + push + PR**

```bash
git add -A && git commit -m "feat: Promote-workflow verwijderd (CD-keten dekt af)"
git push -u origin feat/cd-env-gates
```

PR (base `main`, titel `feat: CD-keten dev-acc-prd met env-gates`),
wacht `m_state: clean`. NIET mergen (owner; Task 3 heeft de merge
nodig).

---

### Task 3: Reviewers + bewijsronde + cleanup

**Files:** Geen (live-acties; vereist gemergde PR uit Task 2)

**Interfaces:**
- Consumes: Task 2 gemerged (keten live op `main`)
- Produces: bewezen keten end-to-end; schone repo

- [ ] **Step 1: Reviewers proberen in te stellen (overgang accepteren)**

Haal EERST de huidige env-JSON op
(`GET /repos/bergconnect/LearnCICD/environments/acc`) en bekijk
`protection_rules`-structuur. Probeer reviewers te zetten conform
die structuur; als user-IDs ontbreken (owner levert later):
NIET blokkeren — rapporteer expliciet `overgangstoestand: gates
zonder wachters (direct door)`. Verander niets anders aan envs.

- [ ] **Step 2: Probe-push en keten volgen**

Triviale Worker-wijziging (1-regel comment), branch
`probe/cd-env-gates`, PR, laat mergen (owner). Volg CD-run:
dev auto (bump-PR → automerge) → `promote-acc` (zonder reviewers:
direct door; MET reviewers: wacht op approve — vraag owner om te
approven en hervat) → `promote-prd` (idem). Noteer run-ID +
versie `V`. Zonder reviewers bewijst groen de BEDRADING;
met reviewers bewijst wachten+approven de GATE (rapporteer welke
van de twee gold).

- [ ] **Step 3: Pod-bewijs alle envs + revert + cleanup**

Pods `dev`/`acc`/`prd` draaien `V` (Running) — zelfde check als
eerdere bewijsrondes per namespace. Revert probe-comment via PR
(schone main). Ruim op:

```bash
git checkout main && git pull -q origin main && git status --short
git branch -D feat/cd-env-gates probe/cd-env-gates 2>/dev/null; true
```

Rapporteer: run-ID, `V`, gate-gedrag (pass-through vs
wacht+approve), pod-staten, resterende minors (reviewer-namen!).
