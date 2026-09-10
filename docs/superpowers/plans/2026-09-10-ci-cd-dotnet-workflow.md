# CI/CD Workflow (.NET 10) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Voeg een GitHub Actions CI-workflow (aanpak B: `test` + `docker` met `needs`) plus multi-stage Dockerfile toe aan deze repo, gevalideerd met een minimale .NET 10 Web API en een xunit-testproject.

**Architecture:** Twee jobs in `.github/workflows/ci.yml` die alleen op PRs naar `main` draaien. `test` bouwt de solution en draait tests met Coverlet-coverage; `docker` bouwt de image met Buildx zonder te pushen en draait alleen bij een geslaagde `test`-job. Omdat de repo nog leeg is, bevat het plan eerst het scaffolden van een minimale API + tests, zodat de workflow vanaf dag één iets echts valideert.

**Tech Stack:** .NET 10 SDK (10.0.1xx), ASP.NET Core minimal API, xunit + Microsoft.AspNetCore.Mvc.Testing + coverlet.collector, Docker Buildx (linux/amd64), GitHub Actions (checkout@v4, setup-dotnet@v4, upload-artifact@v4, setup-buildx-action@v3, build-push-action@v6).

## Global Constraints

- Trigger is uitsluitend `pull_request` naar branch `main` — geen push-trigger, geen tags, geen path-filters in v1.
- Beide jobs draaien op `ubuntu-latest`.
- De `docker`-job pusht nergens naartoe (`push: false`); er zijn geen secrets of environments nodig.
- Alleen `linux/amd64`; geen multi-arch, geen image-scan in v1.
- Actions gepind op major-versie (`@v4`, `@v3`, `@v6`); .NET SDK gepind via `global.json`; base-images gepind op `10.0` (nooit `latest`).
- Build met `TreatWarningsAsErrors`; alle stappen fail-fast (geen `continue-on-error`).
- Coverage-rapport (Cobertura) wordt als artifact geüpload, ook bij falende tests (`if: always()`).
- Commit na elke taak met een conventionele commit-message (`feat:`, `ci:`, `test:`, `docs:`).

---

### Task 1: Solution, SDK-pinning, minimale API + testproject

**Files:**
- Create: `global.json`
- Create: `LearnCICD.sln`
- Create: `src/Api/Api.csproj`
- Create: `src/Api/Program.cs`
- Create: `src/Api/appsettings.json`
- Create: `tests/Api.Tests/Api.Tests.csproj`
- Create: `tests/Api.Tests/HealthEndpointTests.cs`

**Interfaces:**
- Consumes: niets (repo bevat alleen het design doc).
- Produces: solution `LearnCICD.sln` met projecten `src/Api/Api.csproj` (assembly `Api.dll`) en `tests/Api.Tests/Api.Tests.csproj` (referentie naar `Api`); `GET /health` geeft HTTP 200 met body `Healthy`. Latere taken bouwen hierop: `dotnet restore/build/test` zonder argumenten (werken via de solution) en de Dockerfile verwacht `src/Api/Api.csproj`.

- [ ] **Step 1: Create `global.json` (SDK-pinning)**

```json
{
  "sdk": {
    "version": "10.0.100",
    "rollForward": "latestFeature"
  }
}
```

- [ ] **Step 2: Create the solution and projects**

Run:

```bash
dotnet new sln -n LearnCICD
dotnet new web -n Api -o src/Api
dotnet new xunit -n Api.Tests -o tests/Api.Tests
dotnet sln LearnCICD.sln add src/Api/Api.csproj tests/Api.Tests/Api.Tests.csproj
```

(De `ProjectReference` en alle `PackageReference`-versies worden in Step 5 exact vastgelegd door de `.csproj` volledig te overschrijven — `dotnet add` is daarvoor niet nodig.)

Expected: alle commando's slagen; `dotnet --version` in de repo-root meldt een `10.0.1xx`-SDK (via `global.json`).

- [ ] **Step 3: Replace `src/Api/Program.cs` with the minimal API**

```csharp
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/health", () => Results.Ok("Healthy"));

app.Run();

public partial class Program { }
```

(`public partial class Program` maakt de app vindbaar voor `WebApplicationFactory<Program>` in de tests.)

- [ ] **Step 4: Replace `src/Api/Api.csproj` (warnings as errors)**

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  </PropertyGroup>

</Project>
```

(De `dotnet new web`-template voegt geen package-referenties toe, dus na deze vervanging zijn er geen NuGet-packages meer nodig voor de API zelf.)

- [ ] **Step 5: Overwrite `tests/Api.Tests/Api.Tests.csproj`**

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <IsPackable>false</IsPackable>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="coverlet.collector" Version="6.0.4" />
    <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.0.12" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.14.1" />
    <PackageReference Include="xunit" Version="2.9.3" />
    <PackageReference Include="xunit.runner.visualstudio" Version="3.1.4" />
  </ItemGroup>

  <ItemGroup>
    <Using Include="Xunit" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\..\src\Api\Api.csproj" />
  </ItemGroup>

</Project>
```

- [ ] **Step 6: Delete the template test and write `tests/Api.Tests/HealthEndpointTests.cs`**

Run: `rm tests/Api.Tests/UnitTest1.cs` (bestaat alleen als de template hem aanmaakte).

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
        var response = await _client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadAsStringAsync();
        Assert.Contains("Healthy", body);
    }
}
```

- [ ] **Step 7: Run restore, build and test locally**

Run:

```bash
dotnet restore
dotnet build -c Release --no-restore /p:TreatWarningsAsErrors=true
dotnet test -c Release --no-build --collect:"XPlat Code Coverage"
```

Expected: `0 Warning(s)`, `0 Error(s)`; `Passed! - Failed: 0, Passed: 1, Total: 1`; een bestand `tests/Api.Tests/TestResults/*/coverage.cobertura.xml` bestaat.

- [ ] **Step 8: Commit**

```bash
git add global.json LearnCICD.sln src tests
git commit -m "feat: add minimal .NET 10 Web API with health endpoint and tests"
```

### Task 2: Dockerfile + .dockerignore (lokaal geverifieerd)

**Files:**
- Create: `Dockerfile` (repo-root, naast de solution)
- Create: `.dockerignore`

**Interfaces:**
- Consumes: `src/Api/Api.csproj` en `Program.cs` uit Task 1 (assembly-naam `Api`, dus `ENTRYPOINT` verwijst naar `Api.dll`).
- Produces: reproduceerbare image-build `docker build -t app:local .` en een draaiende container waarop `GET /health` HTTP 200 met `Healthy` geeft. De `docker`-job in Task 4 gebruikt exact dit bestand.

- [ ] **Step 1: Write `Dockerfile`**

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY src/Api/Api.csproj src/Api/
RUN dotnet restore src/Api/Api.csproj
COPY src/Api/ src/Api/
WORKDIR /src/src/Api
RUN dotnet publish -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
EXPOSE 8080
COPY --from=build /app/publish .
USER app
ENTRYPOINT ["dotnet", "Api.dll"]
```

- [ ] **Step 2: Write `.dockerignore`**

```dockerignore
**/bin/
**/obj/
**/out/
**/TestResults/
.git/
.vs/
.vscode/
*.user
```

(Let op: `**/`-prefix is verplicht — kale `bin/`- of `obj/`-regels sluiten geneste mappen niet uit, waardoor lokale build-artefacten de restore in de container overschrijven en `publish --no-restore` faalt met `NETSDK1064`. Dit is tijdens het opstellen van dit plan lokaal gereproduceerd en met deze inhoud verholpen.)

- [ ] **Step 3: Build the image locally**

Run:

```bash
docker build -t app:local .
```

Expected: build slaagt (`naming to docker.io/library/app:local`).

- [ ] **Step 4: Run the container and hit the health endpoint**

Run:

```bash
docker run -d --rm -p 18080:8080 --name api-check app:local
sleep 5
curl -s -w "\n%{http_code}\n" http://localhost:18080/health
docker stop api-check
```

Expected: body `Healthy` en statuscode `200`.

- [ ] **Step 5: Commit**

```bash
git add Dockerfile .dockerignore
git commit -m "feat: add multi-stage Dockerfile and .dockerignore for the API"
```

### Task 3: CI-workflow met `test`-job

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `LearnCICD.sln`, `global.json` (setup-dotnet leest de SDK-versie hieruit — géén `dotnet-version`-input nodig) en de testopdracht uit Task 1.
- Produces: workflow `CI` met job `test` die op `pull_request` naar `main` restore → build (warnings as errors) → test met coverage → coverage-artifact uploadt. Task 4 voegt hier de `docker`-job aan toe.

- [ ] **Step 1: Write `.github/workflows/ci.yml` (alleen de test-job)**

```yaml
name: CI

on:
  pull_request:
    branches: [main]

jobs:
  test:
    name: Test (.NET)
    runs-on: ubuntu-latest
    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up .NET SDK
        uses: actions/setup-dotnet@v4

      - name: Restore dependencies
        run: dotnet restore

      - name: Build (Release)
        run: dotnet build -c Release --no-restore /p:TreatWarningsAsErrors=true

      - name: Test with coverage
        run: dotnet test -c Release --no-build --collect:"XPlat Code Coverage"

      - name: Upload coverage report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: "**/coverage.cobertura.xml"
```

- [ ] **Step 2: Validate the YAML syntax**

Run:

```bash
yamllint .github/workflows/ci.yml; echo "exit=$?"
```

Expected: `exit=0` met hooguit twee onschuldige warnings (`missing document start "---"` en `truthy value should be one of [false, true]` bij `on:` — beide zijn normaal voor GitHub Actions-workflows).

- [ ] **Step 3: Replay the job steps locally (zelfde commando's als CI)**

Run:

```bash
dotnet restore
dotnet build -c Release --no-restore /p:TreatWarningsAsErrors=true
dotnet test -c Release --no-build --collect:"XPlat Code Coverage"
```

Expected: zelfde resultaat als Task 1, Step 7 (geen warnings/errors, 1 test geslaagd, Cobertura-bestand aanwezig).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add PR workflow with .NET test job and coverage artifact"
```

### Task 4: `docker`-job toevoegen aan de workflow

**Files:**
- Modify: `.github/workflows/ci.yml` (voeg `docker`-job toe; `test`-job blijft ongewijzigd)

**Interfaces:**
- Consumes: `Dockerfile` + `.dockerignore` uit Task 2 en de `test`-job uit Task 3.
- Produces: volledige workflow met jobs `test` en `docker` (`needs: test`, `push: false`, tag `app:pr-${{ github.event.number }}`). Task 5 valideert beide jobs op een echte PR.

- [ ] **Step 1: Append the `docker` job to `.github/workflows/ci.yml`**

Voeg onder de `test`-job (zelfde inspringniveau als `test:`) toe:

```yaml
  docker:
    name: Docker build
    runs-on: ubuntu-latest
    needs: test
    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build image (no push)
        uses: docker/build-push-action@v6
        with:
          context: .
          push: false
          tags: app:pr-${{ github.event.number }}
```

Het volledige bestand is dan de inhoud van Task 3, Step 1 plus dit blok.

- [ ] **Step 2: Validate the YAML syntax**

Run:

```bash
yamllint .github/workflows/ci.yml; echo "exit=$?"
```

Expected: `exit=0`, alleen dezelfde twee onschuldige warnings als in Task 3.

- [ ] **Step 3: Prove the local equivalence of the docker job**

Run:

```bash
docker build -t app:pr-local .
```

Expected: build slaagt. (Dit is exact wat de `docker`-job doet: zelfde `Dockerfile`, zelfde context `.`, alleen zonder push.)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add docker build job gated on test job (no push)"
```

### Task 5: Remote koppelen, pushen en valideren met een echte PR

**Files:**
- Modify: git-remote-configuratie (geen codewijziging)

**Interfaces:**
- Consumes: alle bestanden uit Taken 1–4.
- Produces: een publieke GitHub-repo met branch `main` plus het bewijs dat beide statuschecks (`Test (.NET)`, `Docker build`) groen zijn op een PR. Task 6 gebruikt deze opzet voor de negatieve test.

- [ ] **Step 1: Create the GitHub repo and push `main`**

Maak op github.com een nieuwe (bij voorkeur public) repo aan genaamd `LearnCICD` **zonder** README, `.gitignore` of licentie te laten genereren. Daarna:

```bash
git remote add origin https://github.com/<jouw-GitHub-gebruikersnaam>/LearnCICD.git
git branch -M main
git push -u origin main
```

Expected: `git status` meldt `nothing to commit, working tree clean` en `git branch --show-current` meldt `main`.

- [ ] **Step 2: Open a validation PR**

Run:

```bash
git checkout -b ci/validation
git commit --allow-empty -m "chore: validate CI on test PR"
git push -u origin ci/validation
```

Open daarna op github.com een PR van `ci/validation` naar `main`.

Expected: onder de PR verschijnen twee checks: `Test (.NET)` en `Docker build`.

- [ ] **Step 3: Confirm green checks and inspect artifacts**

Expected: beide checks zijn groen (✅). Download bij de workflow-run het artifact `coverage-report` en controleer dat het een `coverage.cobertura.xml` bevat.

- [ ] **Step 4: Merge the PR and clean up**

Merge via GitHub, daarna lokaal:

```bash
git checkout main
git pull
git branch -d ci/validation
```

Expected: `main` bevat alle commits uit Taken 1–4 plus de validatie-merge.

### Task 6: Negatieve test — falende test slaat `docker` over

**Files:**
- Modify (tijdelijk, op een wegwerpbranch): `tests/Api.Tests/HealthEndpointTests.cs`

**Interfaces:**
- Consumes: de werkende PR-opzet uit Task 5.
- Produces: het bewijs dat `needs: test` werkt (`test` rood, `docker` overgeslagen) en daarna een schone `main` zonder testresten.

- [ ] **Step 1: Open a branch with a deliberately failing test**

Run:

```bash
git checkout -b ci/negative-test
```

Wijzig in `tests/Api.Tests/HealthEndpointTests.cs` één regel:

```csharp
Assert.Contains("Healthy", body);
```

naar:

```csharp
Assert.Contains("DeliberatelyBroken", body);
```

Run:

```bash
git commit -am "chore: negative CI test (do not merge)"
git push -u origin ci/negative-test
```

Open op github.com een PR van `ci/negative-test` naar `main`. **Deze PR mag nooit gemergd worden.**

- [ ] **Step 2: Confirm the gating behavior**

Expected: check `Test (.NET)` is rood (❌) en check `Docker build` is overgeslagen (`skipped`), dankzij `needs: test`.

- [ ] **Step 3: Close the PR without merging and clean up**

Sluit de PR zonder te mergen op github.com en verwijder de remote branch. Daarna lokaal:

```bash
git checkout main
git branch -D ci/negative-test
git status
```

Expected: `nothing to commit, working tree clean` op `main`; de workflow, Dockerfile en tests zijn ongewijzigd (te controleren met `git log --oneline -8`: alleen commits uit Taken 1–4 plus de Task-5-merge).
