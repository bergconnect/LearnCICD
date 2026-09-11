# Design: Helm-chart + ArgoCD Application voor LearnCICD

- Datum: 2026-09-11
- Status: goedgekeurd door gebruiker (alle 3 secties akkoord; aanpak A gekozen)
- Scope: `charts/learncicd/` (Deployment + ClusterIP-Service, image uit Gitea-registry, tag `latest`) plus `argocd/application.yaml` (auto-sync naar namespace `default`). Geen ingress, geen omgevings-splitsing, geen CI-wijziging.

## 1. Chart-structuur (`charts/learncicd/`)

Standaard Helm-layout, geen subcharts:

- `Chart.yaml` — `name: learncicd`, semver chart-`version` (start `0.1.0`, handmatig te bumpen bij chart-wijzigingen), `appVersion` volgt de app niet (image-tag staat in values).
- `values.yaml` — image (`repository: go.berg-connect.nl/beheerder/learncicd`, `tag: latest`, `pullPolicy: IfNotPresent`), `replicaCount: 1`, service (`type: ClusterIP`, `port: 8080`), resources met bescheiden defaults, probes aan/uit + paden.
- `templates/deployment.yaml` + `templates/service.yaml` (+ `templates/_helpers.tpl` voor labels/namen). Geen ingress, geen HPA, geen configmaps/secrets — YAGNI bij deze API (geen env-config nodig).
- Private registry-toegang: de Gitea-registry vereist pull-authenticatie → chart bevat `templates/pullsecret.yaml` (SealedSecret `gitea-registry`, namespace-scoped `default`, versleuteld met de cluster-key; geen plaintext in git) waar `values.imagePullSecrets` naar verwijst. Migratie-notitie: de controller adopteert een bestaand handmatig Secret níét (`already exists and is not managed`) — verwijder het handmatige Secret eerst, daarna maakt de controller het opnieuw aan en ontsleutelt (lokaal bewezen).

## 2. Deployment-details (probes, resources, security)

Afstemming op de bestaande container (`USER app`, poort 8080, `GET /health`):

- **Probes**: liveness + readiness als HTTP-GET op `/health`, poort 8080 (zelfde endpoint als de tests valideren). Conservatieve timings, exact in values, beide aan/uit schakelbaar.
- **Resources**: bescheiden defaults (`requests` klein, `limits` ruimhartig) volledig overrulbaar via values — voorkomt OOMKills zonder te knijpen bij een leer-API.
- **Security**: `securityContext.runAsNonRoot: true` plus `runAsUser: 1654` (sluit aan op `USER app` in de image). Alleen `runAsNonRoot` is onvoldoende: kubelet kan een benoemde image-user niet verifiëren (`CreateContainerConfigError`) — vandaar de numerieke UID (1654 = `app` in `mcr.microsoft.com/dotnet/aspnet`-images, lokaal bewezen). Geen privileged flags, geen host-volumes. ImagePullPolicy default `IfNotPresent` met values-comment dat `Always` hoort bij strict `latest`-volgen (kubelet haalt met `IfNotPresent` eenzelfde tag niet opnieuw op bij digest-wissel).
- **Service**: ClusterIP op poort 8080 (targetPort 8080), selectors via helpers.

## 3. ArgoCD Application, validatie & scope

- **`argocd/application.yaml`** (in deze repo): `Application` met naam `learncicd`, `source.repoURL: https://github.com/bergconnect/LearnCICD.git`, `targetRevision: HEAD`, `path: charts/learncicd`; `destination.server: https://kubernetes.default.svc` (in-cluster ArgoCD) en `namespace: default`. Sync-policy: `automated: {prune: true, selfHeal: true}`. Toepassen met `kubectl apply -f argocd/application.yaml` (mensenwerk, één keer).
- **Validatie vóór de PR** (verplicht, op feature-branch): `helm lint charts/learncicd` schoon, `helm template charts/learncicd` renderen en `kubectl apply --dry-run=client` waar mogelijk; `yamllint` waar zinvol. Echte deploy-bewijs: na merge Application syncen in ArgoCD-UI en pod `Running` + `/health` OK controleren (port-forward of logs).
- **CI**: geen workflow-wijziging in v1 — chart-validatie (`helm lint`/`template`) als CI-job is doorgroei, geen onderdeel van dit ontwerp.
- **Buiten scope**: ingress/TLS, HPA, aparte values per omgeving (`values-prod.yaml`), image-tag-automatisering (ArgoCD Image Updater), overige secrets-management (Vault), OCI-push van de chart, resource-finetuning op basis van metingen.

## 4. Doorgroei

Zodra dit draait: `helm lint`/`template` als CI-check, omgevings-values, Image Updater of digest-pinning voor deterministische deploys, en pas bij echte nood ingress/TLS en autoscaling.
