# Design: Helm-values per omgeving (subproject 1 van 3: multi-stage)

- Datum: 2026-09-12
- Status: goedgekeurd door gebruiker (alle 2 secties akkoord; aanpak A gekozen)
- Scope: drie overlay-values-bestanden (alleen poort per stage). Onderdeel van het multi-stage-traject: subproject 2 (ArgoCD per omgeving) en 3 (CD-promotieflow) volgen apart.
- Bovenliggend doel: stages DevTest, Acceptatie en Productie, elk met eigen deployment op Kubernetes via ArgoCD; ClusterIP-poorten per stage verschillend.

## 1. Overlay-bestanden (alleen poort)

Drie nieuwe bestanden naast `values.yaml` (die ongewijzigd basis blijft):

- `charts/learncicd/values-devtest.yaml`: `service: {port: 8080}`
- `charts/learncicd/values-acceptatie.yaml`: `service: {port: 8081}`
- `charts/learncicd/values-productie.yaml`: `service: {port: 8082}`

Elk bestand bevat alléén wat afwijkt (nu: poort; later komt de per-env `image.tag` erbij via de promotieflow uit subproject 3). Gebruik altijd als overlay: `helm -f values.yaml -f values-<env>.yaml` (of ArgoCD `valueFiles` in die volgorde). Naamgeving `<stage>` in kleine letters, gelijk aan toekomstige namespace-namen zodat alles 1-op-1 mapt.

## 2. Namespaces, validatie & scope

- **Namespaces** (`devtest`, `acceptatie`, `productie`) komen **niet** uit de chart — ArgoCD zet `destination.namespace` per Application (sub-project 2); de chart blijft namespace-agnostisch. Aanmaken van de namespaces gebeurt bij eerste deploy (ArgoCD `CreateNamespace=true`-optie of handmatig — keuze voor sub-project 2, niet hier).
- **Validatie vóór de PR** (verplicht, op feature-branch): `helm lint` schoon; per env renderen (`helm template -f values.yaml -f values-<env>.yaml`) en controleren dat service-poort 8080/8081/8082 uitkomt en selectors kloppen; `yamllint` waar zinvol.
- **Buiten scope**: ArgoCD Applications per env (sub-project 2), tag-beheer per env + approvals (sub-project 3), `imagePullSecrets` per env (zelfde Gitea-secret overal — geen wijziging), aparte `values.yaml`-defaults wijzigen.
- **Doorgroei** (vastgelegd, niet nu): per-env replicas/resources als een omgeving daarom vraagt; dan groeit het overlay-bestand organisch.

## 3. Volgende subprojecten

- Subproject 2: ArgoCD per omgeving (drie Applications of ApplicationSet, namespaces, sync-beleid).
- Subproject 3: CD-promotieflow (GitHub Environment-approvals tussen stages + per-env versie/tag-update zodat ArgoCD heruitrolt).
