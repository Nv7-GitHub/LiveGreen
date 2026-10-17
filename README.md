# LiveGreen

HackHarvard 2026. A sustainability scanner for iPhone (iOS 26, SwiftUI, Liquid Glass). Point the phone at an item, appliance, meal or setup and LiveGreen breaks it into components, puts sourced numbers on each one, suggests greener swaps, renders the greener setup, compares you with a modeled peer cohort and can schedule a Shelly smart plug for clean-grid hours.

The design spec is in [`docs/superpowers/specs/2026-10-16-livegreen-design.md`](docs/superpowers/specs/2026-10-16-livegreen-design.md).

## Setup

Requirements: Xcode 26+, an iOS 26 simulator or device.

```sh
brew install xcodegen
cp Secrets.example.xcconfig Secrets.xcconfig   # then fill in the keys below
xcodegen generate                              # creates LiveGreen.xcodeproj (not committed)
open LiveGreen.xcodeproj
```

| Key (in `Secrets.xcconfig`) | Used for | Required |
|---|---|---|
| `ANTHROPIC_API_KEY` | Claude identify, alternatives, spec research | yes (except demo mode) |
| `XAI_API_KEY` | Grok greener-image edit | yes (except demo mode) |
| `ELECTRICITYMAPS_API_KEY` | Live grid carbon intensity | yes (falls back to bundled shape) |
| `ENERGYSTAR_APP_TOKEN` | ENERGY STAR Socrata queries | optional |

The keys go into Info.plist at build time. Any key can also be entered in **Settings → API keys**, which stores it in the Keychain and overrides the xcconfig value. A fresh clone builds without `Secrets.xcconfig` because the include is optional.

Run `xcodegen generate` again after pulling. `project.yml` globs the source folders, so adding a file never needs a `project.yml` change.

### Command line

```sh
# Package tests (pure logic, runs on the Mac)
cd Packages/GreenCore && swift test

# App build
xcodegen generate
xcodebuild -project LiveGreen.xcodeproj -scheme LiveGreen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build/DerivedData build

# UI smoke test (demo mode)
xcodebuild -project LiveGreen.xcodeproj -scheme LiveGreen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build/DerivedData test
```

## Architecture

```
LiveGreen/                    app target (UI and platform integrations)
  App/                        LiveGreenApp, RootView (glass TabView), AppModel, FeatureFlags, ServiceContainer
  Features/                   Onboarding, Scan (ScanCoordinator + capture modes), Results, Alternatives,
                              Compare, SmartPlug, History, Settings
  Platform/                   Keychain, Secrets (Vision OCR and AR anchoring go here too)
  Persistence/                SwiftData models: StoredScan, CachedMetrics, StoredProfile; ScanStore, ScanCache
  DesignSystem/               Theme (green palette, tier colors), GlassCard, TierBadge, number formatting
  Resources/                  Assets
Packages/GreenCore/           Swift package with no UIKit/SwiftUI dependency
  Sources/GreenCore/Model     Tier, Source, Measured, MetricKey, Category, Component, ScanResult, UserProfile…
  Sources/GreenCore/Services  Protocols for every external dependency, plus their DTOs
  Sources/GreenCore/Resolve   EvidenceLadder, EstimateResolver (T4), QuestionGate
  Sources/GreenCore/Engine    ScanTotals (the Monte Carlo ImpactEngine lands here)
  Sources/GreenCoreFakes      Fake* implementations and demo fixtures (desk, meal, e-bike corner)
```

**Pipeline.** `ScanCoordinator.scan(image:hints:)` returns an `AsyncThrowingStream<PipelineEvent, Error>`. It identifies components (`VisionIdentifier`), then runs the evidence ladder in tier order (T1 exact record → T2 researched spec → T3 factor model → T4 estimate), using a SwiftData cache keyed by GTIN or brand|model. It then gates follow-up questions and finishes with `.completed(ScanResult)`. Every number is a `Measured` value with a range, tier and sources.

**Services.** Each external dependency sits behind a GreenCore protocol: `VisionIdentifier`, `AlternativeSuggester`, `SpecResearcher`, `ImageEditor`, `ProductDatabase`, `ApplianceDatabase`, `GridSignal`, `PlugController`, `ReferenceProviding` and `MetricResolver`. `ServiceContainer.make(flags:secrets:)` builds the set the app uses, and `ServiceContainer.demo()` builds the offline fakes.

## Feature flags

The flags are set in Settings and persisted in UserDefaults. Launch arguments override them (Xcode scheme → Run → Arguments, or `XCUIApplication.launchArguments`):

| Flag | Default | Launch argument |
|---|---|---|
| Scan mode (`photo` / `ar` / `barcode`) | `photo` | `-ScanMode ar` |
| Demo mode (offline fixture scans) | off | `-DemoMode YES` |
| Smart plug features (Plugs tab, cards) | on | `-PlugFeatures NO` |
| Claude model (`opus` = claude-opus-5-5, `sonnet` = claude-sonnet-5-5) | opus | `-ModelChoice sonnet` |
| Mock plug | off | `-MockPlug YES` |

Launch-only arguments: `-SkipOnboarding YES` and `-InMemoryStore YES` (a throwaway SwiftData store, used by UI tests).

The peer "friends" on the Compare leaderboard are a **simulated network** sampled from the modeled cohort.
