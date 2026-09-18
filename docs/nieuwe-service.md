# Nieuwe service toevoegen

Dit stappenplan neemt een nieuwe minimal-API-service mee van lege map tot werkende devtest-deploy. Vervang overal `<Naam>` door de servicenaam (bijvoorbeeld `Billing`).

## 1. Code

1. Maak `src/<Naam>/<Naam>.csproj` (kopieer `src/Worker/Worker.csproj` als startpunt: `net10.0`, `Nullable`, `ImplicitUsings` en `TreatWarningsAsErrors` aan).
2. Voeg de code toe (minimaal een `Program.cs` met een `/health`-endpoint).
3. Maak `tests/<Naam>.Tests/<Naam>.Tests.csproj` (kopieer `tests/Worker.Tests/Worker.Tests.csproj` als startpunt) met een `ProjectReference` naar `..\..\src\<Naam>\<Naam>.csproj` en minimaal één test op `/health`.
4. Registreer beide projecten in de solution:

```bash
dotnet sln LearnCICD.sln add src/<Naam>/<Naam>.csproj tests/<Naam>.Tests/<Naam>.Tests.csproj
dotnet sln LearnCICD.sln list
```

Verwacht: beide nieuwe paden staan in de lijst.

## 2. Versiebestand

1. Maak `src/<Naam>/version.json` (kopieer `src/Worker/version.json`):

```json
{
  "version": "0.2",
  "pathFilters": ["."],
  "publicReleaseRefSpec": [
    "^refs/heads/main$"
  ]
}
```

2. Kies een versienummer dat nog geen enkel ander project gebruikt — gelijke nummers delen één height-lijn en versies divergeren dan niet. Controleer bestaande nummers met:

```bash
grep -h '"version"' src/*/version.json
```

3. Verifieer dat nbgv het nieuwe bestand resolveert:

```bash
(cd src/<Naam> && dotnet nbgv get-version -v SemVer2)
```

Verwacht: een geldige SemVer2-string.
