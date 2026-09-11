# Image Tag Update via CI-PR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Laat CI na elke `publish` een PR openen die `image.tag` in `values.yaml` op de gepushte `semVer` zet; een `paths-ignore`-breaker voorkomt luscascades.

**Architecture:** Push-trigger krijgt `paths-ignore` voor `values.yaml`; nieuwe job `update-image-tag` (achter `publish` + `version`) edit de tag met een bewaakte `sed` en opent/bijwerkt een vaste PR-branch via `peter-evans/create-pull-request@v8`. Daarna validatie via PR (checks groen, `publish` geskipt) plus merge, gevolgd door het echte bewijs: de push-run opent de update-PR, na merge daarvan loopt géén CI (breaker) en draait ArgoCD de gepinde versie. Alle mechanismen hieronder zijn op 2026-09-11 lokaal bewezen: `sed`-guard vindt exact 1 `tag:`-regel en YAML parseert het resultaat als string; action-pin `@v8` is latest-major (v8.1.1).

**Tech Stack:** `peter-evans/create-pull-request@v8` (latest-major v8.1.1, april 2026), POSIX `grep`/`sed` (geen extra tooling — `yq` staat niet vast op de runner), job-`permissions` (`contents: write`, `pull-requests: write`), bestaande `semVer`-output.

## Global Constraints

- Push-trigger wordt exact:
```yaml
  push:
    branches: [main]
    paths-ignore:
      - charts/learncicd/values.yaml
```
(`pull_request`-trigger ongewijzigd — zonder paths-filter.)
- Nieuwe job `update-image-tag` (`name: Update image tag`): `runs-on: [self-hosted]`, `if: github.event_name == 'push'`, `needs: [publish, version]`, job-`permissions: contents: write` + `pull-requests: write`.
- Tag-edit exact via bewaakte `sed` (inhoud hieronder); géén `yq` (niet bewezen aanwezig op de runner).
- PR-vorm exact: vaste branch `ci/image-tag-update`, `base: main`, `delete-branch: false`, commit-message `ci: update image tag`, titel met versie, body met commit-sha (inhoud hieronder).
- `GITHUB_TOKEN` uitsluitend via `token: ${{ secrets.GITHUB_TOKEN }}`; nooit andere secrets aanraken of loggen.
- `yamllint` exit 0 met hooguit de 2 bekende warnings; geen regels >80 (lange regels alleen via YAML-folding of korte `env`-achtige splits — nooit enkele lange regel).
- Werk op feature-branch `feat/image-tag-pr`; merge naar `main` uitsluitend via PR met groene checks (branch protection); conventionele commits.

---

## File Structure

| Bestand | Verantwoordelijkheid |
|---|---|
| `.github/workflows/ci.yml` | Enig te wijzigen bestand: trigger + nieuwe job |

`values.yaml` wordt door CI zelf bijgewerkt (nooit handmatig in deze taken); al het andere blijft onaangeraakt.

---

### Task 1: Trigger-breaker + update-job (workflow)

**Files:**
- Modify: `.github/workflows/ci.yml` (trigger + nieuwe job onder `publish`)

**Interfaces:**
- Consumes: bestaande jobs (`publish` moet groen zijn vóór update; `version` levert `semVer`).
- Produces: na een push naar `main` opent CI een update-PR met de gepushte tag. Task 2 valideert op GitHub.

- [ ] **Step 1: Add paths-ignore to the push trigger**

Wijzig:

```yaml
  push:
    branches: [main]
```

naar:

```yaml
  push:
    branches: [main]
    paths-ignore:
      - charts/learncicd/values.yaml
```

- [ ] **Step 2: Append the `update-image-tag` job (onder `publish`)**

```yaml
  update-image-tag:
    name: Update image tag
    runs-on: [self-hosted]
    if: github.event_name == 'push'
    needs: [publish, version]
    permissions:
      contents: write
      pull-requests: write
    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set image tag to published version
        run: >
          TAG="${{ needs.version.outputs.semVer }}"
          MATCHES=$(grep -c '^  tag: ' charts/learncicd/values.yaml);
          if [ "$MATCHES" -ne 1 ];
          then echo "::error::Expected exactly one image tag line";
          exit 1; fi;
          sed -i -E "s/^(  tag: ).*/\1$TAG/"
          charts/learncicd/values.yaml

      - name: Open update PR
        uses: peter-evans/create-pull-request@v8
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          commit-message: "ci: update image tag"
          title: >
            ci: update image tag to
            ${{ needs.version.outputs.semVer }}
          body: >
            Automated tag update for image published from
            ${{ github.sha }}.
          branch: ci/image-tag-update
          base: main
          delete-branch: false
```

- [ ] **Step 3: Validate YAML and commit**

Run:

```bash
yamllint .github/workflows/ci.yml; echo "exit=$?"
```

Expected: `exit=0`, hooguit de twee bekende warnings.

Run:

```bash
git add .github/workflows/ci.yml
git commit -m "ci: open update PR with published image tag after publish"
```

### Task 2: Valideren via GitHub-PR en mergen

**Files:**
- Geen (git-operaties + API-stappen)

**Interfaces:**
- Consumes: Task 1 op branch `feat/image-tag-pr` (schoon, gepusht).
- Produces: groene CI op PR als bewijs; `main` bevat de job na merge; branches opgeruimd. Task 3 bewijst het eindgedrag.

- [ ] **Step 1: Push and open a PR `feat/image-tag-pr` → `main`**

Run:

```bash
git push -u origin feat/image-tag-pr
```

Open daarna de PR (github.com of API). Titel: `ci: open update PR with published image tag after publish`. Niet mergen vóór Step 3.

- [ ] **Step 2: Confirm PR checks (update-job hoort overgeslagen te worden)**

Expected op de PR: `Test (.NET)` ✅, `Version` ✅, `Security scan` ✅. `Publish image` **skipped** (event is `pull_request`) en `Update image tag` **skipped** (zelfde reden) — beide correct gedrag, geen fout.

- [ ] **Step 3: Merge and clean up**

Merge de PR via GitHub, verwijder de remote branch, daarna lokaal:

```bash
git checkout main
git pull
git fetch --prune origin
git branch -d feat/image-tag-pr
git log --oneline -3
```

Expected: `main` bevat de workflow-commit plus merge; `git status --short` leeg.

### Task 3: Eindbewijs — update-PR, breaker en gepinde deploy

**Files:**
- Geen (CI-runs + API-/UI-stappen; hooguit een menselijke merge)

**Interfaces:**
- Consumes: Task 2 gemergd op `main` (push-run loopt met de nieuwe job).
- Produces: bewezen keten (update-PR geopend met juiste tag → gemergd → géén CI → ArgoCD gepind); daarna opgeruimd.

- [ ] **Step 1: Confirm the update PR was opened with the right tag**

Na de merge uit Task 2 loopt de push-run op `main`. Verwacht in die run: alle bestaande checks groen, `publish` groen, `Update image tag` groen — plus een open PR vanaf branch `ci/image-tag-update` met titel `ci: update image tag to <semVer>` waarbij `<semVer>` gelijk is aan de zojuist gepubliceerde tag. Controleer in de PR-diff dat exact één regel wijzigde (`tag: latest` → `tag: <semVer>`).

- [ ] **Step 2: Human merges the update PR (wachtpunt — controller pauzeert hier)**

De mens mergt de update-PR via GitHub (bewuste keuze uit de spec — geen controller-merge). Daarna verwijdert de mens of controller de remote branch `ci/image-tag-update`. Pas na bevestiging van de merge gaat de uitvoering verder met Step 3.

- [ ] **Step 3: Prove the loop-breaker (géén nieuwe CI-run)**

Verwacht na de merge van de update-PR: géén nieuwe workflow-run op `main` (de push raakt alleen `charts/learncicd/values.yaml` → `paths-ignore`). Controleer via de Actions-runs-lijst dat er geen run start voor de merge-commit. Verschijnt er tóch een run: STOP, rapporteer BLOCKED met run-id — de breaker werkt niet.

- [ ] **Step 4: Prove ArgoCD runs the pinned version**

Verwacht: ArgoCD sync de gemergde tag automatisch (bestaande auto-sync). Controleer via SSH op de node dat de Deployment-image exact `<registry>/beheerder/learncicd:<semVer>` is (geen `latest` meer in effect):

```bash
ssh -o BatchMode=yes 192.168.2.46 'kubectl -n default get deployment learncicd-learncicd -o jsonpath="{.spec.template.spec.containers[0].image}"; echo'
```

Expected output: `go.berg-connect.nl/beheerder/learncicd:<semVer>` met de `<semVer>` uit Step 1.
