# Design: image-tag in values.yaml automatisch bijwerken via CI-PR

- Datum: 2026-09-11
- Status: goedgekeurd door gebruiker (alle 2 secties akkoord; CI-gedreven variant — géén ArgoCD Image Updater)
- Scope: na elke `publish` maakt CI een branch met de gepushte `semVer` als image-tag in `values.yaml` en opent een PR. Mens mergt; daarna geen nieuwe CI-run (loop-breaker) en deployt ArgoCD de gepinde versie.

## 1. Update-job in CI (branch + tag-bump + PR)

Nieuwe job `update-image-tag` in `ci.yml`, alleen op push naar `main`, met `needs: [publish, version]` (PR pas als de image écht in het registry staat; `version` levert de tag):

1. Checkt `main` uit (de net-gemergde stand).
2. Zet `image.tag` in `charts/learncicd/values.yaml` op de zojuist gepubliceerde `semVer` (zelfde `needs.version.outputs.semVer` als de push-tags — één bron, geen drift).
3. Maakt/bijwerkt branch **`ci/image-tag-update`** (vaste naam — herhaalde runs updaten dezelfde PR i.p.v. nieuwe te spawnen) en opent een PR (`base: main`, titel met de versie, body met commit-sha ter traceerbaarheid).
4. Uitvoering met een standaard bot-action (bv. `peter-evans/create-pull-request`) op `GITHUB_TOKEN` — geen extra credentials, geen cluster-wijzigingen, geen nieuwe infra.

## 2. Loop-breaker, PR-flow, validatie & scope

- **Loop-breaker**: push-trigger krijgt `paths-ignore: ['charts/learncicd/values.yaml']`. Reden: de update-PR mergen verhoogt NB.GV-height (nieuwe versie voor identieke code) — zonder breaker zou elke tag-bump een nieuwe image + nieuwe PR cascaderen. Met de breaker slaat CI merges die alléén `values.yaml` raken over: geen nieuwe versie, geen nieuwe image, keten stabiel. Gemengde pushes (code + values) draaien wél gewoon CI.
- **PR-flow**: de update-PR doorloopt normale protection (3 checks groen — `publish` geskipt op PR, correct); mens mergt; ArgoCD sync de nieuwe tag automatisch (bestaande auto-sync).
- **Validatie**: lokaal `yamllint` + YAML-parse van de job; CI-bewijs in twee stappen — (1) na merge van de implementatie-PR: push-run groen mét een geopende update-PR als bewijs dat de job werkt; (2) na merge van díe update-PR: géén nieuwe CI-run (breaker-bewijs) + ArgoCD draait de gepinde versie (geen `latest` meer in effect).
- **Buiten scope**: ArgoCD Image Updater-configuratie (niet nodig in deze variant), digest-pinning, Renovate/Flux, tag-beleid buiten semVer, omgevings-values.

## 3. Doorgroei

Zodra dit loopt: overwegen de update-PR's automatisch te mergen bij groene checks (auto-merge), en pas bij meerdere omgevingen waarden per omgeving splitsen.
