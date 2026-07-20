#!/usr/bin/env bash
# Downloads the GGUF model into Models/ and verifies its checksum.
#
# Sources, in order:
#   1. this repository's GitHub release assets (tag: models-v1)
#   2. the upstream Hugging Face repository
#
# These values must stay in sync with ModelSpec.default in
# Sources/CapsBlinkKit/Models/ModelSpec.swift — see docs/MODEL.md.
set -euo pipefail

MODEL_FILE="${MODEL_FILE:-qwen2.5-1.5b-instruct-q4_k_m.gguf}"
MODEL_SHA256="${MODEL_SHA256:-6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e}"
MODEL_RELEASE_TAG="${MODEL_RELEASE_TAG:-models-v1}"
HF_URL="${HF_URL:-https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/${MODEL_FILE}}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p Models
DEST="Models/$MODEL_FILE"

verify() {
    local actual
    actual="$(shasum -a 256 "$1" | cut -d' ' -f1)"
    [[ "$actual" == "$MODEL_SHA256" ]]
}

if [[ -f "$DEST" ]] && verify "$DEST"; then
    echo "Model already present and verified: $DEST"
    exit 0
fi

# Derive owner/repo from the git remote for the release-asset URL.
ORIGIN="$(git remote get-url origin 2>/dev/null || true)"
RELEASE_URL=""
if [[ "$ORIGIN" =~ github.com[:/]+([^/]+)/([^/.]+) ]]; then
    RELEASE_URL="https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/releases/download/${MODEL_RELEASE_TAG}/${MODEL_FILE}"
fi

for URL in $RELEASE_URL "$HF_URL"; do
    [[ -n "$URL" ]] || continue
    echo "Trying $URL"
    if curl --fail --location --progress-bar -o "$DEST.tmp" "$URL"; then
        if verify "$DEST.tmp"; then
            mv "$DEST.tmp" "$DEST"
            echo "Model downloaded and verified: $DEST"
            exit 0
        fi
        echo "warning: checksum mismatch from $URL, trying next source" >&2
        rm -f "$DEST.tmp"
    fi
done

echo "error: could not download a valid model" >&2
exit 1
