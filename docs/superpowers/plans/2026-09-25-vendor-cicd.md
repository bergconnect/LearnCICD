# Vendor cicd-workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vendor de 6 centrale workflows/actions naar LearnCICD (harde fork) en wijs callers naar lokale kopieën.

**Architecture:** Byte-identieke kopie van centrale `main`-stand plus mechanische ref-herschrijving (extern→lokaal relatief); één PR; CI + rookproofs als bewijs. Centraal onaangeroerd.

**Tech Stack:** GitHub Actions (reusable workflows `uses: ./.github/...`, composite actions `uses: ../actions/...`), yamllint, GitHub API (geen `gh` CLI).

## Global Constraints

- Max 80 tekens per regel in workflows/actions; `run: >` (NOOIT `run: |` bij multi-line `$(...)`).
- Caller-workflows: géén top-level `concurrency`, géén job `name:`; `secrets: inherit`.
- Nooit versies mixen: na deze PR mag `grep -rn "bergconnect/cicd-workflows" .github/` NIETS meer vinden (geen enkele `@v`-ref over).
- `yamllint`: alleen `missing document start` + `truthy` op `on:` zijn oké.
- NOOIT direct naar `main`: feature-branch + PR, conventionele commits, `m_state: clean` vóór merge.
- Centraal (`bergconnect/cicd-workflows`): GEEN commits, GEEN tags, GEEN branches daar.

---

## File Structure

Te creëren (kopie van centrale `main`-stand op implementatiemoment —
leg de centrale HEAD-SHA vast in het implementatie-rapport):

- `.github/actions/bump-image-tag/action.yml`
- `.github/actions/detect-changed-projects/action.yml`
- `.github/actions/dotnet-setup/action.yml`
- `.github/workflows/cd-dev-template.yml`
- `.github/workflows/ci-template.yml`
- `.github/workflows/promote-template.yml`

Te wijzigen (zelfde branch, zelfde PR):

- `.github/workflows/cd.yml` — `uses:` → `./cd-dev-template.yml`
- `.github/workflows/ci.yml` — `uses:` → `./ci-template.yml`
- `.github/workflows/promote.yml` — `uses:` → `./promote-template.yml`
- `.github/projects.json:15` — `select-all` + `.github/workflows/promote-template.yml`

---

### Task 1: Bestanden overnemen van centrale main

**Files:**
- Create: alle 6 hierboven (exacte paden)

**Interfaces:**
- Consumes: niets (eerste taak)
- Produces: 6 lokale bestanden, nog met centrale refs (herschrijving = Task 2); centrale HEAD-SHA in rapport

- [ ] **Step 1: Branch + centrale stand vastleggen**

```bash
git fetch origin && git checkout -b feat/vendor-cicd origin/main
git ls-remote https://github.com/bergconnect/cicd-workflows.git HEAD
```

Noteer de centrale HEAD-SHA (40 hex) in het rapport — dat is de
bevroren bronversie.

- [ ] **Step 2: Kopieer de 6 bestanden**

```bash
mkdir -p /tmp/opencode/cicd-src && git clone -q https://github.com/bergconnect/cicd-workflows.git /tmp/opencode/cicd-src
for f in actions/bump-image-tag/action.yml actions/detect-changed-projects/action.yml actions/dotnet-setup/action.yml workflows/cd-dev-template.yml workflows/ci-template.yml workflows/promote-template.yml; do cp "/tmp/opencode/cicd-src/.github/$f" ".github/$f"; done
git status --short
```

Verwacht: exact 6 nieuwe bestanden (`??`), niets anders.
Nog NIET committen (Task 2 wijzigt dezelfde bestanden).

---

### Task 2: Ref-herschrijving extern → lokaal

**Files:**
- Modify: alle 6 nieuwe bestanden (alleen `uses:`-regels)
- Modify: `.github/workflows/cd.yml`, `ci.yml`, `promote.yml` (alleen `uses:`-regels)

**Interfaces:**
- Consumes: Task 1 (6 bestanden aanwezig)
- Produces: nul `bergconnect/cicd-workflows`-refs in `.github/`; alles lokaal relatief

- [ ] **Step 1: Interne refs in templates/actions**

In de 3 GEKOPIEERDE templates: elke
`bergconnect/cicd-workflows/.github/actions/<a>@<tag>` →
`../actions/<a>` (tag vervalt; relatieve vorm vanuit
`.github/workflows/`). Zoek EERST alle occurrences:

```bash
grep -rn "bergconnect/cicd-workflows" .github/actions/ .github/workflows/cd-dev-template.yml .github/workflows/ci-template.yml .github/workflows/promote-template.yml
```

Herschrijf ze één voor één (zelfde aantal regels voor/na;
alleen de `uses:`-waarde verandert).

- [ ] **Step 2: Caller-refs**

In `cd.yml`, `ci.yml`, `promote.yml`: elke
`bergconnect/cicd-workflows/.github/workflows/<f>@<tag>` →
`./<f>` (relatieve vorm vanuit `.github/workflows/`).
Niets anders in deze bestanden wijzigen (permissions, `with:`,
`secrets:`, jobs blijven identiek).

- [ ] **Step 3: Nul-proof + yamllint + commits**

```bash
grep -rn "bergconnect/cicd-workflows" .github/ && echo LEK || echo "refs schoon"
yamllint .github/workflows/ .github/actions/   # alleen 2 bekende warnings oké
git add -A && git commit -m "feat: vendor cicd-workflows lokaal (harde fork)"
```

Verwacht: `refs schoon`; yamllint zonder nieuwe findings;
één commit met 6 nieuwe + 3 gewijzigde bestanden.
NIET pushen (Task 3 hoort bij dezelfde PR).

---

### Task 3: Tracking + PR

**Files:**
- Modify: `.github/projects.json:15` (`select-all`)

**Interfaces:**
- Consumes: Task 2 (commit op branch `feat/vendor-cicd`)
- Produces: PR, `m_state: clean`, NIET zelf mergen

- [ ] **Step 1: promote-template toevoegen aan select-all**

`select-all` bevat al `ci-template.yml` en `cd-dev-template.yml`
(die bestonden lokaal nog niet — nu wel). Alleen
`.github/workflows/promote-template.yml` ontbreekt nog; toevoegen
achter `promote.yml`. Niets anders wijzigen. Valideer JSON:

```bash
python3 -c "import json; d=json.load(open('.github/projects.json')); print([p for p in d['_global']['select-all'] if 'template' in p])"
git add .github/projects.json && git commit -m "feat: tracking voor promote-template"
```

- [ ] **Step 2: Push + PR + wachten**

```bash
git push -u origin feat/vendor-cicd
```

PR `feat: vendor cicd-workflows lokaal (harde fork)` (base `main`),
wacht `m_state: clean` (poll 45–60s). NIET mergen (owner).
Docs checken: `grep -rn "cicd-workflows" docs/nieuwe-service.md AGENTS.md`
moet leeg zijn (was leeg bij plan-schrijven; zo niet, alsnog
aanpassen in een extra commit op dezelfde branch).

---

### Task 4: Rookproef na merge + cleanup

**Files:** Geen (live verificatie; vereist gemergde PR uit Task 3)

**Interfaces:**
- Consumes: Task 3 gemerged (main zonder centrale refs)
- Produces: bewezen lokale resolutie; schone repo

- [ ] **Step 1: Negatieve Promote-dispatch**

Actions-tab → `Promote` → Run workflow (`project=Api`,
`version=0.0.0-niet-bestaand`, `environment=acc`). Verwacht: run
rood op validatie, GEEN PR. Noteer run-ID. (Bewijst: lokale
`promote-template` + lokale `bump`-actie resolven.)

- [ ] **Step 2: Bestaande versie als rookproef**

Dispatch `project=Api`, `version=<dev-tag uit origin/main:.infra/learncicd/values_dev.yaml>`,
`environment=acc`. Verwacht: success (idempotent, geen PR bij
gelijke tag). Noteer run-ID.

- [ ] **Step 3: Eindcontrole + opruimen**

```bash
git checkout main && git pull -q origin main && git status --short
grep -rn "bergconnect/cicd-workflows" .github/ && echo LEK || echo "refs schoon"
git branch -D feat/vendor-cicd
rm -rf /tmp/opencode/cicd-src
```

Verwacht: lege status, `refs schoon`, branch weg.
Rapporteer: beide run-IDs + uitkomsten, centrale HEAD-SHA
(bevroren bron), resterende minors.
