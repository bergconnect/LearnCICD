# Design: versie bepalen met Nerdbank.GitVersioning i.p.v. GitVersion

- Datum: 2026-09-11
- Status: goedgekeurd door gebruiker (alle 3 secties akkoord; aanpak A gekozen; basis `0.1`; alleen bepaling, geen stamping)
- Scope: `version`-job van GitVersion-actions naar nbgv-tool; `version.json` nieuw, `GitVersion.yml` weg. Job-output `semVer` blijft — `publish` en al het andere werken ongewijzigd door.

## 1. `version.json` nieuw, `GitVersion.yml` weg

- Nieuw bestand `version.json` in repo-root:
```json
{
  "version": "0.1",
  "publicReleaseRefSpec": [
    "^refs/heads/main$"
  ]
}
```
Basis `0.1` → versies als `0.1.<height>` (logisch vervolg op de `0.0.1-xx`-tags); `main` is de enige public-release-ref, dus builds op `main` krijgen stabiele nummers en PR-builds een pre-release-label. Expliciet vastgelegd, geen impliciete defaults.
- `GitVersion.yml` wordt **verwijderd** — dood gewicht dat alleen maar verwarring zaait naast NB.GV.
- NB.GV telt git-height, dus `fetch-depth: 0` in de `version`-job blijft staan (ongewijzigd).

## 2. `version`-job ombouw (nbgv-tool + outputs)

De `version`-job (`name: Version`, self-hosted, `fetch-depth: 0`, `DOTNET_INSTALL_DIR` — alle drie blijven) wordt:

1. `actions/checkout@v4` + `actions/setup-dotnet@v4` (beide ongewijzigd — dotnet-CLI is nodig voor de tool).
2. **Weg**: `gittools/actions/gitversion/setup@v4` + `execute@v4` (inclusief `versionSpec`).
3. **Nieuw**: `.config/dotnet-tools.json` (tool-manifest met gepinde nbgv-versie — exacte versie bij implementatie na verificatie, zoals altijd) + stappen `dotnet tool restore` en `dotnet nbgv get-version -v SemVer2` → via `$GITHUB_OUTPUT` naar step-output, gemapt op de **bestaande** job-output `semVer`.
4. Display-stap toont de berekende versie (zelfde rol als nu).

Cruciaal: de job-output blijft `semVer` heten met een strikte SemVer-waarde (NB.GV `SemVer2`, géén `+metadata` — Docker-tags mogen geen `+` bevatten). Daardoor hoeft **niets** downstream te veranderen: `publish` blijft `needs.version.outputs.semVer` lezen.

## 3. Validatie, foutafhandeling & scope

- **Lokale validatie vóór de PR** (verplicht, op feature-branch): nbgv-versie pinnen pas ná bewijs — `dotnet tool restore` + `dotnet nbgv get-version -v SemVer2` lokaal draaien op een kloon met volledige historie; verwacht een `0.1.<height>`-vorm zonder GitVersion-restanten. `yamllint` op de workflow (exit 0, alleen de 2 bekende warnings).
- **CI-bewijs**: na merge via PR moeten alle checks groen zijn; in de `Version`-log staat een `0.1.x`-versie en de `publish`-job tagt daarmee (eerste NB.GV-image in Gitea als eindbewijs, zoals bij eerdere trajecten via UI-controle).
- **Foutafhandeling**: ongewijzigd mechanisme — geen `needs` tussen `version`/`test`/`security`; `publish` alleen achter groene `test` + berekende versie. Faalt nbgv (bv. ontbrekende history), dan faalt alleen `Version` rood.
- **Buiten scope**: assembly-stamping (geen `PackageReference`, assemblies byte-identiek), `cloudBuild`-nummering, `publicReleaseRefSpec` uitbreiden naar andere branches, GitVersion volledig uit documentatie verwijderen behalve historische specs, Dependabot, registry-wijzigingen.

## 4. Doorgroei

Zodra dit staat: assembly-stamping aanzetten als versies in de binaries zelf nodig zijn (`PackageReference` + stamping vlaggen), `cloudBuild`-gebaseerde buildnummers, en op termijn GitVersion-verwijzingen uit oude specs opschonen.
