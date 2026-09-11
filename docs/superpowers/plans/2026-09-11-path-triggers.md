# Path Triggers per Job Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Laat CI-jobs alleen draaien bij relevante pad-wijzigingen via een `changes`-job met `git diff`-classificatie, zonder de mergebaarheid te breken.

**Architecture:** Beide workflows krijgen vooraan een `changes`-job (full-history checkout, PR- én push-bewuste diff, drie outputs) en elke bestaande job krijgt `needs: [changes]` plus een `if:` op de outputs — behalve `publish`/`update-image-tag`, die transitief volgen via `needs: [version]`. Daarna validatie via PR (alles groen, want workflows geraakt) plus merge, gevolgd door een docs-only proef-PR die bewijst dat geskipte checks de merge niet blokkeren. Alle mechanismen hieronder zijn op 2026-09-11 lokaal bewezen: glob-semantiek per categorie (geneste `.csproj` matcht, onbekend → `code`), `yamllint`-veilige regellengtes en YAML-folding.

**Tech Stack:** POSIX `git diff`/`case`/`grep` (geen extra actions — `yq`/`dorny` niet nodig), job-`outputs` + `needs` + `if: >`-folding, bestaande `checkout@v4`/`setup-dotnet@v4`.

## Global Constraints

- `changes`-job exact (`name: Change detection`): `runs-on: [self-hosted]`, `timeout-minutes: 5`, `permissions: contents: read` (verplicht — top-level `permissions: {}` staat alles uit), `checkout` met `fetch-depth: 0`, classificatie-stap met `id: classify`, outputs `code`/`workflows`/`docs` (exacte inhoud hieronder).
- Diff-basis exact: op `pull_request` → `git diff --name-only origin/main...HEAD`; op `push` → `git diff --name-only $BASE_SHA $HEAD_SHA` met step-`env` (`BASE_SHA: ${{ github.event.before }}`, `HEAD_SHA: ${{ github.sha }}`).
- Classificatie exact (eerste match wint; `charts/*|argocd/*` is een expliciete no-op-groep zodat chart-only géén tests triggert; `*` valt terug op `code=true` fail-safe). Afwijking t.o.v. spec-tekst genoteerd: spec noemt `charts` niet, maar het spec-voorbeeld ("chart-only PR → geskipt") eist deze tak — bij oplevering melden voor eventuele spec-touch-up.
- Job-`if`s exact als `if: >`-gevouwen OR-vorm (`needs.changes.outputs.<groep> == 'true'`); `test` + `security`: `code OR workflows`; `version`: `code OR workflows`; `publish`/`update-image-tag`: géén eigen `if` (transitief via `needs`). Bestaande event-`if`s, `needs`-ketens, `paths-ignore` en alle stappen blijven staan.
- `yamllint` exit 0 met hooguit de 2 bekende warnings; geen regels >80 (lange condities alleen via `if: >`-folding).
- Werk op feature-branch `feat/path-triggers`; merge naar `main` uitsluitend via PR met groene checks (branch protection); conventionele commits.

---

## File Structure

| Bestand | Verantwoordelijkheid |
|---|---|
| `.github/workflows/ci.yml` | `changes`-job + `needs`/`if` op `test` + `security` |
| `.github/workflows/cd.yml` | `changes`-job + `needs`/`if` op `version` (`publish`/`update` transitief) |
| `AGENTS.md` | Eén conventie-regel over skip-gedrag (alleen Task 4) |

Al het andere blijft onaangeraakt.

---

### Task 1: changes-job + gates in ci.yml

**Files:**
- Modify: `.github/workflows/ci.yml` (`changes`-job vooraan; `needs` + `if` op `test` + `security`)

**Interfaces:**
- Consumes: bestaande CI-jobs (ongewijzigd op `needs`/`if` na).
- Produces: pad-bewuste CI. Task 3 valideert op GitHub (PR raakt workflows → alles groen).

- [ ] **Step 1: Insert the `changes` job as first job (direct onder `jobs:`)**

```yaml
  changes:
    name: Change detection
    runs-on: [self-hosted]
    timeout-minutes: 5
    permissions:
      contents: read
    outputs:
      code: ${{ steps.classify.outputs.code }}
      workflows: ${{ steps.classify.outputs.workflows }}
      docs: ${{ steps.classify.outputs.docs }}
    steps:
      - name: Check out code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Classify changed paths
        id: classify
        env:
          BASE_SHA: ${{ github.event.before }}
          HEAD_SHA: ${{ github.sha }}
        run: >
          if [ "${{ github.event_name }}" = "pull_request" ]; then
          FILES=$(git diff --name-only origin/main...HEAD);
          else
          FILES=$(git diff --name-only $BASE_SHA $HEAD_SHA);
          fi;
          CODE=false; WORKFLOWS=false; DOCS=false;
          while IFS= read -r f; do
          case "$f" in
            src/*|tests/*|*.csproj|Dockerfile|Dockerfile.*)
            CODE=true;;
            global.json|.config/*|version.json)
            CODE=true;;
            .github/*)
            WORKFLOWS=true;;
            charts/*|argocd/*)
            :;;
            docs/*|*.md|.gitignore|LICENSE)
            DOCS=true;;
            *)
            CODE=true;;
          esac;
          done <<< "$FILES";
          echo "code=$CODE" >> "$GITHUB_OUTPUT";
          echo "workflows=$WORKFLOWS" >> "$GITHUB_OUTPUT";
          echo "docs=$DOCS" >> "$GITHUB_OUTPUT"
```

- [ ] **Step 2: Gate the `test` job**

Voeg in de `test`-job direct na het `permissions:`-blok toe:

```yaml
    needs: [changes]
    if: >
      needs.changes.outputs.code == 'true' ||
      needs.changes.outputs.workflows == 'true'
```

- [ ] **Step 3: Gate the `security` job**

Zelfde twee regels, direct na het `permissions:`-blok van de `security`-job:

```yaml
    needs: [changes]
    if: >
      needs.changes.outputs.code == 'true' ||
      needs.changes.outputs.workflows == 'true'
```

- [ ] **Step 4: Dry-run the classification logic locally**

Run (exacte `case` uit Step 1, drie scenario's):

```bash
check() {
  CODE=false; WORKFLOWS=false; DOCS=false
  while IFS= read -r f; do
    case "$f" in
      src/*|tests/*|*.csproj|Dockerfile|Dockerfile.*) CODE=true;;
      global.json|.config/*|version.json) CODE=true;;
      .github/*) WORKFLOWS=true;;
      charts/*|argocd/*) :;;
      docs/*|*.md|.gitignore|LICENSE) DOCS=true;;
      *) CODE=true;;
    esac
  done
  echo "code=$CODE workflows=$WORKFLOWS docs=$DOCS"
}
printf 'docs/x.md\nAGENTS.md\n' | check
printf 'src/Api/Program.cs\n' | check
printf 'charts/learncicd/values.yaml\n' | check
```

Expected, in volgorde: `code=false workflows=false docs=true`; `code=true workflows=false docs=false`; `code=false workflows=false docs=false`.

- [ ] **Step 5: Validate YAML and commit**

Run:

```bash
yamllint .github/workflows/ci.yml; echo "exit=$?"
```

Expected: `exit=0`, hooguit de twee bekende warnings.

Run:

```bash
git add .github/workflows/ci.yml
git commit -m "ci: gate test and security jobs on changed paths"
```

### Task 2: changes-job + gate in cd.yml

**Files:**
- Modify: `.github/workflows/cd.yml` (`changes`-job vooraan; `needs` + `if` op `version`)

**Interfaces:**
- Consumes: bestaande CD-jobs (ongewijzigd op `needs`/`if` na).
- Produces: pad-bewuste CD (`publish`/`update-image-tag` volgen transitief via `needs: [version]`). Task 3 valideert op GitHub.

- [ ] **Step 1: Insert the identical `changes` job as first job**

Zelfde blok als Task 1, Step 1 (byte-identiek — kopieer het; beide workflows delen de snippet bewust).

- [ ] **Step 2: Gate the `version` job**

Voeg in de `version`-job direct na het bestaande blok (vóór `outputs:`) toe:

```yaml
    needs: [changes]
    if: >
      needs.changes.outputs.code == 'true' ||
      needs.changes.outputs.workflows == 'true'
```

(`publish` houdt `needs: [version]`, `update-image-tag` houdt `needs: [publish, version]` — beide zonder eigen `if`; skipt `version`, dan skippen zij mee.)

- [ ] **Step 3: Validate YAML and commit**

Run:

```bash
yamllint .github/workflows/cd.yml; echo "exit=$?"
```

Expected: `exit=0`, hooguit de twee bekende warnings.

Run:

```bash
git add .github/workflows/cd.yml
git commit -m "ci: gate version job on changed paths"
```

### Task 3: Valideren via GitHub-PR en mergen

**Files:**
- Geen (git-operaties + API-stappen)

**Interfaces:**
- Consumes: Task 1 + 2 op branch `feat/path-triggers` (schoon, gepusht) — een PR die workflows raakt, dus `workflows=true` en alles draait.
- Produces: groene CI op PR als bewijs; `main` bevat de wijziging na merge; branches opgeruimd. Task 4 bewijst het skip-gedrag.

- [ ] **Step 1: Push and open a PR `feat/path-triggers` → `main`**

Run:

```bash
git push -u origin feat/path-triggers
```

Open daarna de PR (github.com of API). Titel: `ci: gate jobs on changed paths`. Niet mergen vóór Step 3.

- [ ] **Step 2: Confirm PR checks (alles hoort te draaien)**

Expected op de PR: `Test (.NET)` ✅, `Version` ✅, `Security scan` ✅ (`Docker build` bestaat niet meer; `Publish image` + `Update image tag` **skipped** — event is `pull_request`, correct gedrag). In `Change detection`-logs staat `workflows=true` (deze PR raakt `.github/**`).

- [ ] **Step 3: Merge and clean up**

Merge de PR via GitHub, verwijder de remote branch, daarna lokaal:

```bash
git checkout main
git pull
git fetch --prune origin
git branch -d feat/path-triggers
git log --oneline -3
```

Expected: `main` bevat de twee workflow-commits plus merge; `git status --short` leeg.

### Task 4: Docs-only proef-PR (skip-bewijs + mergebaarheid)

**Files:**
- Modify: `AGENTS.md` (één conventie-regel toevoegen — echte inhoud, geen vulling)

**Interfaces:**
- Consumes: Task 3 gemergd op `main` (gates actief).
- Produces: bewijs dat geskipte verplichte checks de merge niet blokkeren; `main` bevat de regel na merge; branches opgeruimd.

- [ ] **Step 1: Add one convention line and open a docs-only PR**

Voeg aan het einde van de conventie-lijst in `AGENTS.md` toe:

```markdown
- Docs-only wijzigingen skippen CI-jobs via de `changes`-job; geskipte checks blokkeren de merge niet.
```

Run:

```bash
git checkout -b docs/skip-proof
git add AGENTS.md
git commit -m "docs: note that docs-only changes skip CI jobs"
git push -u origin docs/skip-proof
```

Open daarna de PR (github.com of API). Titel: `docs: prove skipped checks stay mergeable`.

- [ ] **Step 2: Confirm skips and mergeability**

Expected op de PR: `Test (.NET)`, `Version`, `Security scan` alle drie **skipped** (alleen `docs/**` + `*.md` geraakt), en de PR toch **mergebaar** (geen blokkade op verplichte checks). Lees in de `Change detection`-log dat alleen `docs=true` staat.

- [ ] **Step 3: Merge and clean up**

Merge de PR via GitHub, verwijder de remote branch, daarna lokaal:

```bash
git checkout main
git pull
git fetch --prune origin
git branch -d docs/skip-proof
git log --oneline -3
```

Expected: `main` bevat beide merges; `git status --short` leeg; `git branch -a` toont alleen `main` + `origin/main` (+ PR-refs).
