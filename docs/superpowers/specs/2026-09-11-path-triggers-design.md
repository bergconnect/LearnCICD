# Design: path-triggers per job (CI draait alleen wanneer nodig)

- Datum: 2026-09-11
- Status: goedgekeurd door gebruiker (alle 3 secties akkoord; aanpak A gekozen; mapping bevestigd)
- Scope: één `changes`-job per workflow (`ci.yml`, `cd.yml`) met `git diff`-classificatie, plus `if:`-gates op alle bestaande jobs. Workflows blijven altijd triggeren; jobs worden geskipt (geskipte checks blokkeren merges niet — ontbrekende checks wel, vandaar géén workflow-level path-filters).

## 1. `changes`-job (één bron van waarheid)

Nieuwe eerste job `changes` (`name: Change detection`) in **beide** workflows:

1. `actions/checkout@v4` met `fetch-depth: 0` (alleen hier nodig voor diff-basis; andere jobs houden shallow).
2. Eén `run:`-stap die bepaalt welke groepen geraakt zijn en ze als job-`outputs` zet (`true`/`false`-strings):
   - Op `pull_request`: `git diff --name-only origin/main...HEAD` (drie-punts — alle PR-commits t.o.v. merge-base).
   - Op `push`: `git diff --name-only <before> <after>` via event-context (alleen de gepushte commits).
   - Groepen (glob-regels, eerste match wint per bestand): `code` = `src/**`, `tests/**`, `*.csproj`, `Dockerfile`, `Dockerfile.*`, `global.json`, `.config/**`, `version.json`; `workflows` = `.github/**`; `docs` = `docs/**`, `*.md`, `.gitignore`, `LICENSE`; `charts`/`argocd` = expliciete no-op-groep (matcht, zet géén vlag — chart-only wijzigingen skippen alles).
   - Onbekende paden vallen terug op `code=true` (fail-safe: liever een run te veel dan een gemiste test). De `docs`-output wordt door geen enkele `if` gebruikt — observability voor logs en toekomstige gates. Bij een push zonder geldige basis (nieuwe branch, `before` = zero-SHA) faalt de diff zichtbaar en skippen afhankelijke jobs via `needs`.
3. Job faalt nooit op inhoud (hooguit op git-fouten zelf); outputs zijn altijd gezet.

## 2. Job-`if`s (CI én CD)

Elke bestaande job krijgt `needs: [changes]` (waar nog niet aanwezig) plus een `if:` op de outputs:

- **CI `test`**: `if: code OR workflows` — draait bij code- én workflow-wijzigingen (workflow-wijzigingen zelf testen is zinloos, maar de check moet *bestaan* voor protection; skippen mag, ontbreken niet).
- **CI `security`**: `if: code OR workflows` — package-wijzigingen zitten in `code` (csproj); zelfde redenering als test.
- **CD `version`**: `if: code OR workflows` — chart-only pushes publiceren geen nieuwe image (geen code veranderd — correct); versie beweegt alleen met code of workflow mee.
- **CD `publish`**: volgt `version` via bestaande `needs` (geen eigen `if` nodig — als `version` skipt, skipt `publish` mee; als `version` draait maar faalt, blokkeert `needs`).
- **CD `update-image-tag`**: idem via `needs` — geen eigen `if`.
- Bestaande event-`if`s (`push`/`pull_request`) en `needs`-ketens blijven staan; de `paths-ignore` op values.yaml blijft (tweede verdedigingslinie voor de breaker).

Effect-voorbeelden: docs-only PR → alle jobs geskipt (mergebaar, geen minuten); chart-only PR → test/security geskipt; code-PR → alles zoals nu.

## 3. Validatie, branch protection & scope

- **Lokale validatie vóór de PR** (verplicht, op feature-branch): `yamllint` op beide workflows (exit 0, alleen de 2 bekende warnings); diff-logica droog testen met `git diff --name-only` op een proefbranch (docs-only → alleen `docs=true`; code-touch → `code=true`).
- **CI-bewijs in twee stappen**: (1) PR met de workflow-wijziging zelf → alle checks groen (de PR raakt workflows = `workflows=true`, dus alles draait); (2) daarna een docs-only proef-PR → alle jobs `skipped`, PR toch mergebaar (bewijst dat geskipte verplichte checks niet blokkeren).
- **Branch protection**: ongewijzigd (`Test (.NET)` + `Security scan` verplicht). Cruciaal uitgangspunt: een *geskipte* verplichte check blokkeert de merge níét (alleen een *ontbrekende* check zou dat doen — vandaar per-job `if`s i.p.v. workflow-filters, en vandaar dat `workflows` altijd alles triggert).
- **Foutafhandeling**: faalt de `changes`-job zelf (bv. geen history), dan worden afhankelijke jobs geskipt via `needs` — fail-safe richting "niets draaien" met zichtbare oorzaak, nooit stil groen.
- **Buiten scope**: `dorny/paths-filter` (niet nodig), concurrency/groeps-annulering aanpassen, scherpere semver-constraints voor de updater, Windows/macOS-runners, monorepo-splitsing.

## 4. Doorgroei

Zodra dit loopt: groepen verfijnen als nieuwe pad-types ontstaan (bv. aparte `helm`-groep bij omgevings-values), en de classificatie hergebruiken voor eventuele extra workflows.
