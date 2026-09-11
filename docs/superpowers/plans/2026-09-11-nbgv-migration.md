# Nerdbank.GitVersioning Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bepaal de versie met Nerdbank.GitVersioning (`version.json`, basis `0.1`) i.p.v. GitVersion, met ongewijzigde `semVer`-job-output richting `publish`.

**Architecture:** `version.json` + repo-local nbgv-tool-manifest toevoegen, `version`-job ombouwen naar `dotnet tool restore` + `nbgv get-version -v SemVer2`, `GitVersion.yml` verwijderen, daarna valideren via PR (checks groen) plus merge (eerste `0.1.x`-image in Gitea als eindbewijs). Alle mechanismen hieronder zijn op 2026-09-11 lokaal bewezen op een kloon van deze repo: `dotnet tool restore` + `dotnet nbgv get-version -v SemVer2` → `0.0.1` vóór commit van `version.json`, `0.1.1` erna (vorm `0.1.<height>`, strikt SemVer, Docker-tag-veilig).

**Tech Stack:** nbgv 3.10.94 (tool-manifest `.config/dotnet-tools.json`), `version.json` (`0.1` + `publicReleaseRefSpec main`), bestaande `Version`-job-vorm (`fetch-depth: 0`, `DOTNET_INSTALL_DIR`, job-`outputs.semVer`).

## Global Constraints

- `version.json` in repo-root bevat exact `{"version": "0.1", "publicReleaseRefSpec": ["^refs/heads/main$"]}` (formattering vrij, inhoud exact).
- Tool-manifest `.config/dotnet-tools.json` pint exact `nbgv` `3.10.94` met command `nbgv` (inhoud hieronder, verbatim).
- `GitVersion.yml` wordt verwijderd (`git rm`); nergens anders in de repo mag nog naar GitVersion verwezen worden (zoek op `gitversion`, hoofdletterongevoelig, en verwijder restanten — verwacht: geen).
- `version`-job behoudt `name: Version`, `runs-on: [self-hosted]`, `fetch-depth: 0`, `DOTNET_INSTALL_DIR`, `setup-dotnet` en job-`outputs.semVer`; alleen de GitVersion-stappen worden vervangen door tool-restore + get-version + display (exacte stappen hieronder).
- Versie-variabele is exact `SemVer2` (strikt SemVer, géén `+metadata` — Docker-tags mogen geen `+` bevatten); job-output blijft `semVer` heten zodat `publish` (`needs.version.outputs.semVer`, tags, `latest`) byte-identiek blijft werken.
- Geen `PackageReference` naar Nerdbank.GitVersioning (geen assembly-stamping — assemblies blijven byte-identiek).
- Alle `dotnet`-commando's lopen vanuit de repo-root (tool-manifest- én `version.json`-ontdekking werken per werkdirectory).
- `yamllint` exit 0 met hooguit de 2 bekende warnings; geen regels >80.
- Werk op feature-branch `feat/nbgv-migration`; merge naar `main` uitsluitend via PR met groene checks (branch protection); conventionele commits.

---

## File Structure

| Bestand | Verantwoordelijkheid |
|---|---|
| `version.json` (nieuw, repo-root) | NB.GV-basisversie + public-release-ref |
| `.config/dotnet-tools.json` (nieuw) | Gepinde nbgv-tool (3.10.94) |
| `.github/workflows/ci.yml` | Alleen `version`-job ombouwen |
| `GitVersion.yml` (verwijderen) | Oude GitVersion-config weg |

`src/*`, tests, `Dockerfile`, `global.json`, `test`/`security`/`publish`-jobs en alle andere workflow-delen blijven onaangeraakt.

---

### Task 1: version.json + tool-manifest (lokaal bewezen)

**Files:**
- Create: `version.json`
- Create: `.config/dotnet-tools.json`

**Interfaces:**
- Consumes: niets (nieuwe bestanden).
- Produces: `dotnet tool restore` + `dotnet nbgv get-version -v SemVer2` geven vanuit repo-root een `0.1.<height>`-versie. Task 2 gebruikt manifest + config in CI.

- [ ] **Step 1: Create `version.json` in repo-root**

```json
{
  "version": "0.1",
  "publicReleaseRefSpec": [
    "^refs/heads/main$"
  ]
}
```

- [ ] **Step 2: Create `.config/dotnet-tools.json`**

```json
{
  "version": 1,
  "isRoot": true,
  "tools": {
    "nbgv": {
      "version": "3.10.94",
      "commands": [
        "nbgv"
      ]
    }
  }
}
```

- [ ] **Step 3: Restore the tool and prove the version locally**

Run (vanuit repo-root):

```bash
dotnet tool restore
dotnet nbgv get-version -v SemVer2
```

Expected: restore exit 0 (`Restore was successful`); get-version exit 0 met output in de vorm `0.1.<height>` (op 2026-09-11 bewezen: `0.1.1` op een kloon met gecommitte `version.json`). Geen `+metadata` in de output.

- [ ] **Step 4: Commit**

Run:

```bash
git add version.json .config/dotnet-tools.json
git commit -m "test: add version.json and pinned nbgv tool manifest"
```

### Task 2: version-job ombouwen (GitVersion eruit, nbgv erin)

**Files:**
- Modify: `.github/workflows/ci.yml` (alleen `version`-job)
- Delete: `GitVersion.yml` (via `git rm`)

**Interfaces:**
- Consumes: Task 1 (`version.json` + manifest aanwezig op de branch).
- Produces: `Version`-check die `semVer` (NB.GV `SemVer2`) logt en als job-output aanbiedt; `publish` blijft ongewijzigd consumeren. Task 3 valideert op GitHub.

- [ ] **Step 1: Replace the GitVersion steps**

In de `version`-job, vervang exact dit blok:

```yaml
      - name: Install GitVersion
        uses: gittools/actions/gitversion/setup@v4
        with:
          versionSpec: '6.x'

      - name: Determine version
        id: version_step
        uses: gittools/actions/gitversion/execute@v4

      - name: Display version
        run: >
          echo "Version ${{ steps.version_step.outputs.semVer }}
          (full: ${{ steps.version_step.outputs.fullSemVer }})"
```

door exact dit blok:

```yaml
      - name: Restore .NET tools
        run: dotnet tool restore

      - name: Determine version
        id: version_step
        run: echo "semVer=$(dotnet nbgv get-version -v SemVer2)" >> "$GITHUB_OUTPUT"

      - name: Display version
        run: echo "Version ${{ steps.version_step.outputs.semVer }}"
```

(Checkout met `fetch-depth: 0`, `setup-dotnet`, `DOTNET_INSTALL_DIR`-env, job-`outputs.semVer` en `name`/`runs-on` blijven staan. `run: echo "semVer=..." >> "$GITHUB_OUTPUT"` is 68 tekens — onder de 80-limiet.)

- [ ] **Step 2: Delete GitVersion.yml and check for leftovers**

Run:

```bash
git rm GitVersion.yml
grep -ri "gitversion" --include="*.yml" --include="*.yaml" --include="*.json" --include="*.csproj" --include="*.md" . | grep -vi "Nerdbank" | grep -vi "superpowers/specs" | grep -vi "superpowers/plans"; echo "leftover-check-done"
```

Expected: geen output vóór `leftover-check-done` (historische specs/plans blijven — die vallen buiten de grep via de uitsluitingen; `docs/superpowers` bevat bewust de oude ontwerphistorie).

- [ ] **Step 3: Validate YAML and commit**

Run:

```bash
yamllint .github/workflows/ci.yml; echo "exit=$?"
```

Expected: `exit=0`, hooguit de twee bekende warnings.

Run:

```bash
git add .github/workflows/ci.yml
git commit -m "ci: determine version with Nerdbank.GitVersioning instead of GitVersion"
```

(De `git rm`-deletie uit Step 2 staat al staged en gaat in dezezelfde commit mee — één logische eenheid.)

### Task 3: Valideren via GitHub-PR, mergen, NB.GV-image bewijzen

**Files:**
- Geen (git-operaties + API-/UI-stappen)

**Interfaces:**
- Consumes: Task 1 + 2 op branch `feat/nbgv-migration` (schoon, gepusht).
- Produces: groene CI op PR én op `main` als bewijs; eerste `0.1.x`-image in Gitea-registry; `main` bevat de migratie na merge; branches opgeruimd.

- [ ] **Step 1: Push and open a PR `feat/nbgv-migration` → `main`**

Run:

```bash
git push -u origin feat/nbgv-migration
```

Open daarna de PR (github.com of API). Titel: `ci: determine version with Nerdbank.GitVersioning`. Niet mergen vóór Step 3.

- [ ] **Step 2: Confirm PR checks (publish hoort overgeslagen te worden)**

Expected op de PR: `Test (.NET)` ✅, `Version` ✅, `Security scan` ✅ (`Docker build` bestaat niet meer). `Publish image` verschijnt als **skipped** — correct gedrag, geen fout. Lees in de `Version`-log dat de getoonde versie de vorm `0.1.<height>-PullRequest<N>.<height>` heeft (pre-release op PR — verwacht NB.GV-gedrag).

- [ ] **Step 3: Merge and prove the first NB.GV image**

Merge de PR via GitHub. Daarna vuurt de push-trigger op `main`. Verwacht in die run: alle checks groen plus een groene `Publish image`-job. Controleer daarna in het Gitea-registry (packages-UI op `go.berg-connect.nl`) dat image `beheerder/learncicd` een tag in de vorm `0.1.<height>` (stabiel, zonder pre-release-label — want gebouwd op `main`) plus bijgewerkte `latest` heeft. Pas als beide zichtbaar zijn, geldt de migratie als bewezen.

- [ ] **Step 4: Clean up**

Verwijder de remote branch, daarna lokaal:

```bash
git checkout main
git pull
git fetch --prune origin
git branch -d feat/nbgv-migration
git log --oneline -4
```

Expected: `main` bevat de twee migratie-commits plus merge; `git status --short` leeg; `git branch -a` toont alleen `main` + `origin/main` (+ PR-refs).
