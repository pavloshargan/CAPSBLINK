# CapsBlink build entry points. Run `make help` for a summary.

# swift test needs XCTest, which the bare CommandLineTools SDK lacks.
# Route through Xcode.app automatically when the CLT is selected.
ifeq ($(shell xcrun --find xctest >/dev/null 2>&1 && echo ok),)
ifneq ($(wildcard /Applications/Xcode.app),)
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
endif
endif

.PHONY: help deps build test run model app agents-app apps dmg release clean

help:
	@echo "Targets:"
	@echo "  deps       download the pinned llama.cpp xcframework into Vendor/ (required once)"
	@echo "  build      debug build of everything"
	@echo "  test       run the unit tests"
	@echo "  model      download the GGUF model into Models/ (only needed to bundle it)"
	@echo "  app        release .app bundle for CapsBlink (page watcher) in dist/"
	@echo "  agents-app release .app bundle for CapsBlinkAgents in dist/"
	@echo "  apps       both apps"
	@echo "  dmg        DMGs for both apps (uses dist/*.app)"
	@echo "  release    everything: universal apps, model bundled, DMGs (set VERSION=x.y.z)"
	@echo "  clean      remove build products (keeps Vendor/ and Models/)"
	@echo ""
	@echo "Useful variables: UNIVERSAL=1 BUNDLE_MODEL=1 VERSION=x.y.z SIGN_IDENTITY='Developer ID …'"

deps:
	scripts/fetch-llama.sh

build: deps
	swift build

test: deps
	swift test

model:
	scripts/fetch-model.sh

app: deps
	scripts/bundle-app.sh CapsBlink

agents-app: deps
	scripts/bundle-app.sh CapsBlinkAgents

apps: app agents-app

dmg:
	scripts/make-dmg.sh CapsBlink
	scripts/make-dmg.sh CapsBlinkAgents

# Full distributable build: universal binaries, model bundled into CapsBlink,
# DMGs for both apps in dist/. Upload the DMGs to a GitHub release manually.
release: deps model
	VERSION="$(VERSION)" UNIVERSAL=1 BUNDLE_MODEL=1 scripts/bundle-app.sh CapsBlink
	VERSION="$(VERSION)" UNIVERSAL=1 scripts/bundle-app.sh CapsBlinkAgents
	VERSION="$(VERSION)" scripts/make-dmg.sh CapsBlink
	VERSION="$(VERSION)" scripts/make-dmg.sh CapsBlinkAgents

clean:
	rm -rf .build dist
