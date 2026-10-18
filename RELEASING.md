# Releasing Halfpast

How a new version gets from this folder to https://exmachina.in/halfpast/, and how the signing
and notarisation were set up — so a release can be made again on this Mac or a new one.

Nothing secret lives in this repository. The signing key and the notary password are in the
Mac's login keychain (and backed up outside the repo, see "On a new Mac").

## What a release is

- `dist/Halfpast-<version>.dmg` — the universal app (Apple silicon + Intel), signed with the
  Developer ID, hardened runtime, notarised by Apple and stapled, in a drag-to-Applications
  disk image.
- The same file in `docs/` (the website's "Download for Mac" button links to it by name) and
  attached to a GitHub release `v<version>`.
- The website is GitHub Pages from `main` / `docs/`. This repo shows at exmachina.in/halfpast
  because exmachina.in is the custom domain of the user site `rahulmatthan.github.io`; any
  public repo with Pages on appears under it at /<repo name>.

## Releasing a new version

1. **Bump the version** in `Resources/Info.plist`: `CFBundleShortVersionString` (e.g. 1.1) and
   `CFBundleVersion` (a whole number that only goes up: 2, 3, …).
2. **Build, sign and notarise**: `./build-dmg.sh`. It builds, signs the app (Developer ID,
   `--options runtime --timestamp`), makes the disk image, signs it, submits it to Apple with
   `notarytool --keychain-profile notary --wait` (usually 1–5 minutes), staples the ticket and
   checks it with `spctl`. The last line must say `notarised: dist/Halfpast-<version>.dmg`; if it
   says "signed but NOT notarised", the notary profile is missing — see below.
3. **Check it as a download would be checked**:
   `spctl -a -vv -t open --context context:primary-signature dist/Halfpast-<version>.dmg`
   → `accepted`, `source=Notarized Developer ID`.
4. **Update the website**:
   - `git rm docs/Halfpast-<old>.dmg` and copy the new one into `docs/`.
   - In `docs/index.html`, change the two `Halfpast-<old>.dmg` links, the version in the footer
     ("Halfpast 1.0"), and the size in the line under the button if it changed.
   - If the panels look different, refresh the screenshots (README › Build, the `HALFPAST_*`
     variables) into `docs/img/`.
5. **Commit and push.** Pages rebuilds in about a minute.
6. **GitHub release**: `gh release create v<version> dist/Halfpast-<version>.dmg --title "Halfpast <version>" --notes "<what changed>"`.
7. **Check the live download**: download https://exmachina.in/halfpast/Halfpast-<version>.dmg,
   `cmp` it with `dist/`, and run the `spctl` check on the downloaded copy.

The app has no auto-update: people get a new version by downloading it again. Settings live in
`~/Library/Application Support/Halfpast/places.json` and survive an update.

## Signing and notarisation — how they were set up

- **Apple Developer Program** membership: Rahul Matthan, Team ID **GAMJ6J6LT3**.
- **Certificate**: "Developer ID Application: Rahul Matthan (GAMJ6J6LT3)", in the login keychain
  with its private key. Issued 5 Oct 2026, valid until 17 Sep 2031. It signs anything
  distributed outside the Mac App Store (Halfpast, QuickCal, notchTP). `build-dmg.sh` names it in
  `IDENTITY`. Check it is present with `security find-identity -v -p codesigning`.
- **Notary credentials** (set up 18 Oct 2026): an app-specific password created at
  account.apple.com › Sign-In and Security › App-Specific Passwords ("Halfpast notary"), stored
  in the keychain once with
  ```
  xcrun notarytool store-credentials notary --apple-id <developer Apple ID> --team-id GAMJ6J6LT3
  ```
  Run it in a Terminal window (it prompts for the password without echoing it). Check it with
  `xcrun notarytool history --keychain-profile notary`. The profile name `notary` is what
  `build-dmg.sh` uses, and any other app can use it too.
- **No entitlements file** is needed: the app is not sandboxed and uses nothing the hardened
  runtime restricts.

## On a new Mac (or if signing stops working)

1. **The signing key.** In Keychain Access on a Mac that has it, find "Developer ID
   Application: Rahul Matthan" under My Certificates, expand it to check the private key is
   there, right-click › Export → a `.p12` with a password. Keep the `.p12` and its password
   outside the repo (the secrets disk image and/or 1Password). On the new Mac, double-click the
   `.p12` and enter the password. If the key is lost, create a new Developer ID Application
   certificate at developer.apple.com › Certificates (only the Account Holder can) — apps
   already shipped keep working.
2. **Xcode Command Line Tools** (`xcode-select --install`) — swiftc, codesign, notarytool,
   stapler. Xcode itself is not needed.
3. **The notary profile**: make a new app-specific password and run the `store-credentials`
   command above. (An app-specific password can be revoked and replaced at any time.)
4. Run `./build-dmg.sh` once and confirm the last line says `notarised`.

## If notarisation is rejected

`xcrun notarytool log <submission id> --keychain-profile notary` shows why. The usual causes:
something inside the app signed without the hardened runtime or without a timestamp, or an
expired certificate.
