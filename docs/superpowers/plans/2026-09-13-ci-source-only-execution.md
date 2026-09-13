# CI Source-Only Execution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Laat `Test (.NET)` en `Security scan` alleen draaien bij source-code-wijzigingen, zonder workflow-level path-filters.

**Architecture:** Verwijder de `paths-ignore` uit de `pull_request`-trigger, maak de `changes`-classificatie expliciet source-only en gate `test`/`security` uitsluitend op `needs.changes.outputs.code == 'true'`.

**Tech Stack:** GitHub Actions, bash-`case`-classificatie, `git diff --name-only`, `yamllint`, .NET 10, Docker Buildx.

## Global Constraints

- NOOIT direct committen of pushen naar `main`; werk op branch `ci/source-only-execution` en merge uitsluitend via GitHub PR.
- Conventionele commit-messages (`ci:`, `docs:`, `test:`, `chore:`).
- `runs-on: [self-hosted]` blijft overal staan.
- Secrets, runners, CD, promotie en ArgoCD worden NIET gewijzigd.
- Bestanden behouden POSIX-newline op EOF.
- `yamllint .github/workflows/ci.yml` geeft exit 0 met alleen de bekende warnings `missing document start` en `truthy` op `on:`.
- Elke wijziging wordt gecontroleerd met `git diff --check`.

---

## File Structure

| Bestand | Verantwoordelijkheid |
|---|---|
| `.github/workflows/ci.yml` | PR-trigger zonder path-filters, expliciete source-code-classificatie en code-only job-gates. |
| `docs/superpowers/specs/2026-09-13-ci-source-only-execution-design.md` | Reeds goedgekeurde specificatie; wordt door deze implementatie niet gewijzigd. |
| `docs/superpowers/plans/2026-09-13-ci-source-only-execution.md` | Dit planbestand zelf. |

---

### Task 1: Verwijder workflow-level `paths-ignore`

**Files:**
- Modify: `.github/workflows/ci.yml:3-9`
- Test: live regressiecheck op `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: huidige trigger met drie values-`paths-ignore`-regels.
- Produces: trigger zonder `paths` of `paths-ignore`, zodat verplichte checks nooit ontbreken.

- [ ] **Step 1: Documenteer de falende baseline**

Run:

```bash
missing=0
for p in 'src/**' 'tests/**' '*.csproj' 'Dockerfile' 'Dockerfile.*' 'global.json' 'version.json'; do
  if ! grep -Fq "$p" .github/workflows/ci.yml; then echo "missing pattern: $p"; missing=1; fi
done
if grep -q 'paths-ignore:' .github/workflows/ci.yml; then echo 'forbidden: paths-ignore present'; missing=1; fi
if grep -q "needs.changes.outputs.workflows == 'true'" .github/workflows/ci.yml; then echo 'forbidden: workflows gate present'; missing=1; fi
if [ "$missing" -ne 0 ]; then echo 'BASELINE FAIL: source-only gates ontbreken'; exit 1; fi
echo 'SOURCE-ONLY GATES PASS'
```

Expected: exit 1, met zeven `missing pattern`-regels plus `forbidden: paths-ignore present` en `forbidden: workflows gate present`.

- [ ] **Step 2: Verwijder exact de `paths-ignore`-regels**

Huidig:

```yaml
on:
  pull_request:
    branches: [main]
    paths-ignore:
      - 'charts/learncicd/values-devtest.yaml'
      - 'charts/learncicd/values-acceptatie.yaml'
      - 'charts/learncicd/values-productie.yaml'
```

Wordt:

```yaml
on:
  pull_request:
    branches: [main]
```

- [ ] **Step 3: Verifieer de triggerwijziging**

Run:

```bash
git diff --check
```

Expected: geen output.

Run:

```bash
yamllint .github/workflows/ci.yml; echo "exit=$?"
```

Expected: `exit=0`, alleen de bekende warnings `missing document start` en `truthy` op `on:`.

Run:

```bash
if grep -q 'paths-ignore:' .github/workflows/ci.yml; then echo 'FAIL: paths-ignore nog aanwezig'; exit 1; fi
echo 'PASS: geen workflow-level paths-ignore'
```

Expected: `PASS: geen workflow-level paths-ignore`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: verwijder workflow-level values paths-ignore"
```

---

### Task 2: Maak `changes` expliciet source-only

**Files:**
- Modify: `.github/workflows/ci.yml:38-54` in de uitgangspositie; na Task 1 gelden dezelfde exacte `case`-fragmenten als anker, niet het regelnummer.
- Test: patroonasserties op `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: bestaande `FILES`, `CODE`, `WORKFLOWS` en `GITHUB_OUTPUT`-logica.
- Produces: `code=true` voor source/infra-paden en onbekende paden; `code=false` voor workflows, docs, charts en ArgoCD.

- [ ] **Step 1: Toon dat de source-patronen ontbreken**

Run:

```bash
for p in 'src/**' 'tests/**' '*.csproj' 'Dockerfile' 'Dockerfile.*' 'global.json' 'version.json'; do
  grep -Fq "$p" .github/workflows/ci.yml || echo "missing pattern: $p"
done
```

Expected: alle zeven patronen worden als missing gerapporteerd.

- [ ] **Step 2: Vervang exact het `case`-blok**

Huidig:

```bash
FILES=$(git diff --name-only origin/main...HEAD);
CODE=false; WORKFLOWS=false;
while IFS= read -r f; do
case "$f" in
  charts/*|argocd/*)
  :;;
  docs/*|*.md|.gitignore|LICENSE)
  :;;
  .github/*)
  WORKFLOWS=true;;
  *)
  CODE=true;;
esac;
done <<< "$FILES";
echo "code=$CODE" >> "$GITHUB_OUTPUT";
echo "workflows=$WORKFLOWS" >> "$GITHUB_OUTPUT"
```

Wordt:

```bash
FILES=$(git diff --name-only origin/main...HEAD);
CODE=false; WORKFLOWS=false;
while IFS= read -r f; do
case "$f" in
  src/**|tests/**|*.csproj|Dockerfile|Dockerfile.*|global.json|version.json)
  CODE=true;;
  .github/*)
  WORKFLOWS=true;;
  charts/*|argocd/*|docs/*|*.md|.gitignore|LICENSE)
  :;;
  *)
  CODE=true;;
esac;
done <<< "$FILES";
echo "code=$CODE" >> "$GITHUB_OUTPUT";
echo "workflows=$WORKFLOWS" >> "$GITHUB_OUTPUT"
```

- [ ] **Step 3: Verifieer patronen en YAML**

Run:

```bash
for p in 'src/**' 'tests/**' '*.csproj' 'Dockerfile' 'Dockerfile.*' 'global.json' 'version.json'; do
  grep -Fq "$p" .github/workflows/ci.yml || { echo "FAIL: missing pattern: $p"; exit 1; }
done
echo 'PASS: alle source-patronen aanwezig'
```

Expected: `PASS: alle source-patronen aanwezig`.

Run:

```bash
git diff --check && yamllint .github/workflows/ci.yml; echo "exit=$?"
```

Expected: geen `diff --check`-output en `exit=0` met alleen de twee bekende warnings.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: classificeer alleen source en infra als code"
```

---

### Task 3: Gate `test` en `security` uitsluitend op code

**Files:**
- Modify: `.github/workflows/ci.yml:63-65` in de uitgangspositie voor de `test`-job; gebruik de omliggende jobnaam `test:` als anker.
- Modify: `.github/workflows/ci.yml:107-109` in de uitgangspositie voor de `security`-job; gebruik de omliggende jobnaam `security:` als anker.
- Test: volledige regressiecheck uit Task 1, Step 1

**Interfaces:**
- Consumes: `changes.outputs.code` uit Task 2.
- Produces: `Test (.NET)` en `Security scan` draaien alleen bij `code == 'true'`; bij non-code PRs worden zij geskipt en niet gemist.

- [ ] **Step 1: Toon dat de workflows-gate nog aanwezig is**

Run:

```bash
grep -n "needs.changes.outputs.workflows == 'true'" .github/workflows/ci.yml
```

Expected: twee matches, bij de `test`-job en bij de `security`-job.

- [ ] **Step 2: Vervang exact de `test`-gate**

Huidig:

```yaml
    needs: [changes]
    if: >
      needs.changes.outputs.code == 'true' ||
      needs.changes.outputs.workflows == 'true'
    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up .NET SDK
        uses: actions/setup-dotnet@v4

      - name: Cache NuGet packages
        uses: actions/cache@v4
        with:
          path: ~/.nuget/packages
          key: nuget-${{ runner.os }}-${{ hashFiles('**/*.csproj') }}
          restore-keys: |
            nuget-${{ runner.os }}-
```

Wordt:

```yaml
    needs: [changes]
    if: needs.changes.outputs.code == 'true'
    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up .NET SDK
        uses: actions/setup-dotnet@v4

      - name: Cache NuGet packages
        uses: actions/cache@v4
        with:
          path: ~/.nuget/packages
          key: nuget-${{ runner.os }}-${{ hashFiles('**/*.csproj') }}
          restore-keys: |
            nuget-${{ runner.os }}-
```

Alleen het `if:`-blok onder jobnaam `test:` wijzigt; alle test-stappen blijven ongewijzigd.

- [ ] **Step 3: Vervang exact de `security`-gate**

Huidig:

```yaml
    needs: [changes]
    if: >
      needs.changes.outputs.code == 'true' ||
      needs.changes.outputs.workflows == 'true'
    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up .NET SDK
        uses: actions/setup-dotnet@v4

      - name: Cache NuGet packages
        uses: actions/cache@v4
        with:
          path: ~/.nuget/packages
          key: nuget-${{ runner.os }}-${{ hashFiles('**/*.csproj') }}
          restore-keys: |
            nuget-${{ runner.os }}-
```

Wordt:

```yaml
    needs: [changes]
    if: needs.changes.outputs.code == 'true'
    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up .NET SDK
        uses: actions/setup-dotnet@v4

      - name: Cache NuGet packages
        uses: actions/cache@v4
        with:
          path: ~/.nuget/packages
          key: nuget-${{ runner.os }}-${{ hashFiles('**/*.csproj') }}
          restore-keys: |
            nuget-${{ runner.os }}-
```

Alleen het `if:`-blok onder jobnaam `security:` wijzigt; alle security-stappen blijven ongewijzigd.

- [ ] **Step 4: Voer de volledige regressiecheck uit**

Run exact het script uit Task 1, Step 1.

Expected: exit 0 met `SOURCE-ONLY GATES PASS`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: draai test en security alleen bij source-code"
```

---

### Task 4: Valideer mapping en repositoryconventies

**Files:**
- Modify: geen
- Test: classificatiematrix, `yamllint`, .NET-validatie en Docker-build

**Interfaces:**
- Consumes: voltooide Tasks 1 tot en met 3.
- Produces: lokaal bewijs dat de mapping klopt en dat de ongewijzigde test-/security-opdrachten nog valideren.

- [ ] **Step 1: Test de classificatiematrix**

Run:

```bash
classify() {
  case "$1" in
    src/**|tests/**|*.csproj|Dockerfile|Dockerfile.*|global.json|version.json) printf 'true'; return;;
    .github/*|charts/*|argocd/*|docs/*|*.md|.gitignore|LICENSE) printf 'false'; return;;
    *) printf 'true'; return;;
  esac
}
check() {
  actual="$(classify "$1")"
  if [ "$actual" != "$2" ]; then echo "FAIL: $1 => $actual, verwacht $2"; exit 1; fi
}
check 'src/Api/Program.cs' true
check 'tests/Api.Tests/HealthEndpointTests.cs' true
check 'src/Api/Api.csproj' true
check 'Dockerfile' true
check 'Dockerfile.dev' true
check 'global.json' true
check 'version.json' true
check '.github/workflows/ci.yml' false
check 'docs/superpowers/specs/2026-09-13-ci-source-only-execution-design.md' false
check 'README.md' false
check '.gitignore' false
check 'LICENSE' false
check 'charts/learncicd/values-devtest.yaml' false
check 'argocd/applications/devtest.yaml' false
check 'scripts/nieuwe-tool.sh' true
echo 'PASS: classificatiematrix'
```

Expected: `PASS: classificatiematrix`.

- [ ] **Step 2: Valideer de workflow-YAML**

Run:

```bash
yamllint .github/workflows/ci.yml; echo "exit=$?"
```

Expected: `exit=0`, alleen de bekende warnings `missing document start` en `truthy` op `on:`.

- [ ] **Step 3: Valideer de ongewijzigde .NET-opdrachten**

Run:

```bash
dotnet restore
dotnet build -c Release --no-restore /p:TreatWarningsAsErrors=true
dotnet test -c Release --no-build --coverage --coverage-output-format cobertura
```

Expected: alle drie opdrachten slagen.

- [ ] **Step 4: Valideer de Docker-build**

Run:

```bash
docker build -t app:local .
```

Expected: de image bouwt succesvol.

- [ ] **Step 5: Controleer de werkboom**

Run:

```bash
git diff --check && git status --short --branch
```

Expected: geen `diff --check`-fouten en een schone werkboom; op `ci/source-only-execution` staan dan alleen de bedoelde spec-, plan- en workflow-commits.
