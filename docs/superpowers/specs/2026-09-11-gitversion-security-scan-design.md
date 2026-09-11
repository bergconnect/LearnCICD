# Design: GitVersion-versiebepaling + NuGet security-scan in CI

- Datum: 2026-09-11
- Status: goedgekeurd door gebruiker (alle 3 secties akkoord; aanpak A gekozen)
- Scope: twee nieuwe PR-checks (`version`, `security`) naast `test`/`docker`. Versie wordt alleen berekend en getoond; vulnerabilities blokkeren de PR; deprecated wordt alleen gerapporteerd.

## 1. `version`-job (GitVersion, Mainline, alleen berekenen + tonen)

Nieuwe job `version` (`name: Version`, `runs-on: ubuntu-latest`), zonder `needs` op andere jobs — versie-informatie mag nooit door een falende test geblokkeerd worden:

1. `actions/checkout@v4` met **`fetch-depth: 0`** — GitVersion heeft de volledige historie nodig (aantal commits sinds basis, branch-structuur); met de standaard shallow checkout berekent hij een verkeerde versie. Dit is het kritieke configuratiepunt.
2. GitVersion uitvoeren via een `GitVersion.yml` in de repo-root met inhoud `workflow: GitHubFlow/v1` (expliciet, versiebeheerd — geen impliciete defaults). GitVersion 6.x kent geen `mode: Mainline` meer (lokaal bewezen: configuratiefout); `GitHubFlow/v1` is het stabiele equivalent voor single-`main` + feature-branches + PRs (de v6-`TrunkBased`-workflow is nog experimenteel). Elke merge verhoogt. Lokaal bewezen op deze repo zonder tags: `0.0.1-21`, exit 0. Uitvoering via `gittools/actions` (`setup` + `execute`, major-pin `@v4`, tool-lijn `6.x`; tool 6.8.2 lokaal geverifieerd).
3. De berekende versie **alleen tonen** (log-output als PR-check-output), nergens in vastleggen: geen assembly-stamping, geen tags, geen image-labels. Op PR-builds levert dit een pre-release-vorm op (bv. `0.1.0-pullrequest.N+...`) — dat is verwacht gedrag, geen fout.
4. Geen secrets nodig; de job faalt alleen bij een kapotte GitVersion-configuratie zelf.

## 2. `security`-job (vulnerabilities rood, deprecated rapport)

Nieuwe job `security` (`name: Security scan`, `runs-on: ubuntu-latest`), eveneens zonder `needs` (eigen signaal, eigen check op de PR):

1. `actions/checkout@v4` (standaard shallow is hier prima — geen historie nodig) + `actions/setup-dotnet@v4` (SDK via `global.json`, zoals de `test`-job).
2. `dotnet restore` als basis voor de scan.
3. **Vulnerabilities → rood**: `dotnet list package --vulnerable --include-transitive` (directe én transitieve packages) met afdwinging: de stap faalt bij gevonden kwetsbaarheden. De exacte afdwingingsvorm (exit-code versus output-parsen) wordt bij implementatie lokaal bewezen — `dotnet list` gedraagt zich hier niet overal gelijk — en dan vastgelegd. Inclusief transitief, want kwetsbaarheden schuilen meestal dieper in de boom.
4. **Deprecated → alleen rapporteren**: `dotnet list package --deprecated` in een aparte stap die altijd slaagt; output zichtbaar in de check-log. Groen, maar zichtbaar.
5. Beide stappen draaien op solution-niveau (zelfde argumentloze `dotnet restore` als de `test`-job), zodat nieuwe projecten automatisch meedoen.

## 3. Validatie, branch protection & scope

- **Lokale validatie vóór de PR** (verplicht, op feature-branch): `GitVersion`-config droog testen waar mogelijk; `dotnet list package --vulnerable --include-transitive` en `--deprecated` lokaal draaien en het afdwingingsgedrag bewijzen (exit-code of parse — vastleggen zodra bewezen); `yamllint` op de workflow (exit 0, alleen de 2 bekende warnings).
- **CI-bewijs**: na merge via PR moeten alle vier checks groen zijn (bij een schone boom) — te controleren via de GitHub API, zoals bij PR #1/#6 gedaan.
- **Branch protection bijwerken**: de twee nieuwe checks (`Version`, `Security scan`) worden óók verplicht (naast `Test (.NET)` en `Docker build`) — anders blokkeert een rode security-check de merge niet en is het signaal tandeloos. `strict` en overige regels blijven staan.
- **Foutafhandeling**: jobs zijn onderling onafhankelijk (geen `needs` tussen `version`/`security`/`test`); alleen `docker` blijft achter `test` hangen. Fail-fast overal, geen `continue-on-error`.
- **Buiten scope**: assembly-stamping, git-tags aanmaken, image-labels met versie, Dependabot, NuGetAudit-MSBuild-modus, severity-drempels (alles telt even zwaar), SARIF-uploads, `dotnet format`.

## 4. Doorgroei

Zodra dit staat: versie wél gaan gebruiken (assembly-stamping, image-tags, GitHub Releases bij tags op `main`), severity-drempels of `NuGetAudit`-modus als de `dotnet list`-aanpak tekortschiet, en Dependabot als aanvullend (niet vervangend) signaal.
