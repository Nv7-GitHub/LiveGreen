# LiveGreen — Design Spec

Date: 2026-10-16 · Event: HackHarvard 2026 · Platform: iPhone, iOS 26+, SwiftUI with Liquid Glass

## 1. Purpose

LiveGreen is a sustainability scanner for regular people who want to be greener but don't know where to start or how to measure their changes. You point the phone at an item, appliance, meal or setup. The app:

1. breaks it into components,
2. puts numbers on each component's environmental cost, with sources,
3. suggests a greener swap for each component and shows the improvement,
4. generates a picture of the greener setup in the same room,
5. shows how you compare with a modeled peer cohort, and
6. (optional) controls a Shelly smart plug so chargers run only when the grid is clean.

### Success criteria
- A judge can scan an arbitrary object live, and in under ~20 s get components, metrics, swaps and a greener image.
- Every number can say where it came from (exact database record, researched spec sheet, factor model, or estimate), with a range and citations.
- Rescanning the same barcode or model number gives identical numbers.
- The demo still works if Wi-Fi to the plug fails (mock plug) and if a network API fails (cached/factor fallbacks).

### Non-goals
Real accounts and social graph, Android, iPad layout, backend server, monetization.

## 2. Key decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Reasoning/vision model | Claude (`claude-opus-5-5`, with `claude-sonnet-5-5` selectable for speed), called directly from the app |
| Greener image | xAI Grok image edit: `POST https://api.x.ai/v1/images/edits`, model `grok-imagine-image-2.0`, source photo as a base64 data URI |
| Number strategy | Hybrid **evidence ladder**: deterministic sources first, LLM estimate last; derived metrics computed in Swift |
| Network comparison | Simulated cohort built from onboarding answers plus published per-capita averages; seeded "friends" |
| Scan UX | Both **Photo + tappable boxes** and **AR anchored labels**, chosen by a `ScanMode` feature flag |
| Barcode/labels | On-device Vision barcode and text recognition feed identifiers into the pipeline |
| ASUS data | Bundled curated set of public ASUS Product Carbon Footprint (PCF) figures |
| Shelly | Real Gen2+ plug over the local RPC API. Fully optional: scans *recommend* a plug without one; pairing is a separate flow; mock plug for demos |
| Persistence | SwiftData, local only |
| Project generation | XcodeGen (`project.yml`) so the project file stays diff-friendly |

API keys live in an untracked `Secrets.xcconfig` (template `Secrets.example.xcconfig` is committed) and can be overridden in Settings (stored in Keychain).

## 3. Architecture

A single iOS app target plus a pure-Swift package for logic that can be tested without the simulator.

```
LiveGreen/                      (app target — UI, platform integrations)
  App/                          LiveGreenApp, RootView, AppModel, FeatureFlags
  Features/
    Onboarding/                 questionnaire → UserProfile
    Scan/                       ScanCoordinator, PhotoScanView, ARScanView, BarcodeLabelReader
    Results/                    ScanResultView, ComponentHotspots, FlowView, MetricInspector
    Alternatives/               AlternativesView, ComparisonChart, GreenerImageView
    Compare/                    PercentilesView, CohortDetail
    SmartPlug/                  PlugRecommendationCard, PairingFlow, PlugDashboard
    History/                    past scans
    Settings/                   keys, scan mode, model choice, plug on/off, mock toggles
  Platform/
    VisionOCR.swift             VNRecognizeText + VNDetectBarcodes
    ARSession+Anchoring.swift   raycast 2D boxes → world anchors
    Keychain.swift
  Resources/ReferenceData/      JSON tables (see §5)

Packages/GreenCore/             (Swift package, no UIKit)
  Model/                        Measured, Metric, Component, ScanResult, Tier, Source
  Engine/                       ImpactEngine (derivations + uncertainty), CohortModel, Percentiles
  Resolve/                      EvidenceLadder, resolvers per tier
  Clients/                      ClaudeClient, GrokImageClient, OpenFoodFactsClient,
                                EnergyStarClient, GridIntensityClient, ShellyClient
  Reference/                    ReferenceStore (loads bundled JSON)
  Tests/
```

Each client sits behind a protocol (`VisionIdentifier`, `SpecResearcher`, `ImageEditor`, `ProductDatabase`, `GridSignal`, `PlugController`) so tests and demo mode can swap in fakes.

## 4. Core data model

```swift
enum Tier: Int { case exactRecord = 1, researchedSpec, factorModel, estimate }

struct Source { let title: String; let url: URL?; let tier: Tier }

struct Measured {               // every number in the app is one of these
  let value: Double
  let low: Double, high: Double // uncertainty range
  let unit: MetricUnit
  let tier: Tier
  let sources: [Source]
}

enum MetricKey {                // the 12 metrics
  case carbon            // kg CO2e (embodied + use-phase, separable)
  case water             // L freshwater (blue water)
  case land              // m²·year
  case powerOn           // W
  case standbyPower      // W
  case yearlyElectricity // kWh/yr
  case lifespan          // years
  case repairability     // 0–10 (EU repairability index style)
  case plasticMass       // g, item + packaging split
  case recyclablePercent // %
  case decompositionTime // years
  case waterPollution    // g PO4e (eutrophication)
}

struct Component {
  let id: UUID
  let name: String
  let category: Category        // food, electronic, clothing, packaging, household, personalCare
  let boundingBox: CGRect       // normalized 0–1 in the captured frame
  let identifiers: Identifiers  // gtin, brand, model, materials, ocrText
  var metrics: [MetricKey: Measured]   // only metrics applicable to the category
  var usage: UsageProfile?      // hours/day on, standby hours, servings/week, wears/yr…
  var alternatives: [Alternative]
  var plugCandidate: PlugCandidate?    // set for deferrable chargers/loads
}

struct ScanResult { id, date, photo, components, totals: [MetricKey: Measured], greenerImage? }
```

Which metrics apply to which category is a static table, for example:
- food: carbon, water, land, water pollution, plastic, recyclable %, decomposition
- electronic: carbon, power on, standby, yearly kWh, lifespan, repairability, plastic, recyclable %

## 5. Scan & resolution pipeline

### 5.1 Capture
- **Photo mode:** `PhotosPicker` or the camera via `AVCaptureSession`. The captured still is shown full-bleed.
- **AR mode:** `ARView`/RealityKit with world tracking. A capture button grabs `ARFrame.capturedImage`. Components come back with 2D boxes; each box's center is raycast (`ARView.raycast(from:allowing:.estimatedPlane)`) to an `AnchorEntity` carrying a glass label. Tapping a label opens the same result UI.
- `FeatureFlags.scanMode` (`.photo` | `.ar`) is set in Settings and can be overridden with the launch argument `-ScanMode ar`.
- **Barcode/label mode:** a dedicated scanner using `DataScannerViewController` for live barcodes and text, for packaged goods and appliance labels.

### 5.2 On-device pre-pass
`VisionOCR` runs `VNDetectBarcodesRequest` and `VNRecognizeTextRequest` (accurate level) on the frame. It extracts:
- GTINs
- model-number-like tokens (regex for `[A-Z0-9-]{5,}` near words such as "Model"/"MOD")
- wattage (`\d+\s?W`)
- fiber percentages
- resin codes

These are passed to Claude as hints and used directly as identifiers.

### 5.3 Identify (Claude vision)
One Messages API call with the JPEG (long edge ≤ 1568 px), the OCR/barcode hints, the user profile summary, and a forced tool call `report_components`, whose JSON schema returns per component:
- name, category, normalized bounding box
- brand/model/GTIN when visible
- inferred quantities (mass, serving size, screen size, materials with % split)
- default usage assumptions
- `needsQuestion` entries: a question, why it matters, the metrics it affects, and answer options

Temperature is 0. The prompt includes the category→metrics table and tells the model to report identifiers and quantities, **not** final impact numbers.

### 5.4 Evidence ladder (per component, per metric)
`EvidenceLadder` tries resolvers in order and stops at the first that returns a value. Results from different tiers are kept per metric, so one component can mix tiers.

| Tier | Resolver | Data |
|---|---|---|
| T1 exact record | `OpenFoodFactsClient` (GTIN → product; `ecoscore_data.agribalyse` CO₂e/kg and per-stage breakdown, packaging materials and weights) | food, drink, packaging, personal care |
| T1 | `EnergyStarClient` (data.energystar.gov Socrata datasets, queried by brand + model number → on-mode W, standby W, annual kWh) | TVs, monitors, computers, appliances |
| T1 | Bundled `asus_pcf.json` (curated public ASUS PCF figures: model, total kg CO₂e, lifecycle-stage split, typical power) | ASUS electronics |
| T2 researched spec | `SpecResearcher` — a Claude call with the `web_search` and `web_fetch` server tools that must return values only alongside the URL and quoted text they came from; values without a citation are discarded | anything with a brand/model |
| T3 factor model | `ReferenceStore` tables × the quantities from 5.3 | everything |
| T4 estimate | Claude's bounded estimate from the identify call's fallback fields, with a deliberately wide range (±50%) | last resort |

Bundled reference tables (`Resources/ReferenceData/*.json`, each record with a citation):
- `food_factors.json`: kg CO₂e, L water, m²·yr land, g PO₄e per kg by food group (Poore & Nemecek 2018 / Our World in Data)
- `fiber_factors.json`: per-kg impacts for cotton, polyester, wool, nylon, linen, etc.
- `material_endoflife.json`: decomposition years, recyclability %, plastic flag per material
- `device_defaults.json`: typical on/standby W, lifespan, repairability by device type (ENERGY STAR / EU repairability averages)
- `grid_intensity.json`: annual average gCO₂e/kWh by eGRID subregion and by country, plus a 24-hour hourly shape per region for fallback
- `per_capita.json`: per-capita yearly carbon, water, land and electricity by country/US state, with diet and household-size modifiers
- `asus_pcf.json`

Cache: resolved component metrics are stored in SwiftData keyed by GTIN or `brand|model`. A cache hit skips the ladder, so the same identifier always gives the same numbers.

### 5.5 Questions
After resolution, the app shows a question only if both of these hold:
- the question is in `needsQuestion`, and
- the affected metric's range is wide (high/low > 1.6) *and* it is one of the component's top-two contributors to carbon.

All questions appear together in one glass sheet with chip answers and a "Use estimate" button. Each answer updates `UsageProfile` and the engine re-runs locally, with no extra network call.

### 5.6 Impact engine (deterministic, `GreenCore`)
- `yearlyElectricity = powerOn × hoursOn × 365 + standby × standbyHours × 365 / 1000`
- `useCarbon = yearlyElectricity × gridIntensity(region)`. Total carbon = embodied ÷ lifespan + annual use (shown both as "per year" and "lifetime").
- Food: impacts per kg × kg per serving × servings per week × 52 for the yearly view.
- Uncertainty: each `Measured` is treated as lognormal with low/high as its ~90% interval. Sums and products are propagated with a fixed-seed 2,000-sample Monte Carlo. The seed comes from the scan id, so results are reproducible.
- Totals per scan and per user year feed into percentiles (§9).

## 6. Results UI (features 1 & 2)

- **Hotspots:** the photo (or AR view) with a glass rounded rectangle per component (`.glassEffect(.regular.interactive(), in: .rect(cornerRadius:))`). The tint shows the component's carbon share. A `GlassEffectContainer` makes the hotspots morph together as they appear.
- **Metric picker:** a glass segmented control for Carbon · Electricity · Water · Land · Plastic · All.
- **Flow view (feature 1):** tapping a component opens a sheet with a Sankey-style flow drawn in SwiftUI `Canvas`: lifecycle stages (materials → manufacturing → transport → use → end of life) on the left, flowing into the selected metric's total. Band widths are proportional, and stage values come from OFF/ASUS stage splits when available, otherwise from the factor model's stage split.
- **Inspector (feature 2):** below the flow, or beside it in landscape, a glass inspector lists every applicable metric as a `Measured` row: value, range bar, tier badge (T1–T4 with color), and a "Sources" disclosure with tappable citations. This is "on the right" on iPhone landscape and a detent sheet in portrait.
- The scan's summary header shows totals plus a confidence meter: the share of total carbon resolved at T1/T2.

## 7. Alternatives & greener image (feature 3 + pipeline step 6)

- **Generating alternatives:** one Claude call per scan with a forced tool `suggest_alternatives`. For each component it returns 1–3 alternatives with name, category, identifiers or quantities, and rationale.
- **Same treatment as originals:** alternatives go through the same evidence ladder and engine, so comparisons are like-for-like. Each alternative carries a `practicality` tag (cost tier, effort).
- **Smart plug as an alternative:** when a component is a deferrable load (e-bike, e-scooter or laptop charger, power bank, dishwasher, washer, EV charger), the plug option is added *locally* as an alternative ("Shelly smart plug + green-hours scheduling") with savings from §8.3.
- **Comparison view:** Swift Charts bar pairs (current vs. alternative) per key metric, with range whiskers and a "% better" chip. The user picks one alternative per component, defaulting to the biggest carbon saving.
- **Greener image:** after the user confirms their picks, `GrokImageClient` sends the original photo and an edit prompt built from the chosen swaps. The prompt asks to replace each listed object at its location, keep everything else (lighting, layout, camera angle) unchanged, and stay photorealistic. The result appears in a before/after slider with glass handles, and a "projected savings" card sums the yearly deltas.
- **Failure handling:** if the image call fails, the user sees a retry button. The numeric comparison is never blocked by the image.

## 8. Smart plug (feature 6)

### 8.1 Optional by design
- Settings has a "Smart plug features" toggle, on by default.
- Without a paired plug, eligible components still show a **Plug recommendation card**: "Charging this only when the grid is clean would save ~X kg CO₂e/yr. Pair a Shelly plug →".
- Turning the toggle off hides the cards and the plug alternative.

### 8.2 Pairing flow (separate feature)
1. Instructions screen: put the plug in AP mode, or have it already on home Wi-Fi.
2. Discovery: Bonjour `_shelly._tcp` browse (requires `NSLocalNetworkUsageDescription` and `NSBonjourServices`), with manual IP entry as fallback.
3. Verify: `GET http://<ip>/rpc/Shelly.GetDeviceInfo` (Gen2+ only; Gen1 shows "unsupported").
4. Optional: if the device has auth enabled, ask for its password and use HTTP digest auth.
5. Name the plug and assign it to a scanned component (for example "E-bike charger").
6. **Mock plug:** a `MockPlugController` with a simulated power draw, selectable in pairing for demos.

### 8.3 Green-hours scheduling
- **Grid signal:** `GridIntensityClient` uses Electricity Maps (`/v3/carbon-intensity/latest` and `/history`, free key) for the user's zone. It falls back to the bundled regional 24-h shape scaled to the annual average.
- **Forecast:** the median hourly intensity of the same hour over the last 7 days of history (or the bundled shape).
- **Plan:** given the charge's required hours per day (from the component's kWh ÷ charger W), choose the cleanest N hours in the next 24 that fit the user's "must be done by" time.
- **Enforce on the plug, not the phone:** the app writes the plan to the plug with `Schedule.DeleteAll` + `Schedule.Create` (cron timespecs calling `Switch.Set on/off`). The plug follows the schedule even when the app is closed. The plan is refreshed whenever the app is foregrounded, plus a `BGAppRefreshTask` best-effort.
- **Dashboard:** live `Switch.GetStatus` (apower W, aenergy), current grid intensity, today's chosen green hours as a 24-h glass timeline, manual override.
- **Savings shown:** `kWh/yr × (avgIntensity − scheduledWindowIntensity)`. It is shown as an estimate on recommendation cards and accumulated from measured `aenergy` × actual hourly intensity when a real plug is running.

## 9. Profile, cohort & percentiles (features 4 & 5)

- **Onboarding** (glass cards, 6–8 questions, editable later):
  - ZIP/country (→ grid region and per-capita baseline)
  - household size
  - diet (omnivore / flexitarian / vegetarian / vegan)
  - commute mode and km/week
  - home type and heating source
  - typical shopping habits (new vs. second-hand clothing)
  - device-charging items owned (e-bike / scooter / EV)
- **Cohort model** (`CohortModel`, deterministic):
  - For each metric (carbon, water, land, electricity), build a lognormal peer distribution. The median is the per-capita baseline for the user's region, adjusted by the profile modifiers from `per_capita.json`; the spread (σ) comes from published inequality figures stored in that file.
  - The user's annualized footprint for the scanned categories is the sum of yearly impacts of scanned items, in scope only: we compare *category sub-footprints*, not whole-life footprints we never measured.
  - Percentile = lognormal CDF of the user's value in the cohort for the same categories. Shown as "You're greener than 68% of people like you."
- **Updating:** every saved scan updates the annualized totals and re-computes percentiles. A trend sparkline shows percentile over time.
- **Network:** 8 seeded "friends" sampled deterministically from the cohort distribution (fixed seed, with names and avatars) give a leaderboard. They're clearly labeled as a "simulated network" in Settings and the About screen.

## 10. Liquid Glass UI shell

- `TabView` with the iOS 26 floating glass tab bar: **Scan**, **History**, **Compare**, **Plugs** (hidden when plug features are off), plus a search-role tab for history search. `tabBarMinimizeBehavior(.onScrollDown)`.
- Scan is the default tab: a full-bleed camera with a glass capture button (`.buttonStyle(.glass)` / `.glassProminent`) and a glass mode switch (Photo / AR / Barcode).
- Sheets use system glass detents. Toolbars use the default glass. Custom floating controls use `GlassEffectContainer` and `glassEffectID` for morphing transitions between capture → analyzing → results.
- **Analyzing state:** a glass progress card shows live pipeline steps (Reading labels → Identifying → Looking up records → Researching specs → Computing), driven by an `AsyncStream<PipelineEvent>` so it reflects real progress.
- Green accent palette; supports Dark Mode and Dynamic Type.

## 11. Error handling

- **Network errors per resolver:** a failure drops that resolver and the ladder continues to the next tier. The tier badge makes the downgrade visible. Errors are never shown as numbers.
- **Claude identify failure:** retry once, then show an error card with Retry. Barcode-only items can still resolve via OFF without Claude.
- **Missing or invalid keys:** a Settings banner names the missing key. **Demo mode** (Settings) replays bundled fixture scans (three canned scenes: desk setup, meal, e-bike corner) end to end, with no network.
- **Plug unreachable:** the dashboard shows "offline since …". Schedules on the plug keep working, and the user can switch to the mock plug.
- **Timeouts:** identify 30 s, research 45 s per component (run concurrently, max 4), image 60 s.

## 12. Testing

- **`GreenCore` unit tests (XCTest/Swift Testing)**, run with `swift test`:
  - `ImpactEngine` formulas
  - Monte Carlo determinism (same seed → same output)
  - evidence-ladder ordering and fallthrough using fake resolvers
  - `CohortModel` percentiles against hand-computed lognormal CDF values
  - green-hours planner (cleanest-N-hours with deadline)
  - Shelly schedule cron generation
  - OFF/ENERGY STAR/Claude tool-output JSON decoding from recorded fixtures
  - reference-table integrity (every record has a citation, units are valid)
- **App UI smoke tests:** launch in Demo mode, run a fixture scan, open a component, open alternatives, open the comparison.
- **Manual demo checklist:** a real scan in each mode, a barcode item, a real plug pair and schedule write.

## 13. Delivery stages (one commit + push per stage)

1. Scaffold: XcodeGen project, `GreenCore` package, secrets template, Liquid Glass tab shell, README run instructions.
2. Core model + impact engine + reference data tables + tests.
3. Clients: Claude (identify, alternatives, research), OFF, ENERGY STAR, Grok image, with fixture-based tests.
4. Evidence ladder + caching + questions flow.
5. Photo scan mode + Vision OCR/barcode + results hotspots + flow view + inspector.
6. AR scan mode behind the feature flag.
7. Alternatives + comparison + greener image.
8. Onboarding + cohort + percentiles + Compare tab.
9. Smart plug: recommendation cards, pairing, Shelly client, grid signal, planner, dashboard, mock.
10. Demo mode fixtures, polish, UI smoke tests.
