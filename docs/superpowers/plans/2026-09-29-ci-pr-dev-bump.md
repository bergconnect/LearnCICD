# CI PR-dev-bump Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CI-run bumpt bij groene checks `values_dev.yaml` naar de nbgv-base-versie van `origin/main`, zodat dev PR-code draait vóór merge.

**Architecture:** Nieuwe `preview`-job in lokale `ci-template.yml` na `Verify`: base-versie bepalen via throwaway-worktree op `origin/main`, image publiceren (zelfde vorm als cd-dev-publish), bumpen via `bump-image-tag`-composite (auto-PR + automerge). Geen cluster-toegang, geen git-mutaties buiten de bump-PR.

**Tech Stack:** GitHub Actions (lokaal `ci-template.yml` + composites), `dotnet publish /t:PublishContainer`, skopeo, NBGV, `git worktree`.

## Global Constraints

- Max 80 tekens per regel in workflows/actions; `run: >` (NOOIT `run: |` bij multi-line `$(...)`).
- Caller-workflows: géén top-level `concurrency`, géén job `name:`; `secrets: inherit`.
- Template-jobs MOGEN `name:` + template-`concurrency` hebben (bestaand patroon).
- Composites erven GEEN secrets: `token`/`gpg-key`/`key-id` ALTIJD expliciet als inputs meegeven.
- `yamllint`: alleen `missing document start` + `truthy` op `on:` zijn oké.
- NOOIT direct naar `main`: feature-branch + PR, conventionele commits, `m_state: clean` vóór merge.
- Preview raakt NOOIT acc/prd (alleen `env-name: dev`), NOOIT handmatig mergen (owner).

---

## File Structure

- Modify: `.github/workflows/ci-template.yml` (nieuwe `preview`-job na `verify`; niets anders)

---

### Task 1: Preview-job + PR

**Files:**
- Modify: `.github/workflows/ci-template.yml` (append `preview`-job; bestaande jobs ongewijzigd)

**Interfaces:**
- Consumes: niets (eerste taak)
- Produces: PR met preview-job, `m_state: clean`, NIET zelf mergen

- [ ] **Step 1: Branch + bestaande structuur lezen**

```bash
git fetch origin && git checkout -b feat/ci-pr-dev-bump origin/main
```

Lees VOLLEDIG: `.github/workflows/ci-template.yml`. Noteer exact:
(a) `changes`-outputs (veld heet `projects`, JSON-array van keys);
(b) `verify`-job (`needs: [changes, verify-project]`, `if: always()`);
(c) hoe `verify-project` zijn matrix betrekt (zelfde `projects`-bron?).

- [ ] **Step 2: Preview-job toevoegen na verify**

```yaml
  preview:
    name: Preview to dev
    runs-on: [self-hosted]
    needs: [changes, verify-project, verify]
    if: >
      always() &&
      needs.verify.result == 'success' &&
      needs.changes.outputs.projects != '' &&
      needs.changes.outputs.projects != '[]'
    timeout-minutes: 20
    permissions:
      contents: write
      pull-requests: write
    strategy:
      fail-fast: false
      matrix:
        include: ${{ fromJSON(needs.changes.outputs.matrix) }}
```

LET OP: `changes` output heet `projects` (geen `matrix`) en bevat
ALLEEN keys (`["Api"]`), zonder image-namen. Bouw de matrix zoals
cd-dev-template dat doet — project→image via lookup (volgende step
als voorbeeld; pas namen EXACT aan op wat Step 1 vond):

```yaml
    steps:
      - name: Set up .NET
        uses: ./.github/actions/dotnet-setup
        with:
          fetch-depth: 0
          token: ${{ secrets.GH_PAT }}
          restore-tools: 'true'

      - name: Map project to image
        env:
          PROJECTS: ${{ needs.changes.outputs.projects }}
        run: >
          P=$(echo "$PROJECTS" |
          jq -r '.[${{ strategy.job-index }}]');
          IMAGE=$(jq -r --arg p "$P" '.[$p].image_name // empty'
          .github/projects.json);
          [ -n "$IMAGE" ] ||
          { echo "::error::$P ontbreekt in .github/projects.json";
          exit 1; };
          echo "PROJECT=$P" >> "$GITHUB_ENV";
          echo "IMAGE_NAME=$IMAGE" >> "$GITHUB_ENV"
```

(`strategy.job-index` koppelt matrix-rij aan project-index; als
`verify-project` een andere indexering gebruikt, OMDRAAIEN naar
`matrix.release.project`-vorm zoals cd-dev-template — lees en kies.)

```yaml
      - name: Base version from origin/main
        run: >
          git fetch origin main:refs/remotes/origin/main;
          rm -rf /tmp/nbgvmain;
          git worktree add /tmp/nbgvmain origin/main;
          VER=$(dotnet nbgv get-version -v SemVer2
          --project /tmp/nbgvmain/src/$PROJECT 2>/dev/null ||
          (cd /tmp/nbgvmain/src/$PROJECT &&
          dotnet nbgv get-version -v SemVer2));
          git worktree remove --force /tmp/nbgvmain;
          VER=$(echo "$VER" | cut -d'-' -f1 | cut -d'+' -f1);
          [[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
          { echo "::error::geen schone base-versie: '$VER'"; exit 1; };
          echo "VER=$VER" >> "$GITHUB_ENV";
          echo "Base version $VER for $PROJECT"
```

(`--project`-vlag bestaat mogelijk NIET in deze nbgv-versie —
cd-fallback met subshell werkt altijd; behoud beide met `||`.
Versie MOET suffixloos `x.y.z` zijn: exact wat acc/prd later
krijgen.)

```yaml
      - name: Build image archive with dotnet publish
        run: >
          dotnet publish "src/$PROJECT/$PROJECT.csproj"
          --os linux --arch x64
          -c Release
          -p:ContainerBaseImage=mcr.microsoft.com/dotnet/aspnet:10.0
          -p:ContainerRepository=$REGISTRY/$REPOSITORY/$IMAGE_NAME
          -p:ContainerImageTag=$VER
          /t:PublishContainer
          -p:ContainerArchiveOutputPath=/tmp/image-$PROJECT-pr.tar
        env:
          REGISTRY: ${{ vars.GITEA_LOCAL }}
          REPOSITORY: ${{ vars.GITEA_SOURCE_REPOSITORY }}
```

(`ContainerBaseImage`-waarde VERIFICEREN tegen cd-dev-template
`BASE_IMAGE`-input/basis in `cd.yml` — letterlijk overnemen, niet
aannemen. `REGISTRY`/`REPOSITORY` idem tegen cd-dev-publish r144-145.)

```yaml
      - name: Push base tag with Skopeo
        run: >
          IMAGE="$REGISTRY/$REPOSITORY/$IMAGE_NAME";
          skopeo copy --tls-verify=false
          --dest-username ${{ vars.GITEA_USER }}
          --dest-password ${{ secrets.GITEA_TOKEN }}
          docker-archive:/tmp/image-$PROJECT-pr.tar:$IMAGE:$VER
          docker://$IMAGE:$VER
        env:
          REGISTRY: ${{ vars.GITEA_LOCAL }}
          REPOSITORY: ${{ vars.GITEA_SOURCE_REPOSITORY }}
```

```yaml
      - name: Bump dev tag via composite
        uses: ./.github/actions/bump-image-tag
        with:
          project: ${{ env.PROJECT }}
          env-name: dev
          version: ${{ env.VER }}
          image-name: ${{ env.IMAGE_NAME }}
          branch: ci/preview-${{ env.PROJECT }}-${{ env.VER }}
          commit-message: "ci: preview ${{ env.PROJECT }} ${{ env.VER }} to dev"
          pr-title: "ci: preview ${{ env.PROJECT }} ${{ env.VER }} to dev"
          pr-body: Automated PR preview of validated image ${{ env.VER }} to dev.
          token: ${{ secrets.GH_PAT }}
          gpg-key: ${{ secrets.BOT_GPG_PRIVATE_KEY }}
          key-id: ${{ vars.BOT_GPG_KEYID }}
```

(Branch-naam `ci/preview-…` i.p.v. CD-vorm, zodat preview-PRs
herkenbaar blijven. Inputs `token`/`gpg-key`/`key-id` zijn
VERPLICHT (geen secret-erving in composites) — exact deze drie
namen uit de action-definitie.)

- [ ] **Step 3: Valideer + commit + push + PR**

```bash
yamllint .github/workflows/ci-template.yml   # alleen 2 bekende warnings oké
git add .github/workflows/ci-template.yml
git commit -m "feat: PR-code naar dev via values-bump"
git push -u origin feat/ci-pr-dev-bump
```

PR (base `main`), wacht `m_state: clean`. NIET mergen (owner).
Bewijsvoering voor groen: de PR-CI zelf.

---

### Task 2: Bewijsronde + cleanup

**Files:** Geen (live verificatie; vereist gemergde PR uit Task 1)

**Interfaces:**
- Consumes: Task 1 gemerged (preview-job live op `main`)
- Produces: bewezen preview-cyclus; schone repo

- [ ] **Step 1: Probe-PR met Worker-wijziging**

1-regel comment in `src/Worker/Program.cs`, branch
`probe/ci-pr-dev-bump`, PR. Wacht CI: Verify groen →
preview-job groen → bump-PR (`ci/preview-Worker-*`) open.
Noteer basis-versie `V` (uit run-logs). Laat bump-PR mergen
(owner of automerge — noteer welke).

- [ ] **Step 2: Pod-bewijs in dev**

```bash
ssh -o ConnectTimeout=10 192.168.2.46 'kubectl -n dev get pods -o json' | python3 -c "
import json,sys
for p in json.load(sys.stdin)['items']:
    if 'worker' in p['metadata']['name']:
        print(p['metadata']['name'], '|', p['spec']['containers'][0]['image'].split(':')[-1], '|', p['status']['phase'])"
```

Verwacht: pod draait PR-code op tag `V` (gelijk aan wat acc/prd
later krijgen), `Running`. PR-code bewijzen: de comment-regel
staat ALLEEN in de PR (bv. via `/health`-output als die de
tekst toont, of image-digest vergelijken met de PR-build).

- [ ] **Step 3: Merge + CD-overname + revert**

Laat probe-PR mergen (owner). Wacht CD-run: `values_dev.yaml`
op echte versie (≥ `V`), pod terug op echte tag. Revert de
probe-comment via PR (schone main). Ruim branch op.

- [ ] **Step 4: Afronding**

```bash
git checkout main && git pull -q origin main && git status --short
git branch -D feat/ci-pr-dev-bump probe/ci-pr-dev-bump 2>/dev/null; true
```

Rapporteer: probe-PR-nummer, `V`, bump-PR-nummer, pod-staten
vóór/na merge, resterende minors.
