# Nieuwe service toevoegen

## 1. Scaffold aanmaken met het script

Voer uit (vervang `<Naam>` door de servicenaam, bijvoorbeeld `Billing`):

```bash
scripts/new-project.sh <Naam>
```

Eisen aan `<Naam>`: alfanumeriek en beginnend met een letter. Het script kiest zelf een ongebruikt `0.x`-versienummer en legt alles aan: code (`src/<Naam>`), tests (`tests/<Naam>.Tests`), solution-registratie, `src/<Naam>/version.json`, een entry in `.github/projects.json`, de chart (`.infra/<naam>`) en de twee ArgoCD-apps (dev en prd).

Controleer de output van het script en draai daarna de verificatie hieronder (§5).

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

Handmatig promoten: CD-`workflow_dispatch` (project + omgeving + versie)
met dezelfde approval-gates als de push-flow.
