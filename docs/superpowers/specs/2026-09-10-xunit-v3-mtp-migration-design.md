# Design: testframework migreren naar xunit v3 + Microsoft.Testing.Platform

- Datum: 2026-09-10
- Status: goedgekeurd door gebruiker (alle 4 secties akkoord; aanpak A gekozen)
- Scope: `tests/Api.Tests` van VSTest/xunit-v2 naar MTP-native xunit v3, met MTP-native coverage. CI blijft `dotnet test` gebruiken. API-project, `Dockerfile` en `docker`-job zijn onaangetast.
- Bronnen: [xunit.net — Microsoft Testing Platform (v3)](https://xunit.net/docs/getting-started/v3/microsoft-testing-platform), [xunit.net — Code Coverage with MTP](https://xunit.net/docs/getting-started/v3/code-coverage-with-mtp), [Microsoft Learn — NUnit runner intro](https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-nunit-runner-intro) (aanleiding; NUnit zelf is niet gekozen).

## 1. Testproject-migratie (`tests/Api.Tests/Api.Tests.csproj`)

Van VSTest naar MTP-native xunit v3:

- **Verwijderen**: `xunit` 2.9.3, `xunit.runner.visualstudio` 3.1.4, `Microsoft.NET.Test.Sdk` 17.14.1, `coverlet.collector` 6.0.4. Alle vier zijn VSTest-gebonden; zonder deze packages zit er geen VSTest meer in de keten.
- **Toevoegen**: `xunit.v3` (huidige 3.x-lijn) als enig framework-package, plus `Microsoft.Testing.Extensions.CodeCoverage` voor coverage. `Microsoft.AspNetCore.Mvc.Testing` 10.0.12 blijft staan (`IClassFixture`/`WebApplicationFactory` worden op v3 ondersteund).
- **Toevoegen aan `PropertyGroup`**: `<OutputType>Exe</OutputType>` — xunit-v3-testprojecten zijn standalone executables, een harde MTP-eis.
- **Ongewijzigd**: `TargetFramework` (`net10.0`), `Nullable`, `ImplicitUsings`, `TreatWarningsAsErrors`, `IsPackable`, `<Using Include="Xunit" />` en de `ProjectReference` naar `src/Api`.
- Exacte packageversies worden bij implementatie gepind na lokale verificatie (zelfde werkwijze als bij de eerste opzet: eerst bewijzen dat restore/build/test slaagt, dan versies vastleggen) — niet vooraf uit het hoofd overnemen.

## 2. Testcode + `global.json`

- **Testcode** (`tests/Api.Tests/HealthEndpointTests.cs`): functioneel ongewijzigd (zelfde endpoint, zelfde eis `200` + `Healthy`), maar twee regels wijzigen verplicht: de xunit-v3-analyzerregel xUnit1051 eist `TestContext.Current.CancellationToken` bij `GetAsync` en `ReadAsStringAsync` — onder `TreatWarningsAsErrors` is dit een build-error, geen waarschuwing. Usings/namespace blijven staan (`Xunit`-namespace is compatibel met v3). Verder geen wijzigingen.
- **`global.json`**: krijgt een `test`-sectie naast de bestaande SDK-pin. Vereist voor `dotnet test` in MTP-modus op SDK 10; zonder deze sleutel valt `dotnet test` terug op VSTest, en die keten bestaat dan niet meer:

```json
{
  "sdk": {
    "version": "10.0.100",
    "rollForward": "latestFeature"
  },
  "test": {
    "runner": "Microsoft.Testing.Platform"
  }
}
```

## 3. CI-workflow (`test`-job)

Alleen de `test`-job verandert; triggers, runners, `docker`-job, `needs`-gating en artifact-upload blijven staan:

- **Oud**: `dotnet test -c Release --no-build --collect:"XPlat Code Coverage"` (VSTest-collector via Coverlet).
- **Nieuw**: `dotnet test -c Release --no-build --coverage --coverage-output-format cobertura` (MTP CodeCoverage-extensie). Restore- en build-stappen zijn ongewijzigd.
- **Geen `--coverage-output` meegeven**: bij meerdere testprojecten overschrijft elk project elkaars rapport; `dotnet test` kent automatisch unieke bestandsnamen toe. Met één testproject vandaag is dit alvast toekomstvast.
- **Artifact-glob verruimen** van `**/coverage.cobertura.xml` naar `**/*.cobertura.xml`: MTP genereert bestandsnamen als `<guid>.cobertura.xml` (zonder `coverage.`-prefix). Dit is de enige wijziging buiten de test-stap zelf.

## 4. Validatie, foutafhandeling & scope

- **Lokale validatie vóór de PR** (verplicht, op feature-branch): `dotnet restore` → build met `TreatWarningsAsErrors` → `dotnet test -c Release --no-build --coverage --coverage-output-format cobertura` → controleer dat er een `TestResults/*.cobertura.xml` ligt en de MTP-runner (geen VSTest) in de output staat. Daarna `docker build` ongewijzigd als equivalentiebewijs voor de `docker`-job.
- **CI-bewijs**: na merge via PR moeten `Test (.NET)` en `Docker build` groen zijn en het `coverage-report`-artifact een `.cobertura.xml` bevatten — te controleren via de GitHub API, zoals bij PR #1 gedaan.
- **Foutafhandeling**: faalt de build of een test, dan faalt `test` en wordt `docker` overgeslagen (ongewijzigd mechanisme). Geen coverage-drempel in v1 — alleen rapporteren, zoals nu.
- **Buiten scope**: `dotnet run`-variant (aanpak B), NUnit-migratie (aanpak C), coverage-gates, ReportGenerator/HTML-rapporten, `dotnet format`-checks, registry-push. `Dockerfile` en `docker`-job wijzigen niet (alleen het testproject wordt een Exe, en dat wordt niet gecontaineriseerd).

## 5. Doorgroei

Zodra dit staat, zijn de paden open voor: HTML-rapporten via ReportGenerator als artifact, coverage-drempels in CI, en — als publiceren ooit nodig is — dezelfde doorgroei uit de CI-spec (registry-push, Trivy, Codecov).
