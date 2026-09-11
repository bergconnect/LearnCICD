# Scalar API Documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Voeg OpenAPI-generatie + Scalar-UI (dev-gated) toe aan de API, met een contract-test die het document valideert.

**Architecture:** Twee packages in `Api.csproj`, zes regels in `Program.cs` (dev-gate), één test erbij. Daarna PR-validatie + merge; CI bewijst 2/2 groene tests. Alles hieronder is op 2026-09-11 lokaal bewezen op een identieke probe-app: packageversies, 0-warning-build, `/openapi/v1.json` met `/health`-pad, `/scalar` → 302 → 200 met `-L` in Development, en 404/404/200 (`scalar`/`openapi`/`health`) onder expliciet `ASPNETCORE_ENVIRONMENT=Production`.

**Tech Stack:** `Microsoft.AspNetCore.OpenApi` 10.0.12, `Scalar.AspNetCore` 2.17.3, xunit v3 + MTP (bestaand), `WebApplicationFactory` (draait standaard in `Development`).

## Global Constraints

- `Api.csproj` krijgt exact twee `PackageReference`s: `Microsoft.AspNetCore.OpenApi` Version `10.0.12` + `Scalar.AspNetCore` Version `2.17.3`. Bestaande properties (`net10.0`, `TreatWarningsAsErrors`, enz.) ongewijzigd.
- `Program.cs` wordt exact de vorm uit de spec (using, `AddOpenApi`, `/health`, `IsDevelopment`-gate met `MapOpenApi` + `MapScalarApiReference`, `Run`, partial `Program`).
- Contract-test exact als in de spec (`GetOpenApiDocument_ContainsHealthEndpoint`, met `TestContext.Current.CancellationToken` op beide async-aanroepen — xUnit1051-regel); bestaande test ongewijzigd.
- Lokale app-runs ALTIJD met `--no-launch-profile` (zonder vlag forceert `launchSettings.json` Development en is elk dev-gate-bewijs ongeldig).
- `/scalar` antwoordt met 302 (redirect naar `/scalar/`); volg met `curl -L` voor de 200-check. Dit is normaal Scalar-gedrag, geen fout.
- Build met `TreatWarningsAsErrors` (0 warnings/0 errors vereist); tests via bestaande MTP-opdracht met coverage.
- Werk op feature-branch `feat/scalar-docs`; merge naar `main` uitsluitend via PR met groene checks (branch protection); conventionele commits.
- Nooit secrets in bestanden, logs of output (hier niet van toepassing — geen credentials betrokken).

---

## File Structure

| Bestand | Verantwoordelijkheid |
|---|---|
| `src/Api/Api.csproj` | Twee package-referenties toevoegen |
| `src/Api/Program.cs` | OpenAPI + Scalar registreren (dev-gated) |
| `tests/Api.Tests/HealthEndpointTests.cs` | Contract-test toevoegen |

Al het andere blijft onaangeraakt (geen CI-, Dockerfile-, Helm- of ArgoCD-wijzigingen).

---

### Task 1: Packages, Program.cs, contract-test (lokaal bewezen)

**Files:**
- Modify: `src/Api/Api.csproj` (2 `PackageReference`s toevoegen)
- Modify: `src/Api/Program.cs` (full rewrite, inhoud hieronder)
- Modify: `tests/Api.Tests/HealthEndpointTests.cs` (1 test toevoegen)

**Interfaces:**
- Consumes: bestaande `/health`-endpoint + `WebApplicationFactory`-fixture (ongewijzigd).
- Produces: bouwende API met dev-gated docs + 2/2 groene tests. Task 2 valideert op GitHub.

- [ ] **Step 1: Add the two package references to `src/Api/Api.csproj`**

```xml
  <ItemGroup>
    <PackageReference Include="Microsoft.AspNetCore.OpenApi" Version="10.0.12" />
    <PackageReference Include="Scalar.AspNetCore" Version="2.17.3" />
  </ItemGroup>
```

- [ ] **Step 2: Overwrite `src/Api/Program.cs`**

```csharp
using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddOpenApi();
var app = builder.Build();

app.MapGet("/health", () => Results.Ok("Healthy"));

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

app.Run();

public partial class Program { }
```

- [ ] **Step 3: Append the contract test to `tests/Api.Tests/HealthEndpointTests.cs`**

Voeg na de bestaande testmethode toe (zelfde klasse, zelfde `_client`):

```csharp
    [Fact]
    public async Task GetOpenApiDocument_ContainsHealthEndpoint()
    {
        var response = await _client.GetAsync("/openapi/v1.json", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken);
        Assert.Contains("/health", body);
    }
```

(`HttpStatusCode` en `Xunit` zijn al via usings beschikbaar; `TestContext` vereist geen using onder v3 ImplicitUsings + `Using Include="Xunit"`.)

- [ ] **Step 4: Restore, build, test**

Run (vanuit repo-root):

```bash
dotnet restore
dotnet build -c Release --no-restore /p:TreatWarningsAsErrors=true
dotnet test -c Release --no-build --coverage --coverage-output-format cobertura
```

Expected: `0 Warning(s)`, `0 Error(s)`; `Passed! - Failed: 0, Passed: 2, Total: 2`; een `*.cobertura.xml` bestaat.

- [ ] **Step 5: Prove dev-gate with local runs (beide kanten)**

Run:

```bash
ASPNETCORE_ENVIRONMENT=Development dotnet run --project src/Api/Api.csproj --no-build --no-launch-profile -c Release --urls http://localhost:18091 > /tmp/opencode/scalar-dev.log 2>&1 &
sleep 6
curl -s -o /dev/null -w "openapi HTTP:%{http_code}\n" http://localhost:18091/openapi/v1.json
curl -sL -o /dev/null -w "scalar HTTP:%{http_code}\n" http://localhost:18091/scalar
```

Expected: `openapi HTTP:200`, `scalar HTTP:200`. Daarna server stoppen (`pkill -f "Api.dll"` of de PID killen).

Run:

```bash
ASPNETCORE_ENVIRONMENT=Production dotnet run --project src/Api/Api.csproj --no-build --no-launch-profile -c Release --urls http://localhost:18092 > /tmp/opencode/scalar-prod.log 2>&1 &
sleep 6
curl -s -o /dev/null -w "scalar HTTP:%{http_code}\n" http://localhost:18092/scalar
curl -s -o /dev/null -w "openapi HTTP:%{http_code}\n" http://localhost:18092/openapi/v1.json
curl -s -o /dev/null -w "health HTTP:%{http_code}\n" http://localhost:18092/health
```

Expected: `scalar HTTP:404`, `openapi HTTP:404`, `health HTTP:200`. Server stoppen, build-artefacten opruimen (`bin`/`obj`/`TestResults`-mappen verwijderen; `git status` toont daarna alleen de 3 bedoelde bestandswijzigingen).

- [ ] **Step 6: Commit**

Run:

```bash
git add src/Api/Api.csproj src/Api/Program.cs tests/Api.Tests/HealthEndpointTests.cs
git commit -m "feat: add Scalar API documentation with OpenAPI (dev-only)"
```

### Task 2: Valideren via GitHub-PR en mergen

**Files:**
- Geen (git-operaties + API-stappen)

**Interfaces:**
- Consumes: Task 1 op branch `feat/scalar-docs` (schoon, gepusht).
- Produces: groene CI op PR én bewijs dat `Test (.NET)` 2 tests bevat; `main` bevat de wijziging na merge; branches opgeruimd.

- [ ] **Step 1: Push and open a PR `feat/scalar-docs` → `main`**

Run:

```bash
git push -u origin feat/scalar-docs
```

Open daarna de PR (github.com of API). Titel: `feat: add Scalar API documentation with OpenAPI (dev-only)`. Niet mergen vóór Step 3.

- [ ] **Step 2: Confirm PR checks and the 2-test proof**

Expected op de PR: `Test (.NET)` ✅, `Version` ✅, `Security scan` ✅ (`Docker build` bestaat niet meer; `Publish image` **skipped** — correct gedrag, geen fout). Lees in de `Test (.NET)`-log dat `Total: 2` tests draaiden (het bewijs dat de contract-test meedoet).

- [ ] **Step 3: Merge and clean up**

Merge de PR via GitHub, verwijder de remote branch, daarna lokaal:

```bash
git checkout main
git pull
git fetch --prune origin
git branch -d feat/scalar-docs
git log --oneline -3
```

Expected: `main` bevat de feat-commit plus merge; `git status --short` leeg; `git branch -a` toont alleen `main` + `origin/main` (+ PR-refs).
