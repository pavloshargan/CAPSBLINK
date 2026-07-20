# Releasing

## Pipelines

| Workflow | Trigger | Output |
| --- | --- | --- |
| `ci.yml` | push to `main`, PRs | build + tests + ad-hoc-signed .app zips (no model) as CI artifacts |
| `release.yml` | push a `v*` tag | GitHub Release with universal DMGs for **both** apps, model bundled |

No setup or secrets are required; workflows use the default `GITHUB_TOKEN`. Model weights are downloaded from Hugging Face during release builds (SHA-256 pinned, cached between runs).

## Cutting a release

```sh
git tag v1.0.0
git push origin v1.0.0
```

The release workflow then: fetches the pinned llama.cpp xcframework (cached) → fetches + verifies the model (cached) → runs tests → builds universal binaries → assembles both `.app` bundles (model inside CapsBlink) → wraps DMGs → creates the GitHub Release with install notes.

Version stamping: the tag (minus `v`) becomes `CFBundleShortVersionString` and the DMG file names.

## Code signing & notarization

CI signs **ad-hoc** (`SIGN_IDENTITY=-`), which is fine for personal use but shows Gatekeeper friction (right-click → Open). For frictionless distribution:

1. Add a Developer ID Application certificate to the repo (e.g. via `apple-actions/import-codesign-certs`).
2. Set `SIGN_IDENTITY="Developer ID Application: …"` in the bundle steps — `bundle-app.sh` automatically adds `--options runtime --timestamp` for real identities.
3. Add a notarization step (`xcrun notarytool submit dist/*.dmg --wait` + `xcrun stapler staple`) after DMG creation.

## Reproducibility notes

- llama.cpp is pinned by release tag **and** zip SHA-256 (`scripts/fetch-llama.sh`).
- Model weights are pinned by SHA-256 (`scripts/fetch-model.sh`, `ModelSpec`).
- CI runs on `macos-15` images; the Swift code targets macOS 14+ and uses no APIs newer than that.
- The only unpinned inputs are the runner's Xcode/Swift toolchain.
