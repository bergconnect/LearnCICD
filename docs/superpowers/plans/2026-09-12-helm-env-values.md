# Helm Values per Omgeving Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Voeg drie overlay-values-bestanden toe (poort per stage: 8080/8081/8082) als eerste stap van het multi-stage-traject.

**Architecture:** Drie minimale YAML-bestanden naast `values.yaml`, daarna PR-validatie + merge. Overlay-semantiek (`-f values.yaml -f values-<env>.yaml`, tweede wint) is op 2026-09-12 lokaal bewezen met een wegwerpchart (basispoort overschreven naar 8081 in render-output).

**Tech Stack:** Helm v3.16.4 (lokaal aanwezig), bestaande chart-structuur (ongewijzigd).

## Global Constraints

- Drie nieuwe bestanden, exacte inhoud (alleen poort — niets anders):
  - `charts/learncicd/values-devtest.yaml`: `service: {port: 8080}`
  - `charts/learncicd/values-acceptatie.yaml`: `service: {port: 8081}`
  - `charts/learncicd/values-productie.yaml`: `service: {port: 8082}`
- Gebruik altijd als overlay (`-f values.yaml -f values-<env>.yaml`); nooit waarden dupliceren uit `values.yaml`.
- `helm lint` schoon (alleen de bekende `icon is recommended`-info is oké).
- Werk op feature-branch `feat/helm-env-values`; merge naar `main` uitsluitend via PR met groene checks (branch protection); conventionele commits.

---

## File Structure

| Bestand | Verantwoordelijkheid |
|---|---|
| `charts/learncicd/values-devtest.yaml` | DevTest-overlay (poort 8080) |
| `charts/learncicd/values-acceptatie.yaml` | Acceptatie-overlay (poort 8081) |
| `charts/learncicd/values-productie.yaml` | Productie-overlay (poort 8082) |

`values.yaml`, templates, helpers en al het andere blijven onaangeraakt.

---

### Task 1: Overlay-bestanden maken + valideren

**Files:**
- Create: `charts/learncicd/values-devtest.yaml`
- Create: `charts/learncicd/values-acceptatie.yaml`
- Create: `charts/learncicd/values-productie.yaml`

**Interfaces:**
- Consumes: bestaande `values.yaml` (basis, ongewijzigd) + chart-templates (ongewijzigd).
- Produces: drie overlays; per-env render toont de juiste poort. Task 2 valideert op GitHub.

- [ ] **Step 1: Create `charts/learncicd/values-devtest.yaml`**

```yaml
service:
  port: 8080
```

- [ ] **Step 2: Create `charts/learncicd/values-acceptatie.yaml`**

```yaml
service:
  port: 8081
```

- [ ] **Step 3: Create `charts/learncicd/values-productie.yaml`**

```yaml
service:
  port: 8082
```

- [ ] **Step 4: Lint and render-verify per environment**

Run:

```bash
helm lint charts/learncicd
```

Expected: `1 chart(s) linted, 0 chart(s) failed` (alleen `icon is recommended`-info is oké).

Run:

```bash
for ENV in devtest acceptatie productie; do echo "--- $ENV ---"; helm template t charts/learncicd -f charts/learncicd/values.yaml -f charts/learncicd/values-$ENV.yaml --show-only templates/service.yaml | grep -E "^\s+- port:"; done
```

Expected:

```text
--- devtest ---
    - port: 8080
--- acceptatie ---
    - port: 8081
--- productie ---
    - port: 8082
```

- [ ] **Step 5: Commit**

Run:

```bash
git add charts/learncicd/values-devtest.yaml charts/learncicd/values-acceptatie.yaml charts/learncicd/values-productie.yaml
git commit -m "feat: add per-environment values overlays with distinct service ports"
```

### Task 2: Valideren via GitHub-PR en mergen

**Files:**
- Geen (git-operaties + API-stappen)

**Interfaces:**
- Consumes: Task 1 op branch `feat/helm-env-values` (schoon, gepusht).
- Produces: groene CI op PR als bewijs; `main` bevat de overlays na merge; branches opgeruimd.

- [ ] **Step 1: Push and open a PR `feat/helm-env-values` → `main`**

Run:

```bash
git push -u origin feat/helm-env-values
```

Open daarna de PR (github.com of API). Titel: `feat: add per-environment values overlays with distinct service ports`. Niet mergen vóór Step 3.

- [ ] **Step 2: Confirm PR checks**

Expected op de PR: `Test (.NET)` ✅, `Version` ✅, `Security scan` ✅ (`Docker build` bestaat niet meer; `Publish image` **skipped** — event is `pull_request`, correct gedrag). NB: deze PR raakt alleen `charts/**` → met actieve path-gates draaien `test`/`security`/`version` als `skipped` en blijft de PR mergebaar; zonder gates draait alles groen. Beide uitkomsten zijn acceptabel bewijs.

- [ ] **Step 3: Merge and clean up**

Merge de PR via GitHub, verwijder de remote branch, daarna lokaal:

```bash
git checkout main
git pull
git fetch --prune origin
git branch -d feat/helm-env-values
git log --oneline -3
```

Expected: `main` bevat de drie overlay-bestanden plus merge; `git status --short` leeg.
