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
  "version": "0.3",
  "pathFilters": ["."],
  "publicReleaseRefSpec": [
    "^refs/heads/main$"
  ]
}
```

2. Kies een versienummer dat nog geen enkel ander project gebruikt — gelijke nummers delen één height-lijn en versies divergeren dan niet. Het versienummer `0.3` in het voorbeeld hierboven is slechts illustratief — verifieer met onderstaand commando dat jouw nummer nog ongebruikt is. Controleer bestaande nummers met:

```bash
grep -h '"version"' src/*/version.json
```

3. Verifieer dat nbgv het nieuwe bestand resolveert:

```bash
(cd src/<Naam> && dotnet nbgv get-version -v SemVer2)
```

Verwacht: een geldige SemVer2-string.

## 3. CI/CD-koppeling

1. Voeg één entry toe aan `.github/projects.json`:

```json
"<Naam>": {
  "image_name": "<image>",
  "chart": "<chart>"
}
```

Gebruik kleine letters zonder spaties voor `<image>` en `<chart>` (bijvoorbeeld `billing` en `billing`).

2. Verder niets aanpassen onder `.github/`: CI/CD ontdekt projecten automatisch via `ls src` en bouwt, test en publiceert elk geraakt project via de matrix; tag-branches volgen automatisch.

## 4. Chart en ArgoCD-app

1. Kopieer de worker-chart als startpunt:

```bash
cp -r .infra/learncicd-worker .infra/<chart>
```

2. Hernoem in de kopie alle helpers/labels van `learncicd-worker` naar `<chart>` (bestanden: `Chart.yaml`, `templates/_helpers.tpl`, `templates/deployment.yaml`, `templates/service.yaml`), inclusief het veld `name:` in `Chart.yaml`.
3. Vul `.infra/<chart>/values.yaml` in (volledige `repository:`, port, pullPolicy, probes, resources — kopieer van de worker-chart) en `.infra/<chart>/values-devtest.yaml` (alleen `service.port` en `image.tag`).
4. Maak `argocd/applications/<chart>-devtest.yaml` (kopieer `argocd/applications/learncicd-worker-devtest.yaml`) met `path: .infra/<chart>` en beide `valueFiles` naar de nieuwe chart.
5. Valideer de chart:

```bash
helm lint .infra/<chart>
helm template <chart>-devtest .infra/<chart> -f .infra/<chart>/values.yaml -f .infra/<chart>/values-devtest.yaml --namespace devtest | grep "image:"
```

Verwacht: `1 chart(s) linted, 0 failed` en één `image:`-regel met jouw repository en tag.

## 5. Verificatie

1. Lokaal valideren (zelfde als CI):

```bash
dotnet restore
dotnet build -c Release --no-restore /p:TreatWarningsAsErrors=true
dotnet test -c Release --no-build --coverage --coverage-output-format cobertura
```

Bij workflow-wijzigingen: draai `actionlint` en `yamllint` (alleen de 2 bekende warnings zijn oké).

2. Open een PR naar `main` en controleer dat de CI-matrix een leg voor `<Naam>` draait (andere projecten skippen of ontbreken).
3. Na merge: controleer dat de CD-run een image voor `<Naam>` publiceert en dat de ArgoCD-app synct (`kubectl get applications -n argocd`, pods `Running`).

Acceptatie/productie vallen buiten dit stappenplan en volgen de bestaande promote-flow.
