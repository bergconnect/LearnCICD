# Design: dotnet publish container publishing i.p.v. Dockerfile

- Datum: 2026-09-15
- Status: goedgekeurd door gebruiker
- Scope: `.github/workflows/cd.yml` (`publish`-job); `Dockerfile` en `.dockerignore` worden verwijderd.

## 1. Architectuur

Vervang de `docker/build-push-action`-stap (incl. Docker Buildx setup) door `dotnet publish` met de ingebouwde container-publishing-target (`/t:PublishContainer`). De Skopeo-push-stappen blijven, maar gebruiken de `docker-archive:`-transport i.p.v. `oci-archive:` (zie § 2, gevonden tijdens validatie).

## 2. Wijzigingen

### cd.yml `publish`-job

Verwijder:
- Stap `Set up Docker Buildx` (`docker/setup-buildx-action@v3`)
- Stap `Build image to OCI layout` (`docker/build-push-action@v6`)

Vervang door:
```yaml
- name: Build image archive with dotnet publish
  run: >
    dotnet publish src/Api/Api.csproj
    --os linux --arch x64
    -c Release
    -p:ContainerBaseImage=mcr.microsoft.com/dotnet/aspnet:10.0
    -p:ContainerRepository=${{ env.IMAGE }}
    -p:ContainerImageTag=$VER
    /t:PublishContainer
    -p:ContainerArchiveOutputPath=/tmp/image.tar
```

Belangrijk verschil met de oude Docker-build (tijdens validatie ontdekt):

- `dotnet publish` produceert een **docker-archive**-tar (`manifest.json` en `RepoTags`), géén OCI-layout (`index.json`). Daarom gebruiken de Skopeo-stappen `docker-archive:` als bron-transport.
- De tar bevat alleen het versie-tag (`ContainerImageTag`), géén `latest`. De `latest`-push verwijst daarom naar hetzelfde `docker-archive:`-bron-tag maar met een ander *destinatie*-tag.
- Job-level env-variabele `VER: ${{ needs.version.outputs.semVer }}` houdt de regels binnen de 80-char yamllint-limiet:

```yaml
- name: Log in to Gitea registry
  env:
    XDG_RUNTIME_DIR: ${{ runner.temp }}/runtime
  run: >
    mkdir -p "$XDG_RUNTIME_DIR";
    skopeo login
    --username ${{ vars.GITEA_USER }}
    --password ${{ secrets.GITEA_TOKEN }}
    ${{ vars.GITEA_HOST }}

- name: Push version tag with Skopeo
  run: >
    skopeo copy
    docker-archive:/tmp/image.tar:$IMAGE:$VER
    docker://$IMAGE:$VER

- name: Push latest tag with Skopeo
  run: >
    skopeo copy
    docker-archive:/tmp/image.tar:$IMAGE:$VER
    docker://$IMAGE:latest
```

De `skopeo login`-stap (bewuste toevoeging na brainstormreview) schrijft de credentials naar `$XDG_RUNTIME_DIR/containers/auth.json`; de push-stappen gebruiken daarna geen `--dest-username`/`--dest-password`-flags meer (die loggen het token in de run-log, login niet). `XDG_RUNTIME_DIR` staat per stap (`runner`-context mag niet op job-level) en de login-stap maakt de map eerst met `mkdir -p` omdat skopeo hem niet zelf aanmaakt.

`ContainerRepository` is expliciet gezet zodat de `RepoTags` in de tar exact overeenkomen met `${{ env.IMAGE }}` (volledig pad incl. Gitea-host).

### Dockerfile en .dockerignore

Beide worden verwijderd:
- `Dockerfile` wordt niet meer gebruikt door CD (dotnet publish bouwt het image direct).
- `.dockerignore` is niet langer nodig.
- `Dockerfile` in `ci.yml` classificatie blijft staan als code-trigger (fail-safe voor toekomstige wijzigingen).

## 3. Reden

- `dotnet publish /t:PublishContainer` is de aanbevolen manier om containerimages te bouwen vanuit .NET 10.
- Geen Docker daemon of Buildx nodig op de runner.
- Eén stap i.p.v. twee (Buildx-setup + build-push-action).
- Dezelfde output als voorheen, maar als docker-archive-tar (93 MB lokaal geverifieerd).

## 4. Buiten scope

- ArgoCD, Helm, promote.yml, CI-workflow, secrets, runners.
- `Dockerfile` in `ci.yml` classificatie (blijft als code-trigger).
