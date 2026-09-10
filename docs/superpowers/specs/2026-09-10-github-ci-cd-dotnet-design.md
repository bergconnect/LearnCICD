# Design: GitHub CI/CD workflow — Testen & Docker-image bouwen (.NET 10 Web API)

- Datum: 2026-09-10
- Status: goedgekeurd door gebruiker (alle 4 secties akkoord)
- Scope: PR-validatie voor een ASP.NET Core Web API op .NET 10. Bouwen en testen; images worden (nog) nergens gepusht.

## 1. Architectuur & triggers

Eén workflow-bestand: `.github/workflows/ci.yml`, met twee jobs:

- **`test`** — checkout, .NET 10 SDK setup, restore, build (Release), `dotnet test` met coverage, warnings als errors.
- **`docker`** — `needs: test`, bouwt de Docker-image met de meegeleverde multi-stage Dockerfile, zonder push.

Trigger:

```yaml
on:
  pull_request:
    branches: [main]
```

- Runners: `ubuntu-latest` voor beide jobs.
- Geen secrets, geen environments, geen registry-authenticatie nodig in v1.
- Zichtbaar resultaat op de PR: twee aparte statuschecks (`test` / `docker`).
- Geen path-filters in v1: elke PR naar `main` draait de volledige validatie.

## 2. Test-job (met coverage)

Stappen, in volgorde:

1. `actions/checkout@v4`
2. `actions/setup-dotnet@v4` met .NET 10 SDK. De SDK-versie wordt gepind via een `global.json` in de repo-root, zodat lokaal en CI dezelfde SDK gebruiken.
3. `dotnet restore` met NuGet-package-caching via de ingebouwde cache-optie van `actions/setup-dotnet@v4` voor snellere herhaalde PR-runs.
4. `dotnet build -c Release --no-restore` met `TreatWarningsAsErrors` aan.
5. `dotnet test -c Release --no-build --collect:"XPlat Code Coverage"` (Coverlet, Cobertura-formaat). Het coverage-rapport wordt geüpload als build-artifact via `actions/upload-artifact`, zodat het per PR-run te downloaden is.
6. Geen externe coverage-service (geen Codecov) in v1.

Gedrag bij falen: faalt de build of een test, dan faalt de `test`-job en wordt de `docker`-job overgeslagen (via `needs`).

## 3. Docker-job + Dockerfile

`docker`-job (`needs: test`, `runs-on: ubuntu-latest`):

1. `actions/checkout@v4`
2. `docker/setup-buildx-action` + `docker/build-push-action` met `push: false`, `context: .`, lokale tag `app:pr-${{ github.event.number }}`.
3. De build faalt bij Dockerfile- of compileerfouten, wat resulteert in een rode `docker`-statuscheck op de PR.

Meegeleverde multi-stage `Dockerfile` (naast de `.csproj` van de Web API):

- Stage `build`: `mcr.microsoft.com/dotnet/sdk:10.0` — restore, daarna `dotnet publish -c Release -o /app/publish`.
- Stage `final`: `mcr.microsoft.com/dotnet/aspnet:10.0` — non-root user, `ENTRYPOINT ["dotnet", "<Api>.dll"]` (waarbij `<Api>` bij implementatie vervangen wordt door de werkelijke assembly-naam van de Web API), `EXPOSE 8080`.
- Plus een `.dockerignore` met `bin/`, `obj/`, `.git/`, `.vs/` zodat de build-context klein blijft.

Bewuste v1-beperkingen: alleen `linux/amd64` (geen multi-arch), geen registry-push, geen image-scan (zoals Trivy). Deze komen pas aan bod zodra images daadwerkelijk gepubliceerd worden.

## 4. Foutafhandeling, caching & validatie

- **Foutafhandeling**: build met `TreatWarningsAsErrors`; falende tests blokkeren de docker-job via `needs: test`; alle stappen fail-fast (geen `continue-on-error` in v1).
- **Caching**: NuGet-packages worden gecachet tussen runs. Docker layer-caching is bewust uitgesloten in v1 (zonder registry voegt GHA-cache voor layers complexiteit toe zonder evenredige winst).
- **Versiepinning**: GitHub Actions gepind op major-versie (`@v4`); .NET SDK gepind via `global.json`; .NET base-images gepind op `10.0` (geen `latest`).
- **Validatie van de workflow zelf**: na implementatie een test-PR openen met een minimale .NET 10 Web API + testproject en controleren dat beide checks groen zijn; daarna een PR met een bewust falende test om te bevestigen dat `docker` wordt overgeslagen.

## 5. Buiten scope (v1)

- Pushen naar een registry (GHCR, Docker Hub, ACR).
- Multi-arch builds, image signing (cosign), vulnerability scanning.
- Coverage-gates (minimum percentage) en externe coverage-diensten.
- CD/deploy naar een omgeving.
- `dotnet format`- of lint-checks.

## 6. Doorgroei

Zodra publiceren nodig is: `docker`-job uitbreiden met registry-login + `push: true` (alleen op `push` naar `main`/tags, niet op PRs), layer-caching aanzetten, en desgewenst Trivy-scan en Codecov toevoegen. Dit volgt het pad van aanpak C uit de brainstorm.
