# xunit v3 + MTP Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migreer `tests/Api.Tests` van VSTest/xunit-v2 naar MTP-native xunit v3 met MTP-native coverage, zonder de API, Dockerfile of `docker`-job te raken.

**Architecture:** Twee code-taken (testproject + CI-workflow) gevolgd door GitHub-validatie via PR. De migratie verwijdert alle VSTest-packages, maakt het testproject een standalone Exe, schakelt `dotnet test` naar MTP-modus via `global.json`, en verzamelt coverage met `Microsoft.Testing.Extensions.CodeCoverage`. Alle packageversies hieronder zijn op 2026-09-10 lokaal geverifieerd (restore/build/test+coverage groen op SDK 10.0.112).

**Tech Stack:** .NET 10 SDK (10.0.1xx), xunit.v3.mtp-v2 4.0.0, Microsoft.Testing.Extensions.CodeCoverage 18.11.0, Microsoft.AspNetCore.Mvc.Testing 10.0.12, GitHub Actions (alleen `ci.yml`-test-stap + artifact-glob wijzigen).

## Global Constraints

- TargetFramework blijft `net10.0`; `Nullable`, `ImplicitUsings`, `TreatWarningsAsErrors`, `IsPackable=false` blijven aan.
- Geen enkel VSTest-package mag overblijven (`xunit` v2, `xunit.runner.visualstudio`, `Microsoft.NET.Test.Sdk`, `coverlet.collector` worden alle vier verwijderd).
- Testproject wordt een standalone Exe (`<OutputType>Exe</OutputType>`) — harde MTP-eis.
- `global.json` behoudt de SDK-pin (`10.0.100`, `latestFeature`) en krijgt `"test": {"runner": "Microsoft.Testing.Platform"}`.
- CI-trigger, runners, `docker`-job, `needs`-gating en fail-fast blijven ongewijzigd; `push: false` blijft.
- Test-opdracht wordt exact `dotnet test -c Release --no-build --coverage --coverage-output-format cobertura` (géén `--coverage-output`, géén `--collect` meer).
- Artifact-glob wordt exact `**/*.cobertura.xml`.
- Geen coverage-drempels, geen ReportGenerator, geen `dotnet run`-variant.
- Alle `dotnet`-commando's lopen vanuit de repo-root (waar `global.json` ligt — MTP-modus wordt per werkdirectory ontdekt).
- Werk op een feature-branch (`feat/mtp-migration`); merge naar `main` uitsluitend via PR met groene checks (branch protection); conventionele commits.

---

## File Structure

| Bestand | Verantwoordelijkheid |
|---|---|
| `tests/Api.Tests/Api.Tests.csproj` | MTP-package-set + `OutputType Exe` (herschrijven) |
| `tests/Api.Tests/HealthEndpointTests.cs` | Twee `CancellationToken`-argumenten toevoegen (xUnit1051); verder ongewijzigd |
| `global.json` | `test.runner`-sleutel toevoegen naast SDK-pin (herschrijven) |
| `.github/workflows/ci.yml` | Test-stap-flags + artifact-glob (2 regels wijzigen) |

`xunit.runner.json` wordt bewust NIET toegevoegd (optioneel configuratiebestand, YAGNI). `src/Api/*`, `Dockerfile`, `.dockerignore` en de `docker`-job blijven onaangeraakt.

---

### Task 1: Testproject migreren naar xunit v3 + MTP

**Files:**
- Modify: `tests/Api.Tests/Api.Tests.csproj` (full rewrite, inhoud hieronder)
- Modify: `tests/Api.Tests/HealthEndpointTests.cs` (2 regels, inhoud hieronder)
- Modify: `global.json` (full rewrite, inhoud hieronder)

**Interfaces:**
- Consumes: `src/Api` met `Program` (`public partial class Program`) en `GET /health` → `200` + `Healthy` (bestaat, ongewijzigd).
- Produces: testproject dat als MTP-Exe bouwt en slaagt; `TestResults/*.cobertura.xml` na een coverage-run; `global.json` met MTP-runner. Task 2 en 3 bouwen hierop (CI-flags veronderstellen deze packages; validatie veronderstelt een groene lokale run).

- [ ] **Step 1: Overwrite `tests/Api.Tests/Api.Tests.csproj`**

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <OutputType>Exe</OutputType>
    <IsPackable>false</IsPackable>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.0.12" />
    <PackageReference Include="Microsoft.Testing.Extensions.CodeCoverage" Version="18.11.0" />
    <PackageReference Include="xunit.v3.mtp-v2" Version="4.0.0" />
  </ItemGroup>

  <ItemGroup>
    <Using Include="Xunit" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\..\src\Api\Api.csproj" />
  </ItemGroup>

</Project>
```

- [ ] **Step 2: Apply the two xUnit1051 fixes in `tests/Api.Tests/HealthEndpointTests.cs`**

Wijzig exact deze twee regels (de rest van het bestand blijft byte-identiek):

```csharp
        var response = await _client.GetAsync("/health", TestContext.Current.CancellationToken);
```

```csharp
        var body = await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken);
```

Het volledige bestand luidt daarna:

```csharp
using System.Net;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Api.Tests;

public class HealthEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public HealthEndpointTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetHealth_ReturnsOkWithHealthyBody()
    {
        var response = await _client.GetAsync("/health", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken);
        Assert.Contains("Healthy", body);
    }
}
```

(Zonder deze argumenten faalt de build: analyzerregel xUnit1051 is onder `TreatWarningsAsErrors` een error. Dit is tijdens het opstellen van dit plan lokaal gereproduceerd.)

- [ ] **Step 3: Overwrite `global.json`**

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

- [ ] **Step 4: Restore and build from the repo root**

Run (vanuit repo-root):

```bash
dotnet restore
dotnet build -c Release --no-restore /p:TreatWarningsAsErrors=true
```

Expected: `0 Warning(s)`, `0 Error(s)`, exit 0.

- [ ] **Step 5: Run tests with MTP coverage from the repo root**

Run (vanuit repo-root):

```bash
dotnet test -c Release --no-build --coverage --coverage-output-format cobertura
```

Expected (MTP-modus, geen VSTest):
- Regel `Running tests from .../Api.Tests.dll (net10.0|x64)` (géén `VSTest version`-regel).
- `Test run summary: Passed!` met `total: 1, failed: 0, succeeded: 1`.
- Regel `In process file artifacts produced:` met een pad eindigend op `.cobertura.xml`.
- Exit 0.

- [ ] **Step 6: Confirm the coverage file exists**

Run (vanuit repo-root):

```bash
find . -name "*.cobertura.xml"
```

Expected: exact één regel, eindigend op `TestResults/<guid>.cobertura.xml`.

- [ ] **Step 7: Clean artifacts and commit**

Run:

```bash
rm -rf src/Api/bin src/Api/obj "tests/Api.Tests/bin" "tests/Api.Tests/obj" "tests/Api.Tests/TestResults"
git add tests/Api.Tests/Api.Tests.csproj tests/Api.Tests/HealthEndpointTests.cs global.json
git commit -m "test: migrate Api.Tests to xunit v3 on Microsoft.Testing.Platform"
```

Expected: `git status --short` toont daarna niets (`.gitignore` vangt hergenereerde artefacten af).

### Task 2: CI-workflow omzetten naar MTP-coverage

**Files:**
- Modify: `.github/workflows/ci.yml` (exact 2 regels)

**Interfaces:**
- Consumes: Task 1 (MTP-packages + `global.json`-runner; zonder die commit faalt deze CI-config).
- Produces: workflow waarvan de `test`-job MTP-coverage verzamelt en het rapport uploadt. Task 3 valideert dit op GitHub.

- [ ] **Step 1: Change the test step command**

In `.github/workflows/ci.yml`, wijzig:

```yaml
      - name: Test with coverage
        run: dotnet test -c Release --no-build --collect:"XPlat Code Coverage"
```

naar:

```yaml
      - name: Test with coverage
        run: dotnet test -c Release --no-build --coverage --coverage-output-format cobertura
```

- [ ] **Step 2: Widen the artifact glob**

In hetzelfde bestand, wijzig:

```yaml
          path: "**/coverage.cobertura.xml"
```

naar:

```yaml
          path: "**/*.cobertura.xml"
```

(MTP genereert `<guid>.cobertura.xml` zonder `coverage.`-prefix; bestanden kunnen zowel onder `tests/Api.Tests/TestResults/` als onder `bin/<config>/.../TestResults/` belanden — de glob vangt beide.)

- [ ] **Step 3: Validate YAML and commit**

Run:

```bash
yamllint .github/workflows/ci.yml; echo "exit=$?"
```

Expected: `exit=0` met hooguit de twee bekende warnings (`missing document start "---"`, `truthy ... (truthy)` bij `on:`).

Run:

```bash
git add .github/workflows/ci.yml
git commit -m "ci: collect coverage via MTP extension in test job"
```

### Task 3: Valideren via GitHub-PR en mergen

**Files:**
- Geen (git-operaties + browser/API-stappen)

**Interfaces:**
- Consumes: Task 1 + 2 op branch `feat/mtp-migration` (schoon, gepusht).
- Produces: groene CI op een echte PR als bewijs; `main` bevat de migratie na merge; branches opgeruimd.

- [ ] **Step 1: Push the branch**

Run:

```bash
git push -u origin feat/mtp-migration
```

Expected: `[new branch] feat/mtp-migration -> feat/mtp-migration` (auth via credential store; geen output met secrets).

- [ ] **Step 2: Open a PR `feat/mtp-migration` → `main`**

Via github.com of de API. Titel: `test: migrate Api.Tests to xunit v3 on Microsoft.Testing.Platform`. Niet mergen vóór Step 3.

- [ ] **Step 3: Confirm green checks and the coverage artifact**

Expected: checks `Test (.NET)` ✅ en `Docker build` ✅. Download bij de run het artifact `coverage-report` en controleer dat het een bestand `*.cobertura.xml` bevat (geen `coverage.`-prefix vereist).

- [ ] **Step 4: Merge and clean up**

Merge de PR via GitHub (merge-commit), verwijder de remote branch, daarna lokaal:

```bash
git checkout main
git pull
git fetch --prune origin
git branch -d feat/mtp-migration
git log --oneline -4
```

Expected: `main` bevat de twee migratie-commits plus merge; `git status --short` leeg; `git branch -a` toont alleen `main` + `origin/main`.
