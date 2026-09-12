# CD-promotie met approvals (devtest → acceptatie → productie) — design

Datum: 2026-09-12. Scope: subproject 3 van de multi-stage-uitrol (na Helm per env en ArgoCD per env).
Besloten met gebruiker: gates op acceptatie + productie, DevTest automatisch, harde gate via
GitHub Environments, promotie sequentieel afgedwongen. Aanpak A (dispatch → approve → promotie-PR).

## 1. Architectuur & dataflow

Elke omgeving krijgt zijn eigen `image.tag`: de tag verdwijnt uit `values.yaml` (base) en leeft
voort in `values-devtest.yaml`, `values-acceptatie.yaml` en `values-productie.yaml`. Een omgeving
is daarmee letterlijk één regel in één bestand; promotie = die regel bijwerken via git.

Flow: push naar `main` → bestaande CD bouwt en publiceert de image → `update-image-tag` schrijft
de nieuwe tag voortaan naar `values-devtest.yaml` (via de bestaande auto-PR) → DevTest rolt
automatisch uit via ArgoCD. Voor acceptatie/productie start de gebruiker `promote.yml`
(`workflow_dispatch` met `environment` + `version`). De promotie-job draait onder het GitHub
Environment `acceptatie` resp. `productie` met required reviewers — GitHub pauzeert de run tot de
reviewer in de UI approvet of reject. Na approval: sequentie-check (voor productie moet de
gevraagde versie in `values-acceptatie.yaml` staan), bump van `image.tag` in `values-<env>.yaml`
op branch `ci/promote-<env>-<versie>`, auto-PR openen. Merge → ArgoCD automated sync deployt.
ArgoCD-zijde verandert niets; de gate zit volledig vóór de merge.

## 2. Componenten

1. **GitHub Environments `acceptatie` en `productie`** (repo-instelling, eenmalig): elk met
   required reviewers (de eigenaar) en optioneel een wachttijd. Geen secrets nodig.
2. **`.github/workflows/promote.yml` (nieuw)** met drie jobs: `validate` (inputs controleren:
   versie bestaat als image-tag in het Gitea-registry via `skopeo inspect`; omgeving geldig),
   `promote` (draait onder `environment: <env>` — hier pauzeert GitHub voor approval; daarna
   sequentie-check, tag-bump, branch en auto-PR volgens het `update-image-tag`-patroon) en een
   samenvattende laatste stap.
3. **CD-wijziging (bestaand)**: `update-image-tag` schrijft naar
   `charts/learncicd/values-devtest.yaml` i.p.v. `values.yaml`; base-`values.yaml` verliest
   `image.tag` (alleen repository en pullPolicy blijven als defaults).
4. **Values-bestanden**: elk `values-<env>.yaml` krijgt expliciet `image.tag`. DevTest start op de
   huidige versie; acceptatie/productie op de versie die nu live staat, zodat de eerste promotie
   een echte bump is.

## 3. Foutafhandeling & verificatie

Onbekende of lege `version`, of een image-tag die niet in het registry bestaat → `validate` faalt
vóór de gate (geen approval gevraagd voor onzin). Sequentie-schending (prod-versie staat niet op
acceptatie) → `promote` faalt ná approval met expliciete melding; opnieuw dispatchen met de
juiste versie. Bestaande promotie-branch of -PR voor dezelfde env en versie → hergebruiken in
plaats van dubbel openen (zelfde `already exists`-tolerantie als `update-image-tag`). Rejected
approval → run eindigt zonder enige bestandswijziging. Concurrency: één promotie per omgeving
tegelijk (`group: promote-<env>`, geen cancel — een lopende promotie wordt nooit halverwege
afgebroken).

Verificatie: `yamllint`, `helm lint` en `helm template` per omgeving in CI (bestaat al via
path-gates); end-to-end bewijs op de cluster na merge van een promotie-PR: app Synced en Healthy,
pod-image is de gepromote tag, `/health` geeft 200. Negatief bewijs: een productie-dispatch van
een versie die niet op acceptatie staat, moet falen zonder dat er een PR ontstaat.

## Buiten scope

ArgoCD-wijzigingen (automated sync blijft aan), Image Updater, automatische acceptatie-tests als
promotievoorwaarde, rollback-automatisering (rollback = promotie van een oudere versie die wel aan
de sequentie-regel voldoet).
