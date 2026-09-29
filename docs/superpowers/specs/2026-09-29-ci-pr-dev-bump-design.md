# Design: PR-code naar dev via values-bump (feature-branch-versie)

Datum: 2026-09-29 (v3; vervangt v2-base-van-main en v1-direct-patch)
Status: goedgekeurd via directie (unieke tag per push, versie van
feature-branch + commit-id)

## Doel

PR-code testen op `dev` vóór merge/review-afronding, zónder merge
naar `main`. Elke push naar een bestaande PR krijgt een unieke tag
en rolt echt uit (geen staleness).

## Stroom en versie

Per PR-push (na groene Verify), per gewijzigd project:

1. Versie = nbgv op de feature-branch zelf
   (`0.2.24-g74fd7bb`, vorm strikt gevalideerd
   `^[0-9]+\.[0-9]+\.[0-9]+-g[0-9a-f]+$`, fail-closed).
   Uniek per push (commit-SHA), Docker-legaal, nooit botsend met
   releases (suffix scheidt).
2. Publiceer image `:TAG` naar dev-registry (zelfde publish-vorm
   als CD).
3. Bump `values_dev.yaml` naar `TAG` via bump-composite (auto-PR +
   automerge, branch `ci/preview-<project>-<TAG>`) → ArgoCD deployt
   PR-code naar dev.
4. Re-pushes: nieuwe SHA → nieuwe tag → echte bump → echte rollout.
5. Meerdere PRs: laatste gemergde bump-PR wint dev (gedeelde ns).

## Plaats, rechten, bewijs

- Eigen `preview`-job in `ci-template.yml` na Verify (blocking);
  hergebruikt `dotnet-setup` + `bump-image-tag` (inputs expliciet:
  `token`/`gpg-key`/`key-id`); job-permissies
  `contents:write` + `pull-requests:write`; `environment: dev`
  (dev-scoped vars); géén `cd-dev-template`-hergebruik (push-vormig).
- `cd.yml` ongewijzigd. Geen cluster-toegang (pure GitOps).
- Fork-PRs zonder secrets falen (geaccepteerd).
- Bewijs: probe-PR met TWEE pushes → twee tags, pod volgt tweede
  (digest-vergelijking) → merge → CD neemt over → revert-PR.

## Buiten scope

- Volgorde-regels dev→acc→prd (vrije doelen).
- Registry-cleanup van PR-tags (handmatig, later).
- Review-verplichting afdwingen (apart).
