# CI/CD-inrichting LearnCICD — replicatie-runbook

Doel: deze inrichting 1-op-1 kunnen herhalen voor een nieuw repo.
Stand: geverifieerd aan live API/cluster op 2026-09-25.
Taal: Nederlands (repo-conventie).

## 1. Architectuur in één beeld

Eén repo (`bergconnect/LearnCICD`) bevat alles: code, infra,
workflows én herbruikbare templates (vendored, harde fork —
`bergconnect/cicd-workflows` is bevroren geschiedenis en wordt
niet meer gebruikt).

```
push naar main ──► CI ──► CD ──► dev (automatisch)
                              │
                              ▼ (handmatig, Actions → Promote)
                        acc / prd (ArgoCD synct)
```

- **CI** (`CD`? nee: `CI`): bij elke PR naar `main`. Matrix per
  project (Api, Worker + Shared-tests), build + tests.
- **CD** (`cd.yml`): bij elke push naar `main` (behalve
  infra/docs-only). Bouwt + publiceert images, bumpt
  `values_dev.yaml` via auto-PR, ArgoCD synct `dev`.
- **Promote** (`promote.yml`): alleen handmatig (`workflow_dispatch`,
  `project` + `version` verplicht, `environment` verplicht zónder
  default). Valideert → kopieert image → bumpt
  `values_<env>.yaml` → auto-PR → ArgoCD synct `acc`/`prd`.

Alle drie callers zijn dun: echte logica zit in lokale herbruikbare
workflows (`.github/workflows/*-template.yml`) en composite actions
(`.github/actions/*/`), aangeroepen via `./.github/...`-refs
(repo-root-relatief — kale `./<f>` of `../actions/` zijn ONGELDIG
en geven stil 0 jobs).

## 2. Workflows in detail

`.github/workflows/`:

| Bestand | Trigger | Doet |
|---|---|---|
| `ci.yml` | `pull_request → main` | Roept `ci-template.yml` aan (changes → matrix verify) |
| `cd.yml` | `push → main` (`paths-ignore`: `.infra/**`, `argocd/**`, `docs/**`, `*.md` e.d.) | Roept `cd-dev-template.yml` aan (detect → versions → publish → dev-bump) |
| `promote.yml` | Alleen `workflow_dispatch` (`project`, `version`, `environment` alle verplicht; env-opties `[acc, dev, prd]`, acc vooraan) + `run-name` met project/versie/env | Roept `promote-template.yml` aan |
| `ci-template.yml` | Reusable (lokaal) | `changes` → `verify-project`-matrix → `Verify`-gate |
| `cd-dev-template.yml` | Reusable (lokaal) | Detect → determine-versions → publish → update-tag (dev) |
| `promote-template.yml` | Reusable (lokaal) | Validate (SemVer + registry) → copy-image (alleen prd/acc) → promote (bump + auto-PR) |

`.github/actions/` (composites, lokaal aangeroepen):

- `detect-changed-projects` — leest `.github/projects.json`,
  matcht gewijzigde bestanden op `paths`/`test-paths`, respecteert
  `_global.select-all`/`ignore`. Output: project-matrix (leeg = skip).
- `dotnet-setup` — SDK uit `global.json`, restore/tools.
- `bump-image-tag` — bumpt image-tag in `values_<env>.yaml`,
  opent auto-PR (gesigneerd door bot, automerge aan).

Harde caller-regels (bewezen breekbaar, niet aan tornen):

- Géén top-level `concurrency` op callers (GitHub expandeert dan
  géén reusable jobs: run faalt direct met 0 jobs, géén foutmelding).
  Concurrency-blokken horen IN de template.
- Géén job-`name:` op callers; `secrets: inherit` overal.
- `run: >` (NOOIT `run: |` bij multi-line `$(...)` — exit 127).
- Max 80 kolommen; `yamllint` kent alleen `document-start` +
  `truthy`-op-`on:` als acceptabel.

## 3. Project-manifest (`.github/projects.json`)

```json
{
  "Api":    {"image_name": "...-api", "chart": "...",
             "paths": ["src/Api/**"], "test-paths": ["tests/Api.Tests/**"]},
  "Worker": {"image_name": "...", "chart": "...",
             "paths": ["src/Worker/**"], "test-paths": ["tests/Worker.Tests/**"]},
  "_global": {"select-all": ["global.json", "version.json", "*.sln",
    "Directory.*", ".github/workflows/ci.yml", ".../ci-template.yml",
    ".../cd.yml", ".../cd-dev-template.yml", ".../promote.yml",
    ".../promote-template.yml"],
    "ignore": [".infra/**", "argocd/**", "docs/**", "**/*.md", ...]}
}
```

- `src/Shared/**` valt onder Worker (paths én test-paths).
- Elke template-mutatie triggert volledige matrix (select-all) —
  zo hoort het bij gedeelde code.
- Onbekende paden → genegeerd (strict); leeg → `[]` (lege matrix,
  Verify slaat over zonder merge te blokkeren).

## 4. Versiebeheer (NBGV)

- Per project `src/<P>/version.json`: `{version: 0.<N>,
  pathFilters, publicReleaseRefSpec: [^refs/heads/main$]}`.
  Tags komen uit `dotnet nbgv get-version -v SemVer2` per projectdir
  (centrale `determine-version`-job).
- `pathFilters` staan in het bestand zelf; relatieve én absolute
  vormen bestaan (`../sibling`, `/src/Shared`).
- **Bewezen les:** `pathFilters`-wijzigingen gelden pas vanuit
  COMMITTED state (uncommitted edits tellen niet mee); sibling-vormen
  deden niets totdat committed getest. Worker telt Shared mee via
  `[".", "/src/Shared"]` (Api raakt Worker niet).
- Shared-only wijziging zonder versie-impact = stille non-deploy
  (zelfde tag, nieuwe digest) — daarom MOET elke dependency in de
  filters staan.
- `global.json` (`10.0.100` + `latestFeature`) is de ENIGE
  SDK-versiebron; CI leest hem uit.

## 5. Omgevingen

| Env | Trigger | Gate | Registry | Namespace |
|---|---|---|---|---|
| `dev` | automatisch (push) | geen | oud (`192.168.2.70:3004`) | `dev` |
| `acc` | handmatig (Promote) | Environment `acc`, geen reviewers | nieuw (`192.168.2.100:3003`) | `acc` |
| `prd` | handmatig (Promote) | Environment `prd`, geen reviewers | nieuw | `prd` |

GitHub Environments `acc`/`dev`/`prd` bestaan; `acc`+`prd` zonder
reviewers (bewuste start = voldoende), `dev` zonder gate.
Gelijktijdige Promote-dispatches cancellen elkaar
(`cancel-in-progress`) — ALTIJD sequentieel starten.

## 6. Registries

- Bron (CI publish): `go.berg-connect.nl` / `192.168.2.70:3004`
  (oude Gitea; `vars.GITEA_LOCAL`, repo `beheerder`).
- Doel (prd/acc): `192.168.2.100:3003` (plain HTTP, auth verplicht).
  Copy-stap dupliceert + verifieert per digest (v13-harden; later
  versimpeld naar tag-copy zonder digest-checks op expliciet verzoek).
- Kubelet-mirror staat in `/etc/rancher/k3s/registries.yaml` op de
  node (`endpoint http://192.168.2.100:3003`); k3s herstart nodig na
  wijziging.
- Env-vars sturen per omgeving (environment-vars winnen van
  repo-vars): `dev` heeft `GITEA_LOCAL` + `GITEA_SOURCE_REPOSITORY`,
  `acc`/`prd` hebben `GITEA_DST_REGISTRY_HOST` +
  `GITEA_DST_REPOSITORY`. Templates declareren `environment:` zodat
  dit resolveert.

## 7. Secrets & vars (namen + plaats + doel; NOOIT waarden in git)

Repo-secrets (`Settings → Secrets → Actions`, alle 4 vereist):

| Secret | Doel | Aanmaken/roteren |
|---|---|---|
| `GITEA_TOKEN` | Pull/push oude registry (CI, copy-source) | Gitea `beheerder` → token met package-rechten; bij rotatie: secret bijwerken, node-docker-config controleren |
| `GITEA_DST_TOKEN` | Push nieuwe registry (copy-dest) | Zelfde, op `192.168.2.100:3003`; zonder deze faalt elke prd/acc-copy met `GITEA_DST_TOKEN ontbreekt` |
| `GH_PAT` | Auto-PR aanmaken/mergen + API-aanroepen (`repo` + `workflow`-scopes); ook credential-helper lokaal | GitHub PAT; minimaal maandelijks rouleren; nergens plakken behalve credential store |
| `BOT_GPG_PRIVATE_KEY` | Ondertekenen bot-commits (auto-PR/bump) | Eigen GPG-sleutel exporteren (zie §8); roteren = nieuwe subkey + var hieronder |

Repo-vars (`Settings → Variables → Actions`):

| Var | Waarde(vorm) | Doel |
|---|---|---|
| `GITEA_USER` | `beheerder` | Registry-gebruiker |
| `GITEA_HOST` | `go.berg-connect.nl` | Oude host (naam) |
| `GITEA_LOCAL` | `192.168.2.70:3004` | Oude host (adres; env-`dev` overschrijft) |
| `BOT_GPG_KEYID` | subkey-ID (zie `gpg --list-secret-keys`) | Welke sleutel de bot gebruikt |

Geen environment-secrets; environment-vars zie §6.
Rotatie-volgorde: nieuwe credential aanmaken → secret/var bijwerken →
rookproef (negatieve Promote-dispatch) → oude intrekken.

## 8. Signed commits

- Ruleset `main` eist `required_signatures`: ELKE commit op `main`
  (ook bot-commits) moet geldig gesigneerd zijn.
- Bot: eigen ed25519-key, UID op `users.noreply.github.com`-vorm
  (anders `verified: False/no_user`); private key in
  `BOT_GPG_PRIVATE_KEY`, keygrip in `BOT_GPG_KEYID`.
- Mensen: eigen GPG-key + `git config commit.gpgsign true`;
  details en Windows-notities in `docs/gpg-keys.md`.
- Valkuil: regels-overschrijdende legacy API (`/branches/.../protection`)
  toont leeg — waarheid staat in rulesets (`/rulesets`).

## 9. Branch protection (ruleset `main`, actief)

- Alleen via PR (`deletion` + `non_fast_forward` geblokkeerd:
  geen deletie/force-push van `main`, ook niet voor owner).
- Verplichte check `ci / Verify` + **strict** (PR-branch moet
  up-to-date zijn; `behind` → eerst bijtrekken via merge).
- PR-regel zonder verplichte reviewers (0 approvals).
- `delete_branch_on_merge` aan (remote takken ruimen zichzelf op).

## 10. ArgoCD + cluster

- Per project per env een Application in `argocd/applications/`
  (`<chart>-<env>.yaml`): `targetRevision: HEAD`, `CreateNamespace`
  + `selfHeal` aan, `prune` aan, valueFiles `values.yaml` +
  `values_<env>.yaml`.
- Namespaces `dev`/`acc`/`prd` (11d+ oud); nooit `devtest`/`productie`
  meer (opgeruimd).
- Pull-secret `gitea-registry` komt uit chart-template
  `pullsecret.yaml` (SealedSecret, cluster-wide blob, BEIDE registries
  erin). Controller draait in `kube-system`. Eis na bootstrap:
  type `kubernetes.io/dockerconfigjson`, ownerRef SealedSecret,
  `Synced=True`. SealedSecret eerst aanmaken, dán pas werkt de sync.
- Cosmetica (geen actie): apps die één SealedSecret delen tonen
  soms `OutOfSync` bij 0 afwijkende resources (dual-ownership flap);
  `Healthy` + lopende pods = goed.
- ImagePullBackOff-betekenis: `401` = secret stuk; `not found` /
  `MANIFEST_UNKNOWN` = auth OK, tag ontbreekt (bewuste testmethode
  met onbestaande tag).

## 11. Runner (`github-runner`)

- Self-hosted, labels `self-hosted, Linux, X64`; ALLE jobs draaien
  erop (`runs-on: [self-hosted]`).
- Vereist: Docker-daemon + Buildx (nesting aan, geen privileges),
  Skopeo, .NET komt via `setup-dotnet` in `DOTNET_INSTALL_DIR`
  (runner-user mag `/usr/share/dotnet` niet schrijven).
- Offline = alles queue't voor eeuwig (geen timeout). Eerst kijken
  bij hangende runs. Node-reboot? Runner-service herstarten.

## 12. Conventies (hard)

- Conventionele commits (`feat:`, `fix:`, `ci:`, `chore:`, `docs:`,
  `test:`); nooit direct op `main`.
- Lokaal valideren vóór PR (zelfde als CI): restore, build Release
  met warnings-as-errors, test met coverage, `docker build`,
  `yamllint` (2 bekende warnings oké).
- Bewijsvoering: negatieve dispatch (onbestaande versie → rood
  zonder PR) vóór elke positieve; pull-bewijs (pod draait tag).
- Versies nooit mixen (één tag per repo-stand, nu: geen — lokaal).
- Scaffolding nieuwe service: `scripts/new-project.sh <Naam>`
  (droogtest + volledige cleanup verplicht); details
  `docs/nieuwe-service.md`.

## 13. Replicatie-checklist (volgorde)

1. Repo aanmaken + `main` beschermen via ruleset (kopieer §9:
   PR-only, `ci / Verify` strict, signatures aan).
2. Runner registreren (`github-runner`-equivalent) en ONLINE brengen.
3. Secrets + vars uit §7 aanmaken (Gitea-tokens eerst valideren met
   `curl .../v2/` → 200).
4. Bot-GPG-key genereren, `BOT_*` vullen, eigen key configureren (§8).
5. `.github/`-skelet kopiëren (workflows + actions + `projects.json`
   aanpassen: namen, image-names, paths) + `global.json` +
   `version.json` per project (filters inclusief gedeelde dirs!).
6. Environments `dev`/`acc`/`prd` + env-vars uit §6.
7. Charts + `values_<env>.yaml` + ArgoCD-apps + namespace-bootstrap
   + SealedSecret-verificatie (§10).
8. Rookproef: CI op probe-PR → CD naar dev → negatieve Promote →
   Promote naar acc (sequentieel!) → pull-bewijs → Promote naar prd.
9. `registries.yaml` + mirror-check op nodes; runner-vereisten (§11).

## 14. Bekende valkuilen (top)

1. `TAG="$VER"` zonder `export` → lege tags (strenv).
2. `run: |` met multi-line `$(...)` → exit 127 (altijd `run: >`).
3. Kale `./<f>` / `../actions/`-refs → stil 0 jobs (alleen
   `./.github/...`-vorm is geldig).
4. Top-level `concurrency` op callers → 0 jobs zonder fout.
5. `behind` op PR → eerst main mergen (strict-beleid).
6. Gelijktijdige dispatches cancellen elkaar → sequentieel.
7. Same-tag-republish → digest-divergentie (CI bouwt opnieuw onder
   gelijke tag); vlag als het bijt, niet als theorie.
8. Trailing spatie in versie-input → SemVer-faal (trim inputs).
9. Tags verwijderen terwijl interne pins ernaar wijzen → alles rood
   (eerst consolideren, dan pas wissen; SHA-backup).
10. Runner offline / node down → eerst infra checken, dan pas logs.
