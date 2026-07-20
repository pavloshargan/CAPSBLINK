# Releasing

Releases are built locally and uploaded to GitHub Releases by hand.

## Cutting a release

```sh
make release VERSION=1.0.0
```

This runs the whole chain: pinned llama.cpp xcframework (`make deps`) → model download + SHA-256 verification (`make model`) → **universal** (arm64 + x86_64) release builds → `.app` bundles (model inside CapsBlink, llama.framework embedded, ad-hoc signed) → compressed DMGs:

```
dist/CapsBlink-1.0.0.dmg        (~1.1 GB — model bundled)
dist/CapsBlinkAgents-1.0.0.dmg  (~200 kB)
```

Then create the release on GitHub (web UI, or `gh release create v1.0.0 dist/*.dmg`) and attach both DMGs. Tag with the matching `v1.0.0` so `git describe` stays meaningful.

Version stamping: `VERSION` becomes `CFBundleShortVersionString` and the DMG file names. If omitted, `git describe` output is used.

## Code signing & notarization

`make release` signs **ad-hoc** by default, which is fine for personal use but shows Gatekeeper friction (right-click → Open on first launch). For frictionless distribution with a paid Apple Developer account:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make release VERSION=1.0.0
xcrun notarytool submit dist/CapsBlink-1.0.0.dmg --keychain-profile <profile> --wait
xcrun stapler staple dist/CapsBlink-1.0.0.dmg   # repeat for the Agents DMG
```

`bundle-app.sh` automatically adds `--options runtime --timestamp` when the identity is not ad-hoc.

## Reproducibility notes

- llama.cpp is pinned by release tag **and** zip SHA-256 (`scripts/fetch-llama.sh`).
- Model weights are pinned by SHA-256 (`scripts/fetch-model.sh`, `ModelSpec`).
- The Swift code targets macOS 14+; the only unpinned input is the local Xcode/Swift toolchain.
