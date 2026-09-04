# Building and packaging Zenith

Zenith is a personal, single-user, single-Mac app. There's no Apple
Developer Program membership, no notarization, and no CI/CD here on
purpose — this doc covers the lightweight local build/package flow that
decision implies. If that ever changes (the app gets shared with someone
else, or run on more than one Mac you don't control), notarization and a
real Developer ID certificate would need to be added — everything below
assumes that isn't the goal.

## Prerequisites

- Xcode (26.5 or later — the app targets macOS 14.0+, Swift 6).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install
  xcodegen`) — `macos/project.yml` is the source of truth for the Xcode
  project; `macos/Zenith.xcodeproj` is generated from it and shouldn't be
  hand-edited.
- No Apple ID needs to be signed into Xcode, and no signing certificate
  needs to exist in Keychain Access — see "Signing" below.

## Regenerating the Xcode project

Whenever `project.yml` changes (new source files are usually picked up
automatically via its `path:` globs, but target/build-setting changes
aren't):

```sh
cd macos
xcodegen generate
```

## Signing

`project.yml` pins the app target to **ad-hoc signing**
(`CODE_SIGN_STYLE: Manual`, `CODE_SIGN_IDENTITY: "-"`, no
`DEVELOPMENT_TEAM`) — this is exactly what Xcode's signing UI calls "Sign
to Run Locally" when you pick it by hand, just made reproducible from the
command line so a build doesn't depend on whatever team Xcode happens to
have selected. It needs no certificate, no keychain identity, and no
Apple ID — `codesign -dv` on the built app will show
`Signature=adhoc`/`TeamIdentifier=not set`, which is expected and correct
here, not a partial/failed signing.

One consequence worth knowing: `spctl -a` (Gatekeeper's own assessment
tool) reports this app as `rejected`, because ad-hoc signing has no
Developer ID and isn't notarized. That's only enforced by Gatekeeper for
apps that have the `com.apple.quarantine` extended attribute set — which
only gets attached when a file arrives via a browser download, AirDrop,
Mail, etc. A `.app` you build yourself and run directly (or one you copy
onto the same Mac without going through one of those channels) never
gets quarantined, so it launches normally with no "unidentified
developer" prompt. If you ever *do* copy the `.app`/`.dmg` somewhere that
quarantines it (e.g. uploading and re-downloading it), right-click →
Open once to bypass Gatekeeper, or `xattr -d com.apple.quarantine
Zenith.app`.

## Building a release build

From `macos/`:

```sh
xcodebuild -project Zenith.xcodeproj -scheme Zenith -configuration Release \
  -derivedDataPath /tmp/zenith-release-build \
  -destination 'platform=macOS' build
```

The built app lands at
`/tmp/zenith-release-build/Build/Products/Release/Zenith.app`. Copy it
wherever you actually want to keep/run it from (e.g. `/Applications`):

```sh
cp -R /tmp/zenith-release-build/Build/Products/Release/Zenith.app /Applications/
```

### Equivalent via Xcode's UI

This is what the command above does under the hood, if you'd rather use
Xcode directly:

1. Open `macos/Zenith.xcodeproj`.
2. **Product → Archive** (uses the `Zenith` scheme's `archive` build
   config, which `project.yml` pins to Release).
3. In the **Organizer** window that opens, select the archive → **Distribute
   App** → **Custom** → **Copy App**. (There's no Developer ID/App Store
   option available without a paid account, which is expected — "Copy
   App" is the right choice for a personal, locally-run build.)
4. Choose an export folder; Xcode drops `Zenith.app` there, already
   ad-hoc signed per `project.yml`.

## Packaging as a DMG (optional)

Not required to run the app — copying the `.app` to `/Applications`
directly is enough day to day. A DMG is only useful if you want a single
file to back up or move between volumes:

```sh
mkdir -p /tmp/zenith-dmg-stage
cp -R /tmp/zenith-release-build/Build/Products/Release/Zenith.app /tmp/zenith-dmg-stage/
ln -s /Applications /tmp/zenith-dmg-stage/Applications
hdiutil create -volname "Zenith" -srcfolder /tmp/zenith-dmg-stage \
  -ov -format UDZO ~/Desktop/Zenith.dmg
```

Mounting it gives the standard "drag Zenith.app onto the Applications
shortcut" layout. This has been verified end to end (built, signed,
DMG'd, mounted, launched from the mounted volume).

## First launch / data setup

Zenith talks directly to whatever Postgres database you point it at — no
bundled server, no migration step in the packaged app itself. On first
launch it shows a setup screen for the database connection string and
(optional) GitHub token; both are stored outside the app bundle
(`~/Library/Application Support/Zenith/config.json` for the database URL,
macOS Keychain for the GitHub token — see `docs/native-rewrite-audit.md`
decision 7), so reinstalling/rebuilding the app doesn't require
re-entering them unless that file/Keychain entry is removed.

## Database schema

The packaged app runs no migrations — it expects the schema to already
exist in whatever Postgres database you point it at. Schema changes are
authored with the dev-only Drizzle tooling at the repo root (`db/schema.ts`,
`drizzle/`) and applied by hand with `psql`; see the "Changing the
database schema" section of `AGENTS.md`.

## Updating the app later

There's no auto-updater (Sparkle or otherwise) — none was requested. To
install a new build, quit Zenith, rebuild per above, and replace the
`.app` in `/Applications`. Your database and Keychain-stored GitHub token
are unaffected either way, since neither lives inside the app bundle.
