# Design: CD-keten dev → acc → prd met goedkeuring per env

Datum: 2026-09-30
Status: goedgekeurd (aanpak A + alle 2 secties)

## Doel

De CD-template deployt na een push naar `main` sequentieel naar
`dev` (automatisch), `acc` (na review-goedkeuring) en `prd` (na
review-goedkeuring). De handmatige Promote-workflow verdwijnt.

## Sectie 1: keten en jobs (akkoord)

Push naar `main` → detect → determine-version (één versie per
project voor de hele run) → publish → update-tag dev (auto,
`environment: dev`, ongewijzigd) → promote-acc (matrix per
project, `environment: acc` → wacht op review; bij approve: copy
+ bump `values_acc.yaml` + auto-PR) → promote-prd (idem met
`environment: prd`, `needs:` acc-job).

- Versie identiek door de keten (zelfde VER-map).
- `cancel-in-progress` blijft: nieuwe push vervangt wachtende
  keten (acceptabel en gewenst).

## Sectie 2: bestanden, reviewers, bewijs (akkoord)

- `cd-dev-template.yml` → `cd-template.yml` (hernoemd; `cd.yml`-ref
  + `projects.json`-tracking mee).
- `promote.yml` + `promote-template.yml` VERWIJDERD (hele
  Promote-ingang weg, incl. dispatch).
- Bump-composite ongewijzigd (auto-merge blijft overal aan).
- Reviewers: `acc`/`prd` Environments krijgen required reviewers
  via API (user-IDs; nu leeg laten, exacte PUT-stap in plan).
  Zonder namen = gate zonder wachters = direct door (expliciet
  als overgangstoestand, geen eindtoestand).
- Bewijs: probe-push → dev auto → acc wacht (approve) → prd
  wacht (approve) → alle pods nieuwe versie.

## Buiten scope

- Aparte keten-workflow via `workflow_run` (aanpak B, afgewezen:
  breekbaar).
- Reviewer-namen invullen (eigenaar doet bij inrichting).
- SealedSecret dual-ownership-cosmetica (bestaand, los traject).
