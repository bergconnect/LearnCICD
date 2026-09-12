# Design: ArgoCD per omgeving (subproject 2 van 3: multi-stage)

- Datum: 2026-09-12
- Status: goedgekeurd door gebruiker (alle 3 secties akkoord; aanpak A gekozen)
- Scope: drie Application-manifesten (devtest/acceptatie/productie), cluster-brede SealedSecret, oude `learncicd`-Application + `default`-deployment opruimen. Vervolg: subproject 3 (CD-promotieflow met approvals + per-env tags).
- Bovenliggend doel: stages DevTest, Acceptatie en Productie, elk met eigen deployment, namespace en ClusterIP-poort (8080/8081/8082).

## 1. Drie Applications

Nieuwe bestanden `argocd/applications/learncicd-{devtest,acceptatie,productie}.yaml` (mapje `applications/` — de huidige losse `application.yaml` verdwijnt in §2):

- Per app: `name: learncicd-<env>`, `namespace: argocd`, `project: default`, `source.repoURL: https://github.com/bergconnect/LearnCICD.git` + `targetRevision: HEAD` + `path: charts/learncicd`, `destination.server: https://kubernetes.default.svc`, `destination.namespace: <env>`.
- Helm-waarden per app via `source.helm.valueFiles`: `[$values/charts/learncicd/values.yaml, $values/charts/learncicd/values-<env>.yaml]` (ArgoCD-syntax met `$values`-prefix, basis eerst).
- Sync: `automated: {prune: true, selfHeal: true}` (gelijk aan nu) **plus** `syncOptions: [CreateNamespace=true]` (maakt `devtest`/`acceptatie`/`productie` aan bij eerste sync — geen handwerk).
- Release-naam per app wordt automatisch de app-naam (`learncicd-<env>`) → Deployment/Service krijgen env-specifieke namen, geen clash tussen namespaces.

## 2. Cluster-brede SealedSecret + oude app opruimen

- **SealedSecret**: `charts/learncicd/templates/pullsecret.yaml` blijft bestaan maar wordt **cluster-breed**: annotatie `sealedsecrets.bitnami.com/cluster-wide: "true"` erop, versleuteld met de cluster-key zonder namespace-binding. Daardoor mag hetzelfde manifest in `devtest`/`acceptatie`/`productie` landen — ArgoCD deployt het per Application mee (het is chart-content, dus elke sync installeert het in de doel-namespace).
- **Oude situatie opruimen**: `argocd/application.yaml` (oude `learncicd` → `default`) wordt **verwijderd**; de oude `default`-Deployment + Service verdwijnen via ArgoCD-prune bij het verwijderen van de app (eerst app deleten met cascade, daarna bestand weg — volgorde in plan). Het handmatige `gitea-registry`-Secret in `default` mag blijven tot niets er meer naar verwijst, daarna weg.
- **Veiligheid gelijk**: geen plaintext in git (alleen de opaque blob verandert: opnieuw versleuteld zónder namespace-scope); `values.imagePullSecrets: [gitea-registry]` ongewijzigd geldig in alle drie namespaces.

## 3. Validatie, foutafhandeling & scope

- **Lokale validatie vóór de PR** (verplicht, op feature-branch): `helm template` per env met beide values-bestanden (poorten 8080/8081/8082 + release-namen `learncicd-<env>`); `kubectl apply --dry-run=server` van de drie Application-manifesten via SSH (CRD-validatie zonder iets aan te maken); `yamllint` waar zinvol.
- **CI-bewijs**: na merge via PR alle checks groen. Echte deploy-bewijs: na `kubectl apply` van de drie Applications via SSH — alle drie `Synced Healthy`, drie namespaces met elk een `Running`-pod en `/health` OK (port-forward per namespace).
- **Foutafhandeling**: faalt één env-sync (bv. image-pull in nieuwe namespace), dan blijven de andere twee onaangetast doorwerken (geen kruis-`needs` tussen Applications). Oude `default`-deployment pas verwijderen nádat alle drie env-pods `Running` zijn (volgorde-bewaking in plan).
- **Buiten scope**: per-env image-tags + approvals (sub-project 3), oude `learncicd`-Application elders dan beschreven, `values-prod`-achtige splitsingen, SealedSecret-rotatie, monitoring/alerting.

## 4. Volgende subprojecten

- Subproject 3: CD-promotieflow (GitHub Environment-approvals tussen stages + per-env versie/tag-update zodat ArgoCD heruitrolt).
