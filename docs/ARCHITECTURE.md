# Architecture

## Modules

```
┌─────────────────┐     ┌──────────────────────┐
│    CapsBlink     │     │   CapsBlinkAgents    │   menu bar apps (SwiftUI)
└────────┬────────┘     └──────────┬───────────┘
         │                          │
┌────────▼────────┐     ┌──────────▼───────────┐
│  CapsBlinkLlama  │     │  CapsBlinkAgentKit   │   llama.cpp classifier / FSEvents monitor
└────────┬────────┘     └──────────┬───────────┘
         │                          │
         └──────────┬──────────────┘
              ┌─────▼──────┐
              │ CapsBlinkKit │   reusable, dependency-free core
              └────────────┘
```

- **CapsBlinkKit** — everything generic: fetching, extraction, diffing, notification (LED), model management, persistence, and the `PageWatcher` orchestrator. No AppKit windows, no llama.cpp. This is the layer to reuse in other tools.
- **CapsBlinkLlama** — the only module that links llama.cpp (via a prebuilt `llama.xcframework` binary target). Implements `ChangeClassifier` with grammar-constrained JSON output.
- **CapsBlinkAgentKit** — watches coding-agent transcript directories with FSEvents and turns write activity into a per-agent state machine.
- **CapsBlink / CapsBlinkAgents** — thin SwiftUI `MenuBarExtra` apps; each is an `@Observable` view model bound to the corresponding kit actor.

## Page-watcher data flow

```
timer tick (PageWatcher actor, default 60 s)
  → PageFetcher        conditional GET (ETag/Last-Modified); 304 ⇒ done, no work
  → HTMLTextExtractor  strip script/style/markup, decode entities, collapse whitespace
  → ChangeDetector     SHA-256 short-circuit + order-preserving multiset line diff
        no diff ⇒ done (LLM never runs)
  → ChangeClassifier   LlamaChangeClassifier: chat-templated prompt with the user's
                       watch instruction + added/removed lines; GBNF grammar forces
                       {"notify": bool, "reason": string}
  → ChangeNotifier     CapsLockBlinkNotifier: LED bursts, then restore modifier state
  → SnapshotStore      persist baseline so relaunches don't re-notify
```

Every stage is a protocol or value type injected into `PageWatcher`, so each is independently testable and replaceable (e.g. swap the notifier for a HomeKit light, or the classifier for a remote model if you really wanted one).

## Key design decisions

### llama.cpp as a prebuilt, pinned xcframework
llama.cpp removed SwiftPM support in late 2024; building it from source in every dev checkout/CI run is slow and needs the Metal toolchain. Instead `scripts/fetch-llama.sh` downloads the **official prebuilt `llama.xcframework`** from llama.cpp's GitHub releases, pinned by tag + SHA-256, and `Package.swift` consumes it as a local `binaryTarget`. Upgrading llama.cpp = bump two variables in one script. Tradeoff: `make deps` is a required one-time step before `swift build` (SPM can't express "remote zip whose xcframework is nested in a subdirectory").

### Model choice: Qwen2.5-1.5B-Instruct Q4_K_M
The task is a binary classification over a small text diff — not generation quality. A 1.5 B model at Q4_K_M (~1.1 GB) is the sweet spot: noticeably more reliable than 0.5 B models at instruction following, loads in a couple of seconds with Metal, runs a verdict in well under a second, and is Apache-2.0 (no Llama-license strings attached). See docs/MODEL.md for swapping it.

### Structured output via GBNF, not prompting
The sampler is constrained with a GBNF grammar so the model *cannot* emit anything but `{"notify": true|false, "reason": "…"}`. Greedy decoding keeps verdicts deterministic. Parsing failures are still handled (fail-open: notify), but the grammar makes them practically unreachable.

### Caps Lock LED without touching Caps Lock
`CapsLockLED` opens keyboard HID devices via `IOHIDManager` and writes the **LED output element** (`kHIDPage_LEDs` / `kHIDUsage_LED_CapsLock`) directly — the modifier state never changes, so typing is unaffected. After blinking, the LED is re-synced to the true modifier state (queried via `CGEventSource`). macOS requires the *Input Monitoring* permission to open keyboard HID devices; both apps surface that in their UI. Everything is behind the `ChangeNotifier` protocol, so hardware without a controllable LED (or a denied permission) degrades cleanly — `CompositeNotifier` can stack fallbacks.

### Change detection before inference
The LLM is the most expensive component, so two deterministic gates run first: HTTP 304 (no download body at all) and an exact-text/multiset-line-diff comparison (no inference). Reordered lines — common on pages that shuffle widgets — produce no diff. The model only ever sees *added and removed lines*, not whole pages, which keeps prompts small and verdicts focused.

### Agent monitoring via FSEvents, not polling
Claude Code appends to `~/.claude/projects/**/<session>.jsonl` and Codex CLI to `~/.codex/sessions/**/rollout-*.jsonl` while they work. `AgentActivityMonitor` subscribes to those trees with FSEvents (coalesced, ~zero idle cost) and applies a state machine: sustained writes ⇒ *working*; quiet for `quietThreshold` (10 s) after real activity ⇒ *finished* ⇒ blink. Known tradeoff: a long-running silent tool call can look "finished" early; the threshold errs toward a spurious blink over a late one.

### Performance posture
- Idle = one sleeping task (page watcher) + FSEvents subscription (agents). No timers firing per second while nothing happens (the agents app ticks 1 Hz only while enabled).
- The model loads once per watch session and is released when watching is disabled (`unloadClassifier`).
- Fetches are conditional; extraction caps text at 60 kB; prompts cap the diff at 40 lines/side.

## Error handling philosophy

- Fetch errors: tolerated up to 3 consecutive failures before surfacing an error status; the loop keeps retrying either way.
- Model unavailable (download failed, no disk): the watcher **degrades** to `HeuristicChangeClassifier` (notify on any substantive diff) instead of dying.
- Classifier errors mid-flight: fail-open and notify — a spurious blink beats a missed goal.
