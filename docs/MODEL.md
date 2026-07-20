# Model management

## What ships today

| | |
| --- | --- |
| Model | Qwen2.5-1.5B-Instruct |
| Format | GGUF, Q4_K_M quantization (~1.07 GB) |
| License | Apache-2.0 |
| Inference | llama.cpp (pinned prebuilt xcframework), full Metal offload |
| SHA-256 | `6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e` |

## How the model reaches users

1. **Repository weights policy**: weights are never committed to git. They live as assets on the `models-v1` GitHub release, mirrored from Hugging Face by the manually-triggered *"Publish model release asset"* workflow (`.github/workflows/model-release.yml`).
2. **Release builds** (`release.yml`): `scripts/fetch-model.sh` downloads + checksum-verifies the GGUF, and `BUNDLE_MODEL=1 scripts/bundle-app.sh` copies it into `CapsBlink.app/Contents/Resources/Models/`. Users get a fully self-contained DMG.
3. **Runtime fallback** (dev builds, CI artifacts without a model): `ModelManager` looks for the model in this order —
   1. `CAPSBLINK_MODEL_PATH` env var,
   2. the app bundle's `Models/` resources,
   3. `~/Library/Application Support/CapsBlink/Models/`,
   and if absent downloads it (release asset first, Hugging Face fallback), showing progress in the status row and verifying the SHA-256 before use.

## Replacing or upgrading the model

The model identity is deliberately defined in exactly **two places** — keep them in sync:

1. `Sources/CapsBlinkKit/Models/ModelSpec.swift` → `ModelSpec.default` (file name, SHA-256, download URLs, size).
2. `scripts/fetch-model.sh` → `MODEL_FILE`, `MODEL_SHA256`, `HF_URL` defaults.

Procedure:

1. Pick a GGUF chat model that llama.cpp (at the pinned tag, see below) supports. For this workload prefer small instruct models (0.5–3 B) at Q4_K_M.
2. Get its SHA-256 and size, e.g. from the Hugging Face API (`lfs.oid` on the file entry) or `shasum -a 256` after downloading.
3. Update the two places above.
4. Run the *"Publish model release asset"* workflow to mirror the new file to the `models-v1` release (or bump `MODEL_RELEASE_TAG`/the URL if you want versioned model tags).
5. `make model && make test` locally, then sanity-check a real watch session (`CAPSBLINK_MODEL_PATH` also works for quick A/B tests).
6. Tag a release.

No code changes are needed for a different chat template — the template is read from the GGUF metadata (`llama_model_chat_template`) with a ChatML fallback.

## Upgrading llama.cpp

`scripts/fetch-llama.sh` pins the official prebuilt xcframework by release tag + zip SHA-256:

```sh
LLAMA_TAG="b10068"
LLAMA_SHA256="5238397d…"
```

To upgrade: pick a newer tag from [llama.cpp releases](https://github.com/ggml-org/llama.cpp/releases), download `llama-<tag>-xcframework.zip`, compute `shasum -a 256`, update both variables, `rm -rf Vendor && make deps && make test`. The Swift code uses the stable C API (`llama_model_load_from_file`, sampler chains, `llama_sampler_init_grammar`); breaking C API changes surface as compile errors in `Sources/CapsBlinkLlama/LlamaSession.swift`.

## Why not …

- **Apple Foundation Models / Core ML** — Foundation Models (macOS 26+) would remove the bundled weights entirely but pins the minimum OS far too high and gives less control over structured output; Core ML conversions of small LLMs are still clunkier than GGUF + llama.cpp.
- **MLX** — excellent on Apple Silicon, but no Intel support (we ship universal binaries) and heavier Swift dependency surface. llama.cpp's prebuilt universal xcframework covers both architectures with Metal on AS.
- **A bigger model** — verdicts are binary and diff-scoped; 1.5 B with a constrained grammar is already near-ceiling for this task, and app size/memory matter for a background utility.
