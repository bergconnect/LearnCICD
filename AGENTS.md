# AGENTS.md — LearnCICD

Repo: `https://github.com/bergconnect/LearnCICD.git` (public, default branch `main`)
Stack: .NET 10 (SDK gepind via `global.json`), ASP.NET Core minimal API, xunit + Coverlet, Docker (Buildx, `linux/amd64`).

## Git-workflow (verplicht)

- NOOIT direct committen of pushen naar `main` — branch protection weigert dit, ook voor de owner.
- Werk altijd op een feature-branch (`feat/...`, `fix/...`, `chore/...`, `docs/...`, `ci/...`) en merge naar `main` uitsluitend via een GitHub Pull Request.
- Beide verplichte checks moeten groen zijn vóór een merge: `Test (.NET)` en `Docker build`. De PR-branch moet up-to-date zijn met `main` (strict-beleid).
- Force-push en deletie van `main` zijn uitgeschakeld.
- Conventionele commit-messages (`feat:`, `fix:`, `ci:`, `chore:`, `docs:`, `test:`).

## Repo-gegevens (geen secrets in dit bestand)

- Remote: `origin` → `https://github.com/bergconnect/LearnCICD.git`
- Default branch: `main` (beschermd: PR-only, CI-checks verplicht, geen force-push/deletie)
- Lokale git-identiteit: `beheerder` / `info@berg-connect.nl`
- Push-authenticatie loopt via de geconfigureerde credential-helper (PAT met `repo` + `workflow`-scopes). Plak nooit tokens in bestanden, logs of chat, tenzij eenmalig en expliciet gevraagd — en sla ze nergens anders op dan in de credential store.

## Lokaal valideren vóór een PR (zelfde als CI)

```bash
dotnet restore
dotnet build -c Release --no-restore /p:TreatWarningsAsErrors=true
dotnet test -c Release --no-build --collect:"XPlat Code Coverage"
docker build -t app:local .
yamllint .github/workflows/ci.yml   # alleen de 2 bekende warnings zijn oké
```

## Belangrijke conventies

- Images worden nergens gepusht (`push: false`) — alleen lokaal bouwen ter validatie.
- Geen NuGet-caching in CI (de setup-dotnet-cache vereist `packages.lock.json`; zie doorgroei in `docs/superpowers/specs/2026-09-10-github-ci-cd-dotnet-design.md`).
- `.dockerignore` gebruikt `**/`-prefixen — kale `bin/`-/`obj/`-regels sluiten geneste mappen niet uit en breken `publish --no-restore` met `NETSDK1064`.
- Ontwerp- en plan-documentatie leeft onder `docs/superpowers/` (`specs/`, `plans/`).
