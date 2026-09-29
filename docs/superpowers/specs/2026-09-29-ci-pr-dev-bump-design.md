# Design: PR-code naar dev via values-bump (zelfde versie als acc/prd)

Datum: 2026-09-29
Status: goedgekeurd (alle 2 secties v2)
Voorganger: `2026-09-25-ci-preview-dev-design.md` (direct-patch +
PR-suffix-versie) is VERvallen — tegengesproken door
eigenaar-eisen (zelfde versie, values_dev-bump, geen ssh).

## Doel

PR-code testen op `dev` vóór merge/review-afronding, zónder merge
naar `main`. Versie identiek aan wat acc/prd later krijgen
(`0.2.21`, zonder extra's). Latere pushes op dezelfde PR deployen
niet automatisch opnieuw (geaccepteerd: alleen eerste push telt).

## Sectie 1: stroom en versie (akkoord)

Per PR-push (na groene Verify), per gewijzigd project:

1. Versie = nbgv-base VAN `origin/main` (fetch eerst):
   `dotnet nbgv get-version` op main-stand, suffixloos
   (`0.2.21`). Deterministisch, gelijk aan wat acc/prd vandaag
   zouden krijgen. NOOIT PR-branch-height of `-gSHA`/`-pr`-suffix.
2. Publiceer image `:VER` naar dev-registry (overwrite van
   dezelfde tag geaccepteerd).
3. Bump `values_dev.yaml` naar `VER` via dezelfde bump-composite
   als CD (auto-PR + automerge) → ArgoCD deployt PR-code naar dev.
4. Re-pushes (zelfde `VER`): bump no-op (geen PR) → géén herdeploy.
5. Meerdere PRs: laatste gemergde bump-PR wint dev (gedeelde ns,
   geaccepteerd).

## Sectie 2: plaats, rechten, bewijs (akkoord)

- Géén `cd-dev-template`-hergebruik: zijn determine (`nbgv` op
  PR-branch → height-versies) en update-tag (zonder event-guard →
  auto-PRs met verkeerde versies) zijn push-vormig.
- Eigen `preview`-job in `ci-template.yml` na Verify (blocking bij
  falen): hergebruikt `dotnet-setup` + `bump-image-tag` composites
  + eigen versie/publish-steps. Job-permissies
  `contents:write` + `pull-requests:write` (caller nu read-only).
- `cd.yml` ongewijzigd (post-merge volledige keten; geen dubbele
  deploys door disjuncte triggers).
- Geen cluster-toegang nodig (geen ssh, geen KUBECONFIG — pure
  GitOps). Eerdere SA/KUBECONFIG-terugdraai blijft staan.
- Limitatie: fork-PRs zonder secrets falen op publish (geen forks
  in praktijk — geaccepteerd).
- Bewijs: probe-PR (Worker-wijziging) → `values_dev` op
  basis-versie → pod draait PR-code → merge → CD neemt over met
  echte versie → revert-PR voor schone main.

## Buiten scope

- Herdeploy bij re-push (bewust uitgesloten door eigenaar).
- Volgorde-regels dev→acc→prd (vrije doelen, ongewijzigd).
- Registry-cleanup van overschreven tags (handmatig, later).
- Review-verplichting afdwingen (aparte discussie; nu 0 approvals).
