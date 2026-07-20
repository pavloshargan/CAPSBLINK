# CapsBlink

Two tiny native macOS menu bar utilities that get your attention by **blinking the Caps Lock LED** — without ever toggling the actual Caps Lock state:

| App | What it watches | When it blinks |
| --- | --- | --- |
| **CapsBlink** | Any webpage (paste a URL) | A local LLM decides the page changed in a way you care about — a score changed, a match finished, a status flipped. The default prompt is tuned for live sports pages and is fully editable in Settings, so any page works. |
| **CapsBlink Agents** | Local coding agents (**Claude Code**, **Codex CLI**) | An agent finishes its turn and is waiting for you. The popover shows a per-agent indicator (idle / working / finished). |

Everything runs **locally**: no cloud APIs, no accounts, no telemetry. The only network traffic is fetching the page you asked to watch (and a one-time model download if you use a build without a bundled model).

## How CapsBlink works

1. Every interval (default 60 s) the page is fetched with polite conditional requests (ETag / `If-Modified-Since`).
2. HTML is reduced to visible text (scripts, styles, markup stripped).
3. A deterministic line diff gates everything: identical or merely reordered content never wakes the model.
4. Only when the text meaningfully differs, a local LLM (Qwen2.5-1.5B-Instruct, GGUF, llama.cpp with Metal) judges the diff against your instruction. Its output is grammar-constrained JSON — `{"notify": …, "reason": …}` — enforced at the sampler level.
5. On a positive verdict, the Caps Lock LED blinks in two short bursts, then re-syncs with the real modifier state.

## Install

Grab the DMG for either app from [Releases](../../releases), drag it to Applications, launch. The menu bar gets a ⇪ icon.

- Release DMGs are **universal** (Apple Silicon + Intel) and ship with the model **bundled** — no extra downloads.
- The apps are ad-hoc signed: on first launch use right-click → Open (or `xattr -cr /Applications/CapsBlink.app`).
- Grant **Input Monitoring** when prompted — macOS requires it to open keyboard HID devices, which is how the LED is driven. Without it the app still watches pages; it just can't blink.

## Build from source

Requirements: macOS 14+, Xcode (or CLT + Xcode for tests), `make`.

```sh
make deps    # one-time: downloads the pinned llama.cpp xcframework (checksum-verified)
make build   # debug build
make test    # unit tests
make app     # dist/CapsBlink.app (release, ad-hoc signed)
make agents-app
make dmg     # DMGs for both
```

Developer conveniences:

- `CAPSBLINK_MODEL_PATH=/path/to/model.gguf` — point a dev build at any local GGUF.
- Without a bundled model, CapsBlink downloads the model on first watch (status shows progress) to `~/Library/Application Support/CapsBlink/Models/`.
- `make model` + `BUNDLE_MODEL=1 make app` — produce a fully self-contained app locally.
- `make release VERSION=x.y.z` — the full distributable build: universal binaries, model bundled, DMGs for both apps (see [docs/RELEASING.md](docs/RELEASING.md)).

## Repository layout

```
Sources/
  CapsBlinkKit/       reusable core: fetch, extract, diff, LED, persistence, watch loop
  CapsBlinkLlama/     llama.cpp session + grammar-constrained classifier
  CapsBlinkAgentKit/  FSEvents-based Claude Code / Codex activity monitor
  CapsBlink/          page-watcher menu bar app
  CapsBlinkAgents/    coding-agent menu bar app
Tests/                unit tests per module
scripts/              fetch-llama, fetch-model, bundle-app, make-dmg
Vendor/               (generated) pinned llama.xcframework
docs/                 ARCHITECTURE, MODEL, RELEASING
```

`CapsBlinkKit`, `CapsBlinkLlama` and `CapsBlinkAgentKit` are library products — depend on them from your own tools if you want the machinery without the apps.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — components, data flow, key design decisions and tradeoffs.
- [docs/MODEL.md](docs/MODEL.md) — which model is bundled, why, and exactly how to replace or upgrade it.
- [docs/RELEASING.md](docs/RELEASING.md) — building distributable DMGs, versioning, real code signing.

## Privacy & security

- All inference is local (llama.cpp, Metal-accelerated).
- No API keys, no accounts, no analytics, no data collection.
- Network access: the watched URL, plus (only when no model is bundled) the model download from this repo's releases or Hugging Face — both checksum-verified.

## License

MIT — see [LICENSE](LICENSE). The bundled Qwen2.5 model is Apache-2.0.
