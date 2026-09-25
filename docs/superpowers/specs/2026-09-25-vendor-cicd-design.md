# Design: cicd-workflows vendorten naar LearnCICD (harde fork)

Datum: 2026-09-25
Status: goedgekeurd (aanpak A + alle 2 secties)

## Doel

Haal de custom actions en templates uit `bergconnect/cicd-workflows`
naar LearnCICD (harde fork). De centrale repo blijft intact maar
wordt door LearnCICD niet meer gebruikt; CI-, CD- en Promote-callers
wijzen naar lokale kopieën. Reden: volledige lokale controle, geen
floating-tag-tredmolen of cross-repo-breuk meer.

## Sectie 1: bestanden en ref-herschrijving (akkoord)

6 bestanden 1-op-1 naar dezelfde paden lokaal, stand centrale `main`:
- `.github/actions/bump-image-tag/action.yml`
- `.github/actions/detect-changed-projects/action.yml`
- `.github/actions/dotnet-setup/action.yml`
- `.github/workflows/cd-dev-template.yml`
- `.github/workflows/ci-template.yml`
- `.github/workflows/promote-template.yml`

Ref-herschrijving (enige inhoudelijke delta):
- Callers: `bergconnect/cicd-workflows/.github/workflows/<f>@<tag>`
  → `./<f>` (lokaal relatief, geen versie).
- In templates: `bergconnect/cicd-workflows/.github/actions/<a>@<tag>`
  → `../actions/<a>` (whatever de centrale pin is — principe geldt).
- Verder byte-identiek.

`projects.json` caller-tracking controleren op workflow-paden en
bijwerken waar nodig.

## Sectie 2: docs, tags, bewijs (akkoord)

- Docs: vermeldingen van centrale pins/tags (o.a.
  `docs/nieuwe-service.md`) omzetten naar lokaal (geen versies).
- Tags: centrale floating tags blijven staan als bevroren
  geschiedenis; geen nieuwe centrale tags meer voor LearnCICD.
- Centraal: geen commits (intact).
- Bewijs: PR-CI groen (verplichte checks) + daarna één handmatige
  Promote-dispatch (negatief én bestaand) als rookproef dat lokale
  refs resolven.

## Buiten scope

- Opschonen van overgenomen code (dode inputs/comments) — later traject.
- Sync terug naar centraal (harde fork: geen).
- Andere consumer-repos (varen eigen koers op centrale tags).
