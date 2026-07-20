# CapsBlink — notes for contributors

- **First command in a fresh checkout: `make deps`.** `swift build` fails without it (`Vendor/llama.xcframework` is a local binaryTarget populated by `scripts/fetch-llama.sh`).
- `make test` — on machines where `xcode-select` points at CommandLineTools, the Makefile automatically routes through `/Applications/Xcode.app` (XCTest is not in the CLT SDK). If invoking `swift test` directly, set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Two apps, one package: `CapsBlink` (page watcher, windowed app, links llama.cpp) and `CapsBlinkAgents` (Claude Code/Codex watcher, menu bar, no LLM). Shared logic belongs in `CapsBlinkKit` (LLM-free) — keep it that way.
- To run from Xcode: `xed .` (opens the Swift package), pick the `CapsBlink` scheme → My Mac → Run. Set `CAPSBLINK_MODEL_PATH` in the scheme's environment to skip the model download.
- The model file name/SHA-256/URLs live in `ModelSpec.default` **and** `scripts/fetch-model.sh`; change both together (docs/MODEL.md has the procedure).
- llama.cpp C API calls are confined to `Sources/CapsBlinkLlama/LlamaSession.swift`; the pinned tag/checksum live in `scripts/fetch-llama.sh`.
- Blinking the LED needs the macOS Input Monitoring permission; when testing from a terminal the *terminal app's* permission applies.
- Release = `make release VERSION=x.y.z` locally, then upload `dist/*.dmg` to a GitHub release by hand (docs/RELEASING.md). There is no CI. Model weights are downloaded from Hugging Face (SHA-256 pinned), never committed.
