# Design: Docker-image publiceren naar Gitea-registry (go.berg-connect.nl)

- Datum: 2026-09-11
- Status: goedgekeurd door gebruiker (alle 4 secties akkoord; aanpak A gekozen; image-naam gecorrigeerd naar `beheerder/learncicd`)
- Scope: na elke merge naar `main` de image bouwen en pushen naar `go.berg-connect.nl/beheerder/learncicd` met `semVer`- en `latest`-tags. Credentials uitsluitend via GitHub Secrets.
- Bron: [Gitea-docs — Container Registry](https://docs.gitea.com/usage/packages/container) (`{registry}/{owner}/{image}:{tag}`, `docker login <registry>` met user + token).

## 1. Triggers & jobgating

Triggerblok wordt:

```yaml
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
```

- Alle bestaande jobs (`test`, `version`, `security`) draaien ongewijzigd mee op beide events — na een merge volgt gratis een tweede validatie op `main` zelf.
- **`docker`-job wordt PR-only**: `if: github.event_name == 'pull_request'`. Nodig, want zijn tag `app:pr-${{ github.event.number }}` bestaat niet op push-events (geen PR-nummer → kapotte tag).
- **Nieuwe `publish`-job wordt push-only**: `if: github.event_name == 'push'`, met `needs: [test, version]` — publiceren alleen bij groene tests én met een berekende versie. `security` bewust níét in `needs` (scan-informatie, geen publicatie-blokkade).
- Direct pushen naar `main` blijft geblokkeerd door branch protection; de push-trigger vuurt in de praktijk alleen op gemergde PRs.

## 2. `publish`-job & image-naam

Nieuwe job `publish` (`name: Publish image`, `runs-on: ubuntu-latest`):

1. `actions/checkout@v4` (standaard shallow — geen historie nodig; versie komt via `needs.version`-outputs).
2. `docker/setup-buildx-action@v3` (zelfde als `docker`-job).
3. Build naar OCI-layout via `docker/build-push-action@v6` met `push: false` en `outputs: type=oci,dest=/tmp/image.tar` (zelfde `context: .`, `Dockerfile` en tags als de login-variant; de tarball leeft alleen in de vluchtige runner-workspace, geen daemon nodig).
4. Twee `skopeo copy`-stappen (Skopeo 1.13.3 staat voorgeïnstalleerd op de runners) — één per tag (`semVer`, `latest`):
   `skopeo copy --dest-username ${{ secrets.GITEA_USER }} --dest-password ${{ secrets.GITEA_TOKEN }} oci-archive:/tmp/image.tar:<tag> docker://${{ env.IMAGE }}:<tag>`
   met de job-`env.IMAGE` (houdt alle regels onder 80 tekens). Bron-transport is `oci-archive:` (tarball-bestand, mét kale tag — kaal `oci:` verwacht een directory en faalt; lokaal bewezen). Geen `docker/login-action`: Skopeo authenticeert per copy direct met Basic-auth, zonder apart login-handshake.
   - `${{ secrets.GITEA_HOST }}/beheerder/learncicd:${{ needs.version.outputs.semVer }}`
   - `${{ secrets.GITEA_HOST }}/beheerder/learncicd:latest`

   (`semVer` komt uit de `version`-job; op `main` is dat een schone versie zoals `0.1.0` — geen pre-release-label, omdat de push-event op `main` zelf draait.)

Image-naam `beheerder/learncicd` in kleine letters conform Docker-eis. Gitea maakt het package bij de eerste push automatisch aan onder de token-eigenaar — geen vooraf aanmaken nodig (aanname, te bewijzen door de eerste echte push).

## 3. Credentials (alles via GitHub Secrets)

Drie repo-secrets op `github.com/bergconnect/LearnCICD` (Settings → Secrets and variables → Actions), door de eigenaar vooraf aan te maken — vóór de implementatie-PR gemergd wordt, anders faalt `publish` op login:

- **`GITEA_HOST`** — `go.berg-connect.nl` (zonder `https://`-prefix; Skopeo bouwt er `docker://<host>/...` van).
- **`GITEA_USER`** — `beheerder` (de Gitea-gebruiker waaraan de token hangt).
- **`GITEA_TOKEN`** — Gitea personal access token met **package-schrijfrechten** (`write:package`). Bij 2FA op het account is een token verplicht (wachtwoord werkt dan niet).

Regels: nergens in de repo (geen hardcoded host/user/token in `ci.yml` — alles via `${{ secrets.* }}`), nooit in logs (GitHub maskeert secrets automatisch in output), nooit in chat buiten eenmalige overdracht. De workflow valideert niets aan de secrets vooraf — een verkeerde token uit zich als rode `publish`-check met login-fout, wat precies het bewijs is dat iets misstaat.

## 4. Validatie, branch protection & scope

- **Lokale validatie vóór de PR** (verplicht, op feature-branch): `yamllint` op de workflow (exit 0, alleen de 2 bekende warnings); `docker build` met de Gitea-naam lokaal (`beheerder/learncicd:local`) als equivalentiebewijs — **niet pushen** vanaf lokaal. Registry-login en echte push zijn niet lokaal te bewijzen zonder secrets op schijf achter te laten; de eerste echte push gebeurt in CI.
- **CI-bewijs**: na merge van de implementatie-PR naar `main` vuurt de push-trigger; verwacht: alle bestaande checks groen op `main` plus een groene `Publish image`-job, en daarna image `beheerder/learncicd` met de `semVer`- en `latest`-tags zichtbaar in het Gitea-registry — te controleren via de Gitea-packages-UI/API.
- **Branch protection**: ongewijzigd (vier verplichte PR-checks, strict, enforce-admins). Push-events omzeilen geen enkele regel: direct pushen naar `main` blijft geblokkeerd, de trigger vuurt alleen op gemergde PRs. De `publish`-job zelf hoeft niet als verplichte check — hij draait immers pas ná de merge.
- **Buiten scope**: multi-arch images, image-scanning (Trivy), signing (cosign), `latest`-tag vermijden, Gitea NuGet-registry, automatische secret-rotatie, deploy naar een omgeving.

## 5. Doorgroei

Zodra publiceren loopt: image-scans en signing toevoegen, overwegen de `docker`- en `publish`-jobs samen te voegen met event-conditionals als de duplicatie gaat wringen, en secret-rotatie-procedure vastleggen.
