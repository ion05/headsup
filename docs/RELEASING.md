# Releasing

HeadsUp updates itself with [Sparkle](https://sparkle-project.org). Every release is a GitHub Release with three files: `HeadsUp.dmg` (for new installs), `HeadsUp.zip` (what Sparkle downloads) and `appcast.xml` (the feed installed copies check daily, via `releases/latest/download/appcast.xml`).

## Prerequisites (once per Mac)

- A **Developer ID Application** certificate in your login keychain.
- Notarization credentials saved as a keychain profile. The script uses `mix-notary` unless you set `NOTARY_PROFILE`:
  ```sh
  xcrun notarytool store-credentials mix-notary --apple-id <you@example.com> --team-id 27UZT2RBW3
  ```
- The Sparkle EdDSA private key in your login keychain. It's shared with Mix, so it's already there if you release Mix. On a new Mac, import it with `.build/artifacts/sparkle/Sparkle/bin/generate_keys -f <exported-key-file>`. Check that `generate_keys -p` prints the `SUPublicEDKey` value in `Info.plist`.
- `brew install create-dmg gh`, and `gh auth login`.

## The one command

```sh
scripts/release.sh 1.2.0             # build, sign, notarize, staple; files land in build/release
scripts/release.sh 1.2.0 --publish   # same, then commit the version bump, tag v1.2.0, push, create the GitHub release
```

A new version number gets the next build number in `Info.plist`. Running the same version again repackages it with the same build number. The script stops if your tree has uncommitted changes, or if the build number isn't higher than the one already published. Release notes come from that version's `## ` section in `CHANGELOG.md`.

## Updates need a public repo

Assets on a private GitHub repo can't be downloaded without signing in, so installed copies can't read the feed or download the update until `ion05/headsup` is public. Until then, background checks fail silently and Check Now in Settings shows an error.
