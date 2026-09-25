# Manual prd-promote Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatiseer CI/CD t/m `dev`; `prd`-promotie alleen via handmatige dispatch met project + versie.

**Architecture:** Centraal (`bergconnect/cicd-workflows`, tag `v6`): push-keten beperken tot `dev` via nieuwe input, registry-validatie toevoegen aan dispatch-pad. Lokaal (`LearnCICD`): pins `@v5` → `@v6`, promote-docs, bewijsronde.

**Tech Stack:** GitHub Actions (reusable workflows, `workflow_dispatch`), skopeo/crane, SealedSecrets-ongevoelig (geen secret-wijziging), ArgoCD.

## Global Constraints

- Max 80 tekens per regel in workflows/actions; `run: >` (NOOIT `run: |` bij multi-line `$(...)`).
- Caller-workflows: géén top-level `concurrency`, géén job `name:`; `secrets: inherit`.
- Nooit versies mixen: na `v6` moet `grep -rn "cicd-workflows/.github/actions/" .github/workflows/ | grep -v "@v6"` leeg zijn (zelfde voor `workflows/`-refs).
- `yamllint`: alleen `missing document start` + `truthy` op `on:` zijn oké.
- NOOIT direct naar `main`: feature-branch + PR, conventionele commits, `m_state: clean` vóór merge.
- Zwevende major-tag `v6` wordt verplaatst (nooit oude tags herschrijven behalve de zwevende major).

---

## File Structure

Centraal (na `git clone https://github.com/bergconnect/cicd-workflows.git`):

- `.github/workflows/cd-template.yml` — push-keten + dispatch-pad (Task 1, 2)
- `.github/actions/<bump-actie>/action.yml` — ongewijzigd hergebruik (alleen lezen ter bevestiging)

Lokaal (`LearnCICD`):

- `.github/workflows/cd.yml:40` — pin `cd-template.yml@v5` → `@v6` (Task 4)
- `.github/workflows/ci.yml:16` — pin `ci-template.yml@v5` → `@v6` (Task 4)
- `docs/nieuwe-service.md` — promote-paragraaf (Task 5)

---

### Task 1: Centraal — push-keten beperken tot dev via `auto-environments`

**Files:**
- Modify (centraal): `.github/workflows/cd-template.yml` (nieuwe `workflow_call`-input + `if:`-gate op prd-promote-job)

**Interfaces:**
- Consumes: niets (eerste taak)
- Produces: input `auto-environments` (type string, default `'["dev"]'`, JSON-lijst van env-namen die de push-keten automatisch doorloopt)

- [ ] **Step 1: Clone centrale repo en lees template**

```bash
git clone https://github.com/bergconnect/cicd-workflows.git /tmp/opencode/cicd-wf
```

Lees daarna VOLLEDIG: `/tmp/opencode/cicd-wf/.github/workflows/cd-template.yml`.
Noteer: (a) de exacte job-naam van de prd-promote-job, (b) de bestaande
`if:`-conditie op die job (dispatch vs push), (c) het `inputs:`-blok van
`workflow_call`.

- [ ] **Step 2: Voeg `auto-environments`-input toe**

In het `on.workflow_call.inputs:`-blok, na de laatste bestaande input:

```yaml
    auto-environments:
      description: >
        JSON-lijst van omgevingen die de push-keten automatisch
        doorloopt (default alleen dev)
      required: false
      default: '["dev"]'
      type: string
```

- [ ] **Step 3: Gate de prd-promote-job op de push-keten**

Vind de prd-promote-job uit Step 1. Breid zijn `if:` uit zodat hij bij
`github.event_name == 'push'` alleen draait als `'prd'` in
`auto-environments` staat, en bij `workflow_dispatch` ongewijzigd
doordraait. Patroon (aanpassen aan exacte bestaande conditie):

```yaml
if: >
  github.event_name == 'workflow_dispatch' ||
  (github.event_name == 'push' &&
   contains(fromJSON(inputs.auto-environments), 'prd'))
```

De dev-promote-job blijft ongewijzigd (default `["dev"]` dekt hem).

- [ ] **Step 4: Valideer syntax en commit**

```bash
yamllint .github/workflows/cd-template.yml   # alleen 2 bekende warnings oké
git add .github/workflows/cd-template.yml
git commit -m "feat: auto-environments begrenst push-keten tot dev"
```

Verwacht: commit lukt, geen yamllint-errors. NIET pushen (eerst Task 2).

---

### Task 2: Centraal — registry-validatie in dispatch-pad

**Files:**
- Modify (centraal): `.github/workflows/cd-template.yml` (nieuwe validatie-step vóór bump in dispatch-pad)

**Interfaces:**
- Consumes: Task 1 (werkboom met `auto-environments`-commit)
- Produces: dispatch faalt vóór elke git-mutatie bij onbekende versie

- [ ] **Step 1: Vind dispatch bump-job**

Lees in `/tmp/opencode/cicd-wf/.github/workflows/cd-template.yml` de job
die bij `workflow_dispatch` de image-tag bumpt (bump-composite-aanroep).
Noteer de step náám direct vóór de bump-step en de beschikbare
inputs-namen (`dispatch-project`, `dispatch-version`, registry-host).

- [ ] **Step 2: Voeg validatie-step in vóór de bump**

```yaml
      - name: Valideer versie in registry
        run: >
          skopeo inspect
          --tls-verify=false
          docker://${{ inputs.registry-host }}/${{ inputs.repository }}/${{ inputs.dispatch-project }}:${{ inputs.dispatch-version }}
          > /dev/null
```

Eis: deze step staat vóór ELKE step die git muteert of PRs aanmaakt
in dezelfde job. SemVer2-vorm wordt al afgevangen door de bestaande
input-validatie; zo niet, voeg toe:
`[[ "${{ inputs.dispatch-version }}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]`.

- [ ] **Step 3: Valideer en commit**

```bash
yamllint .github/workflows/cd-template.yml   # alleen 2 bekende warnings oké
git add .github/workflows/cd-template.yml
git commit -m "feat: valideer dispatch-versie in registry vóór bump"
```

Verwacht: yamllint schoon. NIET pushen (eerst Task 3).

---

### Task 3: Centraal — review, push, tag v6

**Files:**
- Geen (git-operaties op `/tmp/opencode/cicd-wf`)

**Interfaces:**
- Consumes: Task 1 + 2 (twee commits op centrale branch)
- Produces: centrale tag `v6` met beide features; `main` bevat ze

- [ ] **Step 1: Review diff**

```bash
git log --oneline -3 && git diff origin/main --stat
```

Verwacht: exact 2 eigen commits, alleen
`.github/workflows/cd-template.yml` gewijzigd.

- [ ] **Step 2: Push via PR en merge**

Maak een branch + PR aan in `bergconnect/cicd-workflows` (conventionele
titel, bv. `feat: auto t/m dev, handmatige prd-promotie`), wacht tot
checks groen zijn, merge. (Centrale repo valt onder dezelfde PR-regels.)

- [ ] **Step 3: Verplaats tag v6**

```bash
git fetch origin && git checkout origin/main
git tag -f v6 origin/main && git push -f origin v6
git ls-remote --tags origin | grep -E "v6$"
```

Verwacht: `v6` wijst naar de merge-commit van Step 2.

---

### Task 4: Lokaal — pins naar @v6 + PR

**Files:**
- Modify: `.github/workflows/cd.yml:40` (`cd-template.yml@v5` → `@v6`)
- Modify: `.github/workflows/ci.yml:16` (`ci-template.yml@v5` → `@v6`)

**Interfaces:**
- Consumes: Task 3 (`v6` bestaat centraal)
- Produces: LearnCICD draait volledig op `@v6`, geen gemixte refs

- [ ] **Step 1: Nieuwe branch vanaf origin/main**

```bash
git fetch origin && git checkout -b chore/pin-cicd-v6 origin/main
```

- [ ] **Step 2: Pins omzetten**

Twee exacte edits (`@v5` → `@v6`, alleen op de twee `uses:`-regels).
Daarna bewijsvoering:

```bash
grep -rn "cicd-workflows/.github/workflows/.*@v5" .github/workflows/ && echo MIX-GEVONDEN || echo "pins schoon"
grep -rn "cicd-workflows/.github/actions/" .github/workflows/ | grep -v "@v6" && echo MIX-GEVONDEN || echo "actions schoon"
```

Verwacht: tweemaal `schoon`.

- [ ] **Step 3: Commit, push, PR**

```bash
git add .github/workflows/cd.yml .github/workflows/ci.yml
git commit -m "chore: pin cicd-workflows op v6 (auto t/m dev)"
git push -u origin chore/pin-cicd-v6
```

Maak PR `chore: pin cicd-workflows op v6` aan (base `main`), wacht
`m_state: clean`. NIET laten mergen vóór Task 5 (docs-commit komt
op dezelfde PR erbij).

---

### Task 5: Lokaal — promote-paragraaf in docs

**Files:**
- Modify: `docs/nieuwe-service.md` (nieuwe paragraaf; eerst het bestand lezen en de bestaande structuur volgen)

**Interfaces:**
- Consumes: Task 4 (PR open en clean; docs-commit komt op dezelfde branch vóór merge)
- Produces: gedocumenteerde handmatige prd-promotie; daarna mag de PR gemerged worden

- [ ] **Step 1: Lees docs/nieuwe-service.md**

Lees het VOLLEDIGE bestand. Noteer waar de CD-stappen staan en welke
stijl (nummering, code-blokken) gebruikt wordt.

- [ ] **Step 2: Voeg promote-paragraaf toe**

Inhoud (aanpassen aan gevonden structuur, max 80-koloms n.v.t. voor md):
hoe de `CD`-workflow handmatig starten (Actions-tab → `CD` →
`Run workflow`, velden `project` + `version`, `environment: prd`),
hoe de versie te kiezen (laatste dev-tag uit `.infra/<chart>/values_dev.yaml`;
downgrade alleen bewust), en wat er daarna gebeurt (validatie → auto-PR
→ automerge → ArgoCD synct prd).

- [ ] **Step 3: Commit op dezelfde branch**

```bash
git add docs/nieuwe-service.md
git commit -m "docs: handmatige prd-promotie beschrijven"
git push origin chore/pin-cicd-v6
```

Verwacht: PR bevat nu 2 commits (pins + docs).

---

### Task 6: Bewijsronde — auto dev + handmatige prd

**Files:**
- Geen (live verificatie; tijdelijke probe-artefacten volledig opruimen)

**Interfaces:**
- Consumes: Task 4 + 5 gemerged (main draait `@v6`)
- Produces: bewezen keten end-to-end + pull-bewijs in `prd`

- [ ] **Step 1: Probe-PR voor auto dev-deploy**

Maak een minimale probe-wijziging (bv. comment in `src/Api`), PR,
merge. Wacht op CD-run: CI groen → publish → dev-bump-PR → automerge.
Noteer de nieuwe dev-versie `V` uit `.infra/learncicd/values_dev.yaml`
op `main`.

- [ ] **Step 2: Handmatige prd-dispatch van V**

Actions-tab → `CD` → `Run workflow`: `project=Api` (of `api`,
exacte project-key uit `.github/projects.json`), `environment=prd`,
`version=V`. Wacht: validatie groen → prd-bump-PR → automerge.

- [ ] **Step 3: Pull-bewijs in prd**

```bash
ssh 192.168.2.46 'kubectl -n prd get pods -o wide | head -5'
```

Wacht tot de prd-pod de nieuwe image draait (`V` in image-tag),
status Running. Bij twijfel over auth: herhaal de
onbestaande-tag-test uit de vorige sessie (verwacht `not found`,
geen 401).

- [ ] **Step 4: Ruim probe op**

Revert de probe-wijziging via nieuwe PR (geen direct push),
zodat `main` schoon achterblijft.

---

### Task 7: Afronding

**Files:**
- Geen

**Interfaces:**
- Consumes: Task 6 (bewijs compleet)
- Produces: schone repo, gesloten PRs

- [ ] **Step 1: Verifieer eindstand**

```bash
git checkout main && git pull -q origin main && git status --short
grep -rn "@v5" .github/workflows/ && echo OUD-GEVONDEN || echo "geen oude pins"
```

Verwacht: lege status, geen oude pins.

- [ ] **Step 2: Ruim branches op**

```bash
git branch -D chore/pin-cicd-v6
rm -rf /tmp/opencode/cicd-wf
```

- [ ] **Step 3: Rapporteer**

Meld: spec + plan gemerged, keten bewezen (dev-versie `V`,
prd-promotie-run-id, pull-bewijs), resterende minors (OutOfSync-cosmetica,
SealedSecret-template-watch).
