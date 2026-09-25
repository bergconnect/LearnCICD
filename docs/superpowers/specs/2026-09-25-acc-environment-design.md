# Design: acc-omgeving naast dev en prd (alleen via Promote)

Datum: 2026-09-25
Status: goedgekeurd (alle 2 secties)
Aanpak: A — repo-native in één keer (zelfde patroon als prd)

## Doel

Voeg een `acc`-omgeving toe naast `dev` en `prd`. Naar `acc`
promoten kan uitsluitend via de handmatige `Promote`-workflow,
net als naar `prd`. Geen volgorde-regels tussen acc en prd
(vrije doelen).

## Sectie 1: scope en stromen (akkoord)

Centraal (`bergconnect/cicd-workflows`, nieuwe tag `v8`):
allowlist `[dev, prd]` → `[dev, prd, acc]` in `promote-template`
(validatie + copy + bump werken env-agnostisch via de
`values_<env>.yaml`-conventie).

Lokaal (`LearnCICD`):
- `promote.yml`: environment-opties + `acc` (wordt `[dev, prd, acc]`).
- `values_acc.yaml` per chart (`learncicd`, `learncicd-worker`)
  met placeholder-tag `0.0.0-niet-bestaand` (bewust onbestaand:
  kan nooit voor een echte deploy worden aangezien).
- 2 ArgoCD-apps in git (`learncicd-acc`, `learncicd-worker-acc`).
- `new-project.sh` genereert voortaan ook acc-artefacten
  (values-bestand + beide apps; let op de VFILE-les: per iteratie
  opnieuw zetten).

Cluster (eenmalig, harde voorwaarde vóór eerste promote):
namespace `acc` aanmaken + apps toepassen; pull-secret
materialiseert uit de chart-SealedSecret (verifiëren:
type `kubernetes.io/dockerconfigjson`, beide registries,
ownerRef SealedSecret).

GitHub: Environment `acc` als gate, zonder verplichte reviewers
(zelfde bescherming als `prd` nu).

Flow: Promote-dispatch met `environment=acc` → validatie → bump
`values_acc.yaml` → auto-PR → automerge → ArgoCD synct `acc`.

## Sectie 2: starttoestand, fouten, bewijs (akkoord)

- Start: placeholder-tag in `values_acc.yaml`; acc-apps tonen
  ImagePull/OutOfSync tot de eerste echte promote — verwacht en
  acceptabel, geen blokker.
- Validatie hergebruikt v7 ongewijzigd (SemVer + registry-check
  vóór mutatie; onbekende versie → run rood zonder PR).
- Fouten: bootstrap faalt → apps OutOfSync, geen CI-impact;
  promote vóór bootstrap → run groen maar ArgoCD kan niet syncen
  (daarom bootstrap als eerste plan-taak).
- Bewijs: na bootstrap één handmatige promote (huidige dev-tag)
  naar acc + pull-bewijs (pod draait tag, Running).

## Buiten scope

- Verplichte volgorde dev→acc→prd (afgewezen: vrije doelen).
- Environment-reviewers op acc (afgewezen: zelfde niveau als prd).
- SealedSecret dual-ownership-cosmetica (bestaand, los traject).
