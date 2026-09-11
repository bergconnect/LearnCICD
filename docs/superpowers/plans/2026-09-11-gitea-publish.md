# Gitea Publish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publiceer de Docker-image naar `go.berg-connect.nl/beheerder/learncicd` (`semVer` + `latest`) bij elke merge naar `main`, met credentials uitsluitend via GitHub Secrets.

**Architecture:** Trigger uitgebreid met `push` op `main`; `docker`-job wordt PR-only; nieuwe `publish`-job (push-only, achter `test` + `version`) logt in op Gitea en pusht twee tags. Daarna validatie via PR (checks groen, `publish` overgeslagen) plus merge (push-event bewijst de echte publicatie). Volledige nieuwe workflow is vooraf gevalideerd: `yamllint` exit 0, geen regels >80, YAML-structuur geparset (`if`/`needs`/`outputs`/newline-tags correct).

**Tech Stack:** `docker/login-action@v4` (latest v4.6.0, juli 2026), `docker/build-push-action@v6` (bestaand), `needs.version.outputs.semVer` (nieuw job-output), GitHub Secrets (`GITEA_HOST`, `GITEA_USER`, `GITEA_TOKEN` — alle drie aanwezig, geverifieerd op naam).

## Global Constraints

- Triggerblok wordt exact `pull_request: branches [main]` + `push: branches [main]`.
- `docker`-job krijgt `if: github.event_name == 'pull_request'` (direct na `runs-on`); zijn tag `app:pr-${{ github.event.number }}` blijft ongewijzigd.
- `version`-job krijgt job-level `outputs: semVer: ${{ steps.version_step.outputs.semVer }}` (na `runs-on`); verder ongewijzigd.
- Nieuwe job `publish` (`name: Publish image`): `runs-on: ubuntu-latest`, `if: github.event_name == 'push'`, `needs: [test, version]`, job-`env: IMAGE: ${{ secrets.GITEA_HOST }}/beheerder/learncicd`; login via `docker/login-action@v4` (`registry`/`username`/`password` uit secrets); build-push met `push: true` en newline-`tags:` (`${{ env.IMAGE }}:${{ needs.version.outputs.semVer }}` + `${{ env.IMAGE }}:latest`). Image-naam altijd kleine letters (`beheerder/learncicd`).
- Nergens host/user/token hardcoded — uitsluitend `${{ secrets.* }}`; nooit secrets in logs, output of commits.
- `yamllint` exit 0 met hooguit de 2 bekende warnings; geen regels >80 (lange tag-regels via `env.IMAGE`, nooit enkele lange regel).
- Nooit lokaal pushen (`docker build` zonder push is het enige lokale bewijs); registry-login en echte push alleen in CI.
- Werk op feature-branch `feat/gitea-publish`; merge naar `main` uitsluitend via PR met groene checks (branch protection); conventionele commits.

---

## File Structure

| Bestand | Verantwoordelijkheid |
|---|---|
| `.github/workflows/ci.yml` | Enig te wijzigen bestand: trigger + `docker`-`if` + `version`-`outputs` + nieuwe `publish`-job |

`Dockerfile`, sources, tests, `GitVersion.yml` en alle andere jobs blijven onaangeraakt.

---

### Task 1: Triggers, docker-guard en version-output

**Files:**
- Modify: `.github/workflows/ci.yml` (3 kleine wijzigingen, inhoud hieronder)

**Interfaces:**
- Consumes: bestaande workflow op `main` (jobs `test`/`docker`/`version`/`security`).
- Produces: workflow die op PR- én push-events draait, met PR-only `docker` en `semVer` als job-output. Task 2 voegt hier de `publish`-job aan toe.

- [ ] **Step 1: Extend the trigger block**

Wijzig:

```yaml
on:
  pull_request:
    branches: [main]
```

naar:

```yaml
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
```

- [ ] **Step 2: Guard the docker job to PR events**

In de `docker`-job, voeg direct na `runs-on: ubuntu-latest` toe:

```yaml
    if: github.event_name == 'pull_request'
```

De job wordt dan (volgorde: `name`, `runs-on`, `if`, `needs`, `steps`):

```yaml
  docker:
    name: Docker build
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    needs: test
```

(Rest van de job byte-identiek, inclusief tag `app:pr-${{ github.event.number }}`.)

- [ ] **Step 3: Expose semVer as version-job output**

In de `version`-job, voeg direct na `runs-on: ubuntu-latest` toe:

```yaml
    outputs:
      semVer: ${{ steps.version_step.outputs.semVer }}
```

(Rest van de job byte-identiek.)

- [ ] **Step 4: Validate YAML and commit**

Run:

```bash
yamllint .github/workflows/ci.yml; echo "exit=$?"
```

Expected: `exit=0` met hooguit de twee bekende warnings (`document-start`, `truthy`).

Run:

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run on push to main, guard docker to PRs, expose version output"
```

### Task 2: `publish`-job (Gitea-login + push)

**Files:**
- Modify: `.github/workflows/ci.yml` (alleen `publish`-job toevoegen onder `security`)

**Interfaces:**
- Consumes: Task 1 (`push`-trigger actief, `needs.version.outputs.semVer` beschikbaar); secrets `GITEA_HOST`/`GITEA_USER`/`GITEA_TOKEN` bestaan in GitHub (door controller op naam geverifieerd vóór het schrijven van dit plan — nooit waarden opvragen of loggen).
- Produces: volledige publicatie-configuratie. Task 3 bewijst hem op GitHub (PR groen + echte push na merge).

- [ ] **Step 1: Append the `publish` job**

Voeg onder de `security`-job toe (zelfde inspringniveau als `test:`/`docker:`, 2 spaties):

```yaml
  publish:
    name: Publish image
    runs-on: ubuntu-latest
    if: github.event_name == 'push'
    needs: [test, version]
    env:
      IMAGE: ${{ secrets.GITEA_HOST }}/beheerder/learncicd
    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Gitea registry
        uses: docker/login-action@v4
        with:
          registry: ${{ secrets.GITEA_HOST }}
          username: ${{ secrets.GITEA_USER }}
          password: ${{ secrets.GITEA_TOKEN }}

      - name: Build and push image
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ${{ env.IMAGE }}:${{ needs.version.outputs.semVer }}
            ${{ env.IMAGE }}:latest
```

(`env.IMAGE` houdt de tag-regels onder 80 tekens; `tags: |` eist newline-scheiding — exact zo laten.)

- [ ] **Step 2: Prove local build equivalence (zonder push)**

Run:

```bash
docker build -t beheerder/learncicd:local . > /tmp/opencode/pub-build.log 2>&1; echo "exit=$?"; tail -2 /tmp/opencode/pub-build.log; docker rmi beheerder/learncicd:local > /dev/null 2>&1; rm -rf src/Api/bin src/Api/obj "tests/Api.Tests/bin" "tests/Api.Tests/obj" "tests/Api.Tests/TestResults"; git status --short; echo "clean-check-done"
```

Expected: `exit=0`, build-succes in log, image opgeruimd, `git status` leeg (niets dan de workflow-wijziging; géén login, géén push vanaf lokaal — nooit).

- [ ] **Step 3: Validate YAML and commit**

Run:

```bash
yamllint .github/workflows/ci.yml; echo "exit=$?"
```

Expected: `exit=0`, hooguit de twee bekende warnings.

Run:

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add publish job pushing image to Gitea registry"
```

### Task 3: Valideren via GitHub-PR, mergen, publicatie bewijzen

**Files:**
- Geen (git-operaties + API-/UI-stappen)

**Interfaces:**
- Consumes: Task 1 + 2 op branch `feat/gitea-publish` (schoon, gepusht).
- Produces: groene CI op PR én op `main` als bewijs; image met twee tags in Gitea-registry; `main` bevat de wijziging na merge; branches opgeruimd.

- [ ] **Step 1: Push and open a PR `feat/gitea-publish` → `main`**

Run:

```bash
git push -u origin feat/gitea-publish
```

Open daarna de PR (github.com of API). Titel: `ci: publish image to Gitea registry on merge to main`. Niet mergen vóór Step 3.

- [ ] **Step 2: Confirm PR checks (publish hoort overgeslagen te worden)**

Expected op de PR: `Test (.NET)` ✅, `Docker build` ✅, `Version` ✅, `Security scan` ✅. De `Publish image`-job verschijnt als **skipped** (event is `pull_request`, geen `push`) — dat is correct gedrag, geen fout.

- [ ] **Step 3: Merge and prove the real push**

Merge de PR via GitHub. Daarna vuurt de push-trigger op `main`. Verwacht in die run: alle vier bestaande checks groen plus een groene `Publish image`-job. Controleer daarna in het Gitea-registry (packages-UI of API op `go.berg-connect.nl`) dat image `beheerder/learncicd` bestaat met de `semVer`-tag van de merge (bv. `0.1.0`) én de `latest`-tag. Pas als beide tags zichtbaar zijn, geldt de publicatie als bewezen. (Een groene `publish`-job alléén — `docker push` exit 0 — betekent dat het registry de push accepteerde; de UI-check bevestigt het eindresultaat.)

- [ ] **Step 4: Clean up**

Verwijder de remote branch, daarna lokaal:

```bash
git checkout main
git pull
git fetch --prune origin
git branch -d feat/gitea-publish
git log --oneline -4
```

Expected: `main` bevat de twee workflow-commits plus merge; `git status --short` leeg; `git branch -a` toont alleen `main` + `origin/main` (+ PR-refs).
