# CI preview-deploy naar dev Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Elke CI-run deployt bij groene checks zijn PR-code naar gedeelde dev-ns (directe patch, geen git-mutatie).

**Architecture:** Nieuwe `preview`-job in lokale `ci-template.yml` na `Verify`: PR-tag publiceren (zelfde publish-vorm als cd-dev-template) + `kubectl set image` op dev-Deployments. Cluster-toegang via nieuw `KUBECONFIG`-secret (dedicated SA, least privilege).

**Tech Stack:** GitHub Actions (lokaal `ci-template.yml`), `dotnet publish /t:PublishContainer`, skopeo, kubectl, k3s RBAC.

## Global Constraints

- Max 80 tekens per regel in workflows/actions; `run: >` (NOOIT `run: |` bij multi-line `$(...)`).
- Caller-workflows: géén top-level `concurrency`, géén job `name:`; `secrets: inherit`.
- `yamllint`: alleen `missing document start` + `truthy` op `on:` zijn oké.
- NOOIT direct naar `main`: feature-branch + PR, conventionele commits, `m_state: clean` vóór merge.
- Preview raakt NOOIT git (geen values-bump, geen auto-PR) en NOOIT acc/prd (alleen `dev`-namespace, alleen via `kubectl set image`).
- Nieuwe secrets: ALLEEN `KUBECONFIG` (repo-niveau, kubeconfig-file-inhoud); nooit waarden in logs/chat.

---

## File Structure

- `.github/workflows/ci-template.yml` — nieuwe `preview`-job na `Verify` (Task 2)
- Cluster: `ServiceAccount dev-preview-deployer` + `Role` + `RoleBinding` in namespace `dev` (Task 1)
- Repo-secret: `KUBECONFIG` (Task 1)

---

### Task 1: Cluster-toegang (SA + KUBECONFIG-secret)

**Files:** Geen (live-acties op cluster + GitHub-secret)

**Interfaces:**
- Consumes: niets (eerste taak)
- Produces: `KUBECONFIG`-secret; SA kan deployments patchen in `dev`

- [ ] **Step 1: API-endpoint en bestaande SA's vaststellen**

```bash
ssh -o ConnectTimeout=10 192.168.2.46 'kubectl cluster-info 2>/dev/null | head -3; kubectl -n dev get sa 2>/dev/null'
```

Noteer het API-adres (verwacht `https://192.168.2.46:6443`).

- [ ] **Step 2: SA + least-privilege Role aanmaken**

```bash
ssh -o ConnectTimeout=10 192.168.2.46 'kubectl -n dev create sa dev-preview-deployer 2>&1 | head -1'
```

Maak `Role` (inline YAML via `kubectl apply -f -`): `get,list` op
`deployments` + `pods`, `patch` op `deployments`, ALLEEN namespace
`dev`. Bind via `RoleBinding` aan de SA. Niets cluster-breeds
(geen ClusterRole).

- [ ] **Step 3: Kubeconfig bouwen + secret zetten**

Token ophalen (`kubectl -n dev create token dev-preview-deployer
--duration 87600h`), CA uit
`kubectl config view --raw` (zelfde cluster). Bouw minimale
kubeconfig (server uit Step 1, géén andere users/contexts) en zet
als repo-secret `KUBECONFIG` via API (`PUT
/repos/bergconnect/LearnCICD/actions/secrets/KUBECONFIG` met
`key_id` + libsodium-sealed value — haal public key via
`GET .../actions/secrets/public-key`; seal met `nacl`
(`python3 -c` met PyNaCl) of `gh`? GEEN `gh` — PyNaCl-pad).

- [ ] **Step 4: Toegang bewijzen**

```bash
KUBECONFIG=/tmp/prev-test kubectl auth can-i patch deployments -n dev
KUBECONFIG=/tmp/prev-test kubectl auth can-i delete namespaces --all-namespaces
```

Verwacht: `yes` / `no`. Shred het test-bestand. Rapporteer
beide outputs.

---

### Task 2: Preview-job in ci-template

**Files:**
- Modify: `.github/workflows/ci-template.yml` (nieuwe job na `verify`)

**Interfaces:**
- Consumes: Task 1 (`KUBECONFIG` bestaat)
- Produces: PR #<n> met preview-job; `m_state: clean`; NIET zelf mergen

- [ ] **Step 1: Branch + bestaande structuur lezen**

```bash
git fetch origin && git checkout -b feat/ci-preview-dev origin/main
```

Lees VOLLEDIG: `.github/workflows/ci-template.yml` (jobs `changes`
r21, `verify-project` r61, `verify` r123-129 + hun `needs:`/`if:`/
outputs). Noteer exact hoe `verify` slaagt en welke matrix-output
(`needs.detect.outputs.matrix`? of changes-output) de projectenlijst
draagt — hergebruik DIEZELFDE bron.

- [ ] **Step 2: Preview-job toevoegen**

```yaml
  preview:
    name: Preview to dev
    runs-on: [self-hosted]
    needs: [changes, verify-project, verify]
    if: >
      always() &&
      needs.verify.result == 'success' &&
      needs.changes.outputs.matrix != '' &&
      needs.changes.outputs.matrix != '[]'
    timeout-minutes: 15
    permissions:
      contents: read
    strategy:
      fail-fast: false
      matrix:
        release: ${{ fromJSON(needs.changes.outputs.matrix) }}
    env:
      PROJECT: ${{ matrix.release.project }}
      IMAGE_NAME: ${{ matrix.release.image }}
      REGISTRY: ${{ vars.GITEA_LOCAL }}
      REPOSITORY: ${{ vars.GITEA_SOURCE_REPOSITORY }}
    steps:
      - name: Set up .NET
        uses: ./.github/actions/dotnet-setup
        with:
          fetch-depth: 0
          token: ${{ secrets.GH_PAT }}
          restore-tools: 'true'
```

(Pas `needs.*`-namen/matrix-bron EXACT aan op wat Step 1 vond;
bovenstaande is het patroon uit cd-dev-template, geen letterlijke
waarheid voor ci-template.)

Daarna steps (zelfde publish-vorm als cd-dev-template r164-182,
`VER` vervangen door PR-tag):

```yaml
      - name: Build PR-tag
        run: >
          BASE=$(cd "src/$PROJECT" &&
          dotnet nbgv get-version -v SemVer2 |
          cut -d'-' -f1 | cut -d'+' -f1);
          TAG="$BASE-pr${{ github.event.pull_request.number }}.${{ github.run_number }}";
          echo "TAG=$TAG" >> "$GITHUB_ENV";
          dotnet publish "src/$PROJECT/$PROJECT.csproj"
          --os linux --arch x64
          -c Release
          -p:ContainerBaseImage=mcr.microsoft.com/dotnet/aspnet:10.0
          -p:ContainerRepository=$REGISTRY/$REPOSITORY/$IMAGE_NAME
          -p:ContainerImageTag=$TAG
          /t:PublishContainer
          -p:ContainerArchiveOutputPath=/tmp/image-$PROJECT-pr.tar
```

(`ContainerBaseImage`: neem EXACTE waarde uit cd-dev-template
r146 `BASE_IMAGE`-env/input over — niet aannemen.)

```yaml
      - name: Push PR-tag
        run: >
          IMAGE="$REGISTRY/$REPOSITORY/$IMAGE_NAME";
          skopeo copy --tls-verify=false
          --dest-username ${{ vars.GITEA_USER }}
          --dest-password ${{ secrets.GITEA_TOKEN }}
          docker-archive:/tmp/image-$PROJECT-pr.tar:$IMAGE:$TAG
          docker://$IMAGE:$TAG
```

```yaml
      - name: Kubeconfig schrijven
        env:
          KUBECONFIG_DATA: ${{ secrets.KUBECONFIG }}
        run: >
          printf '%s' "$KUBECONFIG_DATA" >
          "$RUNNER_TEMP/kubeconfig-preview" &&
          chmod 600 "$RUNNER_TEMP/kubeconfig-preview" &&
          echo "KUBECONFIG=$RUNNER_TEMP/kubeconfig-preview" >>
          "$GITHUB_ENV"
```

```yaml
      - name: Patch dev-Deployment
        run: >
          DEP=$(kubectl -n dev get deploy -l
          app.kubernetes.io/name=$IMAGE_NAME
          -o jsonpath='{.items[0].metadata.name}');
          [ -n "$DEP" ] ||
          { echo "::error::geen dev-Deployment voor $IMAGE_NAME";
          exit 1; };
          CTR=$(kubectl -n dev get deploy "$DEP"
          -o jsonpath='{.spec.template.spec.containers[0].name}');
          kubectl -n dev set image "deployment/$DEP"
          "$CTR=$REGISTRY/$REPOSITORY/$IMAGE_NAME:$TAG" &&
          kubectl -n dev rollout status "deployment/$DEP"
          --timeout=180s
```

(Deployment-selectie via label is een AANNAME — verifieer tegen
live `kubectl -n dev get deploy --show-labels` en pas aan op
werkelijkheid: deployment-naamvorm is `<release>-<chart>`, bv.
`learncicd-dev-learncicd`. Harde eis: patch ALLEEN namespace
`dev`, ALLEEN het Deployment van DIT project.)

- [ ] **Step 3: Valideer + commit + push + PR**

```bash
yamllint .github/workflows/ci-template.yml   # alleen 2 bekende warnings oké
git add .github/workflows/ci-template.yml
git commit -m "feat: PR-preview deploy naar dev vanuit CI"
git push -u origin feat/ci-preview-dev
```

PR (base `main`), wacht `m_state: clean`. NIET mergen (owner).
Bewijsvoering voor CI-groen: de PR-CI zelf (geen aparte tests;
workflow-YAML kan niet unit-getest worden).

---

### Task 3: Bewijsronde + cleanup

**Files:** Geen (live verificatie; vereist gemergde PR uit Task 2)

**Interfaces:**
- Consumes: Task 2 gemerged (preview-job live op `main`)
- Produces: bewezen preview-cyclus; schone repo

- [ ] **Step 1: Probe-PR met Worker-wijziging**

Minimale Worker-wijziging (1-regel comment in
`src/Worker/Program.cs`), branch `probe/ci-preview`, PR.
Wacht CI: Verify groen → preview-job groen. Noteer PR-tag
(`0.2.x-pr<nr>.<run>`) uit de run-logs.

- [ ] **Step 2: Pod-bewijs in dev**

```bash
ssh -o ConnectTimeout=10 192.168.2.46 'kubectl -n dev get pods -o json' | python3 -c "
import json,sys
for p in json.load(sys.stdin)['items']:
    if 'worker' in p['metadata']['name']:
        print(p['metadata']['name'], '|', p['spec']['containers'][0]['image'].split(':')[-1], '|', p['status']['phase'])"
```

Verwacht: pod draait de PR-tag, `Running`.

- [ ] **Step 3: Merge + self-healing-bewijs**

Laat probe-PR mergen (owner). Wacht CD-run: dev-Deployment terug
op echte versie (`values_dev.yaml`-tag). Herhaal Step-2-check:
pod draait echte tag. Revert NIET nodig (comment was triviaal;
laat staan of revert via PR — kies revert via PR voor schone main).

- [ ] **Step 4: Afronding**

```bash
git checkout main && git pull -q origin main && git status --short
git branch -D feat/ci-preview-dev
```

Rapporteer: probe-PR-nummer, PR-tag, pod-staten vóór/na merge,
resterende minors.
