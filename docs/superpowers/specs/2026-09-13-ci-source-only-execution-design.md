# Design: CI voert alleen source-code-wijzigingen uit

- Datum: 2026-09-13
- Status: door gebruiker goedgekeurd, aanpak B
- Scope: `.github/workflows/ci.yml`; geen code-, chart-, ArgoCD-, CD- of promotiewijzigingen.

## 1. Architectuur

De CI-workflow blijft op elke pull request naar `main` activeren. De bestaande workflow-level `paths-ignore` voor de drie omgevings-values wordt verwijderd.

Alleen de kostbare jobs worden gefilterd:

- `changes` classificeert gewijzigde paden.
- `Test (.NET)` en `Security scan` draaien alleen wanneer de PR source code bevat.
- Bij alle overige PRs worden deze verplichte checks geskipt; geskipte checks blokkeren de merge niet.

## 2. Source-code-classificatie

`changes` zet `code=true` bij:

- `src/**`
- `tests/**`
- `*.csproj`
- `Dockerfile`
- `Dockerfile.*`
- `global.json`
- `version.json`

`changes` zet `code=false` bij:

- `.github/**`
- `docs/**`
- `*.md`
- `.gitignore`
- `LICENSE`
- `charts/**`
- `argocd/**`

Overige onbekende paden blijven fail-safe `code=true`, zodat een nieuw relevant pad geen CI mist. `.github/**` blijft hooguit observability via de bestaande `workflows`-output; geen enkele job-`if` gebruikt die output meer.

## 3. Dataflow en job-gating

1. `changes` gebruikt op pull requests `git diff --name-only origin/main...HEAD`.
2. `changes` publiceert `code` als `true` of `false`.
3. `test` krijgt `needs: [changes]` en `if: needs.changes.outputs.code == 'true'`.
4. `security` krijgt dezelfde `needs` en `if`.
5. Er komt geen workflow-level `paths:`-allowlist, omdat ontbrekende verplichte checks branch protection zouden blokkeren.

## 4. Foutafhandeling

- `changes` faalt alleen bij een git-fout; de oorzaak is dan zichtbaar in de logs.
- Als `changes` faalt, worden afhankelijke jobs via `needs` geskipt; er wordt geen stil groen resultaat geproduceerd.
- Onbekende paden vallen fail-safe terug op uitvoering.

## 5. Testen en acceptatie

Voor implementatie:

- `yamllint .github/workflows/ci.yml` geeft exit 0 met alleen de bekende warnings.
- YAML-parse controleert de verwijderde `paths-ignore` en de nieuwe `if`-voorwaarden.
- Classificatietests controleren representatieve code-, values-, docs- en workflow-paden.
- CI-bewijs bestaat uit een code-PR met groene checks en een non-code-PR met geskipte maar mergebare checks.

Buiten scope blijven `dorny/paths-filter`, wijzigingen aan runners, secrets, CD, promotie en ArgoCD.
