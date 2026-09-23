# GPG-sleutels: overzicht en beheer

Dit document is de enige waarheid over GPG-signing in dit project. Het
vervangt `docs/signed-commits.md` (achterhaald: bevat nog het `.gitea`-
adres en de ed25519-poging).

Stand per heden (september 2026):

| Sleutel | Key-ID | Doel | Passphrase | Verloopt | Publiek op |
|---|---|---|---|---|---|
| Bot (CI) | `114527D8362078FE` (ed25519) | automatische PR-commits | geen | nooit | `bergconnect`-account |
| Persoonlijk (laptop) | `FA4E2474C26905D8` (RSA-4096) | eigen commits | ja | ~aug 2028 | `bergconnect`-account |

Bijbehorende email-adressen (`128380454+bergconnect@users.noreply.github.com`
resp. `info@berg-connect.nl`) staan beide als verified op het account —
zonder dat telt een cryptografisch geldige handtekening alsnog als
Unverified (`no_user`).

## Bot-sleutel (CI)

Aangemaakt met (UID-email MOET het GitHub-noreply-formaat
`ID+user@users.noreply.github.com` hebben — numerieke ID via
`https://api.github.com/users/bergconnect`):

```bash
gpg --batch --passphrase '' --quick-generate-key "gitea-actions[bot] <128380454+bergconnect@users.noreply.github.com>" ed25519 sign never
```

Daarna: public key op het account, private key als secret
`BOT_GPG_PRIVATE_KEY`, fingerprint als var `BOT_GPG_KEYID`. De pipeline
(`bump-image-tag`) importeert per run en signeert via git-config; details
in de spec.

## Persoonlijke sleutel (deze laptop)

```bash
gpg --quick-generate-key "beheerder <info@berg-connect.nl>" rsa4096 sign 2y
git config --global user.signingkey <FINGERPRINT>
git config --global commit.gpgsign true
```

(RSA-4096 bewust: een ed25519-key werd door GitHub geweigerd bij het
toevoegen.) Passphrase instellen bij generatie; de agent onthoudt hem per
sessie (zie cache-instellingen hieronder). Publieke key als tweede key op
het account zetten.

Huidige machine-stand (`~/.gitconfig`): identity
`beheerder <info@berg-connect.nl>`, `commit.gpgsign true`, signingkey
`D79C530E…`. Sleutelbos (`~/.gnupg`): alleen bot + persoonlijk.

## Wachtwoord-prompt (gpg-agent cache)

Elke commit ontgrendelt de sleutel; de agent onthoudt de passphrase
tijdelijk (standaard ~2 uur). Langer cachen via
`~/.gnupg/gpg-agent.conf`:

```
default-cache-ttl 86400
max-cache-ttl 86400
```

daarna `gpg-connect-agent reloadagent /bye`. Afweging: zolang de cache
leeft kan iedereen achter een ontgrendelde laptop signeren — combineer met
schermvergrendeling. Passphrase vergeten = niet te herstellen: nieuwe key,
oude vervangen (zie roulatie).

## Verifiëren

```bash
git log --show-signature -1  # verwacht: Good signature
```

of via API op een commit: `verified: True, reason: valid`.

## Roulatie en opruimen

- Nieuw paar genereren (zie boven), secrets/vars/account bijwerken, oude
  key intrekken: lokaal `gpg --batch --yes --delete-secret-keys <FPR>`,
  daarna `--delete-keys`; uit GitHub-UI verwijderen.
- Intrekkingscertificaten in `~/.gnupg/openpgp-revocs.d/` bewaren.
- Persoonlijke key: bij `2y`-expiry tijdig vernieuwen (anders falen commits
  plotseling met een verlopen sleutel).

## Problemen en oorzaken (echt tegenaan gelopen)

| Symptoom | Oorzaak | Oplossing |
|---|---|---|
| `verified: False, no_user` bij geldige handtekening | UID-email niet verifieerbaar op account | noreply-formaat of geverifieerd adres gebruiken |
| GitHub weigert key bij toevoegen | ed25519 (plus mogelijk plakfout) | RSA-4096 + exact blok incl. BEGIN/END plakken |
| `commit failed: Geen geheime sleutel` | signingkey wijst naar afwezige key | `user.signingkey` op aanwezige fingerprint zetten |
| PR geblokkeerd na aanzetten regel | oude ongesigneerde commits in PR | rebase/squash met signing aan |
