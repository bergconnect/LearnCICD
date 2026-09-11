# GitVersion + Security-Scan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Voeg twee PR-checks toe aan CI — `version` (GitVersion-versie berekenen + tonen) en `security` (vulnerabilities blokkeren, deprecated rapporteren) — en maak beide verplicht in branch protection.

**Architecture:** Twee onafhankelijke jobs naast `test`/`docker` (geen `needs` ertussen), gevolgd door GitHub-validatie via PR plus een branch-protection-update via API. Alle mechanismen hieronder zijn op 2026-09-11 lokaal bewezen: GitVersion 6.8.2 met `workflow: GitHubFlow/v1` berekent `0.0.1-21` op deze tagloze repo; `dotnet list --vulnerable` geeft exit 0 mét kwetsbaarheden (afdwinging vereist dus parsen); `dotnet list --deprecated` geeft exit 0 met én zonder deprecated packages.

**Tech Stack:** GitVersion (tool-lijn `6.x`, lokaal 6.8.2 geverifieerd) via `gittools/actions` `@v4`, `dotnet list package` (`--vulnerable --include-transitive`, `--deprecated`), GitHub branch protection API.

## Global Constraints

- Nieuwe jobs heten exact `version` (`name: Version`) en `security` (`name: Security scan`); `runs-on: ubuntu-latest`; geen `needs` tussen `version`/`security`/`test`; `docker` blijft `needs: test`.
- Alleen de `version`-job gebruikt `checkout` met `fetch-depth: 0`; alle andere jobs standaard (shallow) checkout.
- `GitVersion.yml` in repo-root bevat exact `workflow: GitHubFlow/v1` (één regel).
- GitVersion-acties gepind op major (`gittools/actions/gitversion/setup@v4`, `.../execute@v4`); tool-lijn `versionSpec: '6.x'` (float binnen major 6, conform repo-pin-conventie).
- Versie wordt alleen getoond (`semVer` + `fullSemVer` in log-output); nergens vastgelegd (geen stamping, tags, labels).
- Vulnerability-afdwinging gebeurt exact via grep op `has the following vulnerable packages` → `exit 1` (exit-code alleen is onvoldoende — bewezen exit 0 mét High-vulnerability).
- Deprecated-stap is een kaal `dotnet list package --deprecated` commando (altijd groen — bewezen exit 0 mét deprecated package) en slaat nooit over (`if: always()` is NIET nodig; wél fail-fast zoals alles).
- Alle `dotnet`-commando's lopen vanuit de repo-root op solution-niveau (argumentloos, zoals `test`-job).
- `yamllint` exit 0 met hooguit de 2 bekende warnings (`document-start`, `truthy`); regels langer dan 80 tekens alleen via YAML-folding (`>`), nooit als enkele lange regel.
- Werk op feature-branch `feat/gitversion-security` (aangemaakt vanaf `main` vóór Taak 1); merge naar `main` uitsluitend via PR met groene checks (branch protection); conventionele commits.
- Nooit secrets in bestanden, logs of output; push-authenticatie via credential store.

---

## File Structure

| Bestand | Verantwoordelijkheid |
|---|---|
| `GitVersion.yml` (nieuw, repo-root) | GitVersion-workflow-selectie (1 regel) |
| `.github/workflows/ci.yml` | Twee jobs toevoegen (`version`, `security`); rest byte-identiek |

`src/*`, `Dockerfile`, testprojecten, `global.json` en de `test`/`docker`-jobs blijven onaangeraakt.

---

### Task 1: `version`-job (GitVersion.yml + workflow)

**Files:**
- Create: `GitVersion.yml`
- Modify: `.github/workflows/ci.yml` (alleen `version`-job toevoegen; `test`/`docker`/`security` onaangeroerd)

**Interfaces:**
- Consumes: volledige git-historie op de runner (via `fetch-depth: 0` — zonder lukt versieberekening niet).
- Produces: `Version`-check die de berekende versie logt. Task 3 gebruikt deze check als verplichte status-check.

- [ ] **Step 1: Create `GitVersion.yml` in repo-root**

```yaml
workflow: GitHubFlow/v1
```

- [ ] **Step 2: Append the `version` job to `.github/workflows/ci.yml`**

Voeg onder de `docker`-job toe (zelfde inspringniveau als `test:`/`docker:`, 2 spaties):

```yaml
  version:
    name: Version
    runs-on: ubuntu-latest
    steps:
      - name: Check out code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

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

(De `run:`-regel is YAML-gefold (`>`) zodat `yamllint` line-length slaagt; de shell ontvangt exact `echo "Version <semVer> (full: <fullSemVer>)"`.)

- [ ] **Step 3: Validate YAML**

Run:

```bash
yamllint .github/workflows/ci.yml GitVersion.yml; echo "exit=$?"
```

Expected: `exit=0` met hooguit de twee bekende warnings (`document-start`, `truthy`).

- [ ] **Step 4: Commit**

Run:

```bash
git add GitVersion.yml .github/workflows/ci.yml
git commit -m "ci: add version job with GitVersion (GitHubFlow)"
```

(GitVersion zelf draaien kan lokaal niet zonder de Action; de config is al bewezen met tool 6.8.2 op een kloon van deze repo: `0.0.1-21`, exit 0. De CI-run in Task 3 is het echte bewijs.)

### Task 2: `security`-job (workflow)

**Files:**
- Modify: `.github/workflows/ci.yml` (alleen `security`-job toevoegen)

**Interfaces:**
- Consumes: `LearnCICD.sln` + NuGet-toegang op de runner (zelfde als `test`-job).
- Produces: `Security scan`-check die rood is bij vulnerabilities en deprecated rapporteert. Task 3 gebruikt deze check als verplichte status-check.

- [ ] **Step 1: Append the `security` job to `.github/workflows/ci.yml`**

Voeg onder de `version`-job toe:

```yaml
  security:
    name: Security scan
    runs-on: ubuntu-latest
    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up .NET SDK
        uses: actions/setup-dotnet@v4

      - name: Restore dependencies
        run: dotnet restore

      - name: Check for vulnerable packages
        run: >
          dotnet list package --vulnerable --include-transitive
          | tee audit.log;
          if grep -q "has the following vulnerable packages" audit.log;
          then echo "::error::Vulnerable NuGet packages found";
          exit 1; fi;
          rm -f audit.log

      - name: Report deprecated packages
        run: dotnet list package --deprecated
```

(Regels zijn YAML-gefold voor line-length; de shell ontvangt één commando per stap. `grep -q` in een `if` is veilig onder de `errexit`-shell van Actions. `audit.log` leeft alleen in de vluchtige runner-workspace; lokaal altijd opruimen.)

- [ ] **Step 2: Prove the enforcement RED path in /tmp (repo blijft schoon)**

De repo heeft geen kwetsbare packages, dus bewijs het rood-pad met een wegwerpproject buiten de repo:

Run:

```bash
rm -rf /tmp/opencode/redprobe && mkdir -p /tmp/opencode/redprobe
dotnet new console -n Red -o /tmp/opencode/redprobe/Red > /dev/null 2>&1
dotnet add /tmp/opencode/redprobe/Red/Red.csproj package Newtonsoft.Json --version 12.0.1 > /dev/null 2>&1
dotnet list /tmp/opencode/redprobe/Red/Red.csproj package --vulnerable --include-transitive | tee /tmp/opencode/red-audit.log; if grep -q "has the following vulnerable packages" /tmp/opencode/red-audit.log; then echo "ENFORCEMENT_FIRES"; exit 1; fi
```

Expected: output bevat `Newtonsoft.Json ... High ...`, daarna `ENFORCEMENT_FIRES`, exit 1. (Newtonsoft.Json 12.0.1 heeft een bekende High-vulnerability; op 2026-09-11 bewezen.)

Run daarna:

```bash
rm -rf /tmp/opencode/redprobe /tmp/opencode/red-audit.log; git status --short; echo "clean-check-done"
```

Expected: geen output vóór `clean-check-done` (repo onaangeroerd).

- [ ] **Step 3: Prove the GREEN path on the repo**

Run (vanuit repo-root):

```bash
dotnet list package --vulnerable --include-transitive > /tmp/opencode/green-audit.log 2>&1; echo "exit=$?"; grep -c "has no vulnerable packages" /tmp/opencode/green-audit.log; dotnet list package --deprecated > /tmp/opencode/green-depr.log 2>&1; echo "exit=$?"; grep -c "has no deprecated packages" /tmp/opencode/green-depr.log
```

Expected: `exit=0`, `2` (beide projecten zonder vulnerabilities), `exit=0`, `2` (beide zonder deprecated).

- [ ] **Step 4: Validate YAML and commit**

Run:

```bash
yamllint .github/workflows/ci.yml; echo "exit=$?"
```

Expected: `exit=0`, hooguit de twee bekende warnings.

Run:

```bash
rm -f audit.log; git add .github/workflows/ci.yml
git commit -m "ci: add security job failing on vulnerable packages"
```

### Task 3: Valideren via GitHub-PR, protection bijwerken, mergen

**Files:**
- Geen (git-operaties + API-stappen)

**Interfaces:**
- Consumes: Task 1 + 2 op branch `feat/gitversion-security` (schoon, gepusht).
- Produces: groene CI op een echte PR als bewijs; `Version` + `Security scan` als verplichte checks; `main` bevat de migratie na merge; branches opgeruimd.

- [ ] **Step 1: Push and open a PR `feat/gitversion-security` → `main`**

Run:

```bash
git push -u origin feat/gitversion-security
```

Open daarna de PR (github.com of API). Titel: `ci: add version and security jobs`. Niet mergen vóór Step 4.

- [ ] **Step 2: Add the new checks to branch protection (vóór merge)**

Via API (`PUT /repos/bergconnect/LearnCICD/branches/main/protection`), ongewijzigd behalve `contexts`:

```json
["Test (.NET)", "Docker build", "Version", "Security scan"]
```

(`strict`, `enforce_admins`, PR-eis en no-force-push/deletie blijven staan.) Verifieer daarna via GET dat alle vier contexts vereist zijn.

- [ ] **Step 3: Confirm green checks and the version output**

Expected: checks `Test (.NET)` ✅, `Docker build` ✅, `Version` ✅, `Security scan` ✅. Controleer in de `Version`-log dat de berekende versie getoond wordt (op een PR een pre-release-vorm zoals `0.1.0-pullrequest.N+...` — verwacht gedrag).

- [ ] **Step 4: Merge and clean up**

Merge de PR via GitHub, verwijder de remote branch, daarna lokaal:

```bash
git checkout main
git pull
git fetch --prune origin
git branch -d feat/gitversion-security
git log --oneline -5
```

Expected: `main` bevat de implementatie-commits plus merge; `git status --short` leeg; `git branch -a` toont alleen `main` + `origin/main` (+ PR-refs).
