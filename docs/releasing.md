# Releasing

Push a version tag and GitHub Actions does the rest:

```bash
git tag v1.2.0
git push origin v1.2.0
```

The tag is the only place the version is set.

## What the workflow does

[`release.yml`](../.github/workflows/release.yml):

1. Runs the tests.
2. Builds a universal app and signs it with Developer ID.
3. Sends it to Apple for notarization and checks that Gatekeeper accepts it.
4. Publishes a GitHub release with two files: `LookAway.dmg`, for people
   downloading the app, and `LookAway.zip`, for the in-app updater.
5. Updates the cask in
   [connortorrell/homebrew-tap](https://github.com/connortorrell/homebrew-tap).

A tag with a hyphen, like `v1.2.0-rc1`, is published as a prerelease. The
in-app updater and Homebrew ignore prereleases, so this is a safe way to test
the pipeline.

## Dry run

To package locally with an ad hoc signature and check the DMG and zip without
a certificate:

```bash
make dist VERSION=0.0.0 NOTARIZE=0
```

## Repository secrets

| Secret                      | What it is |
|-----------------------------|------------|
| `DEVELOPER_ID_P12_BASE64`   | The Developer ID Application certificate and key, exported from Keychain Access as `.p12`, then `base64 -i cert.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen when exporting it |
| `NOTARY_KEY_P8_BASE64`      | An App Store Connect API key (Users and Access → Integrations, Developer role), `base64 -i AuthKey_XXXX.p8` |
| `NOTARY_KEY_ID`             | That key's ID |
| `NOTARY_ISSUER_ID`          | The issuer ID shown above the keys list |
| `HOMEBREW_TAP_TOKEN`        | A fine-grained token with Contents: read and write on `connortorrell/homebrew-tap` only |

## Homebrew tap

The tap repo's `Casks/look-away.rb` started as a copy of
[`scripts/homebrew-cask.rb`](../scripts/homebrew-cask.rb). The workflow
updates its version and checksum on each release.
