# Design: PR-preview deploy naar dev vanuit CI

Datum: 2026-09-25
Status: goedgekeurd (aanpak A + alle 2 secties)

## Doel

Elke CI-run (PR) deployt bij groene checks zijn eigen code naar de
gedeelde `dev`-namespace, zodat PR-code vóór merge getest kan worden.
Geen git-mutatie, geen values-bump, geen auto-PR vanuit preview.

## Sectie 1: stroom en images (akkoord)

CI-run (PR): Verify groen → per gewijzigd project PR-image
publiceren met nbgv-prerelease-tag (bv. `0.2.21-pr.248.3`, uniek
per PR+run) naar het dev-registry → `kubectl set image` op het
dev-Deployment (directe patch).

- Géén git-mutatie, géén values-bump, géén auto-PR vanuit preview.
- Post-merge CD overschrijft dev vanzelf met de echte versie
  (self-healing).
- Registry-spam (PR-tags blijven staan) geaccepteerd; periodieke
  cleanup handmatig.

## Sectie 2: toegang, contention, bewijs (akkoord)

- Cluster-toegang: runner is géén clusternode → nieuw repo-secret
  `KUBECONFIG` (of ssh-key naar `.46`; keuze bij implementatie,
  kubeconfig aanbevolen) + kubectl-setup-step in de preview-job.
- Contention: gedeelde dev-ns, last-write-wins; parallelle PRs
  overschrijven elkaar (geaccepteerd).
- Fouten: preview faalt → CI-run rood (blocking). Kapotte preview
  = kapotte deploy; Verify-uitslag alleen is niet genoeg voor merge.
- Bewijs: probe-PR → pod draait PR-tag in dev → merge → CD zet
  echte versie terug.

## Buiten scope

- Aparte `preview.yml` (aanpak B, afgewezen: dubbele cyclus).
- Namespace per PR (aanpak C, afgewezen: sprawl/cleanup).
- Registry-cleanup-automatisering (handmatig, later).
- Ssh-alternatief uitwerken (alleen als kubeconfig afvalt).
