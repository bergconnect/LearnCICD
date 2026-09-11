# Design: Scalar API-documentatie voor de Web API

- Datum: 2026-09-11
- Status: goedgekeurd door gebruiker (alle 3 secties akkoord; aanpak A gekozen; dev-only docs; contract-test ja)
- Scope: OpenAPI-generatie (`Microsoft.AspNetCore.OpenApi`) + Scalar-UI (`Scalar.AspNetCore`), dev-gated, plus één contract-test. Bestaande `/health`-test en al het andere ongewijzigd.
- Bronnen: [Scalar — ASP.NET Core integration](https://scalar.com/products/api-references/integrations/aspnetcore/integration), [Microsoft Learn — OpenAPI-documenten gebruiken (ASP.NET Core 10)](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/using-openapi-documents?view=aspnetcore-10.0).

## 1. Packages + `Program.cs`

- **`src/Api/Api.csproj`** krijgt exact twee `PackageReference`s: `Microsoft.AspNetCore.OpenApi` en `Scalar.AspNetCore` (exacte versies bij implementatie na verificatie — `dotnet add package` lost latest op .NET 10 op, daarna pinnen, zoals altijd).
- **`src/Api/Program.cs`** wordt (volledig):
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
- Resultaat: OpenAPI-JSON op `/openapi/v1.json`, Scalar-UI op `/scalar` — **alleen** als `ASPNETCORE_ENVIRONMENT=Development`. De productie-container (`ASPNETCORE_ENVIRONMENT` unset → `Production`) serveert geen docs: geen extra oppervlak, geen gedragsverschil voor `/health`.

## 2. OpenAPI-contracttest

Nieuwe test in `tests/Api.Tests/HealthEndpointTests.cs` (zelfde fixture; `WebApplicationFactory` draait standaard in `Development`, dus de dev-gated endpoints zijn in tests bereikbaar zonder extra configuratie):

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

Bestaande `/health`-test blijft ongewijzigd. De test bewijst: document wordt gegenereerd én bevat het endpoint — een kapotte OpenAPI-config (bv. ontbrekende `AddOpenApi`) faalt hier rood. De Scalar-UI zelf (`/scalar` HTML) testen we niet — dat is third-party rendering zonder logica van ons.

## 3. Validatie, foutafhandeling & scope

- **Lokale validatie vóór de PR** (verplicht, op feature-branch): `dotnet restore` → build met `TreatWarningsAsErrors` → `dotnet test` met coverage — verwacht 2/2 groen; daarna app draaien met `ASPNETCORE_ENVIRONMENT=Development` en in de browser `/scalar` + `/openapi/v1.json` controleren, plus één run zónder die variabele waar `/scalar` 404 geeft (dev-gate bewijs).
- **CI-bewijs**: na merge via PR alle checks groen; `Test (.NET)` bevat dan 2 tests. `Docker build` bestaat niet meer — image-bouw loopt via `publish`.
- **Foutafhandeling**: faalt de contract-test (bv. OpenAPI-route weg), dan faalt `test` en wordt `publish` overgeslagen (ongewijzigd mechanisme).
- **Buiten scope**: extra endpoints documenteren (er is alleen `/health`), response-voorbeelden/`Produces`-attributen, meerdere OpenAPI-documenten, Scalar-thema's/opties, SwaggerUI/Redoc, OpenAPI-JSON als build-artefact, Helm/ArgoCD-wijzigingen.

## 4. Doorgroei

Zodra dit staat: `Produces`-metadata en response-voorbeelden bij groeiende API, Scalar-opties (titel/thema) bij behoefte, en OpenAPI-contract als consument voor gegenereerde clients.
