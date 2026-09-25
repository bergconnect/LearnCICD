# Design: CI/CD automatisch t/m dev, handmatige promote naar prd

Datum: 2026-09-24
Status: goedgekeurd (alle 3 secties)
Aanpak: A — één workflow, twee ingangen

## Doel

Automatiseer de volledige keten tot en met `dev`; promotie naar `prd`
gebeurt uitsluitend via een bewust handmatig gestarte workflow-run
met expliciete project- en versie-keuze.

## Sectie 1: stromen (akkoord)

Auto-flow (push naar `main`): CI (matrix per project, tests) →
publish (image + tag) → promote `dev` (bump `values_dev.yaml` +
auto-PR + automerge) → ArgoCD synct `dev`. `prd` komt NOOIT meer
in deze keten voor.

Hand-flow (workflow_dispatch op `CD` met `project` + `version`):
valideren → bump `values_prd.yaml` + auto-PR + automerge → ArgoCD
synct `prd`. Zelfde bump-composite en PR-vorm als dev; alleen de
trigger en de doel-env verschillen.

## Sectie 2: componenten en wijzigingen (akkoord)

Centraal (`bergconnect/cicd-workflows`, nieuwe tag `v6`):
- `cd-template.yml` krijgt `auto-environments` (default `[dev]`);
  de prd-promote-job verdwijnt uit de push-keten.
- Dispatch-pad ongewijzigd (`project` + `environment` + `version`
  → valideren → bump → auto-PR); dit pad is in productie bewezen
  (backfills).
- Nieuw: registry-validatiestap in dispatch (faal snel bij
  onbekende versie, vóór elke git-mutatie).

Lokaal (`LearnCICD`):
- Géén workflow-wijziging: `cd.yml` heeft de dispatch-inputs al.
- Alleen `docs/nieuwe-service.md` krijgt een promote-paragraaf
  (hoe starten, welke versie kiezen).
- Versie-pins (`@v5` → `@v6`) gaan in één keer mee; nooit mixen.

## Sectie 3: validatie, fouten, bewijs (akkoord)

- Versie moet SemVer2 zijn én als image-tag in het registry
  bestaan (skopeo/crane-check).
- Downgrade t.o.v. huidige prd-tag mag alleen met expliciete
  confirm-input.
- Validatie faalt → run rood vóór PR-aanmaak, niks gemuteerd.
- ArgoCD OutOfSync na merge → bestaande health-checks, geen
  workflow-retry.
- Bewijsronde na implementatie: probe-PR (auto dev-deploy) +
  handmatige prd-promote van diezelfde versie, afgesloten met
  pull-bewijs in `prd`.

## Beveiliging

Alleen de `prd`-Environment-gate (zonder verplichte reviewers,
zoals nu). Starten = bewuste actie; 4-ogen-principe expliciet
niet vereist.

## Buiten scope

- Aparte `promote.yml` (aanpak B, afgewezen: extra caller-onderhoud).
- Keten-met-approval (aanpak C, afgewezen: geen bewuste start).
- SealedSecret dual-ownership-cosmetica (bestaand, los traject).
