---
paths:
  - "Cyclometer/CyclometerTests/**"
---

**Testing conventions** (target `CyclometerTests`):
- Reducer logic — Swift Testing (`@Suite`/`@Test`/`#expect`) + TCA `TestStore` with `withDependencies` for mocks (e.g. `SpeedFeatureTests.swift`).
- UI — `pointfreeco/swift-snapshot-testing` via XCTest, fixed-size canvases, light + dark variants (e.g. `SpeedWidgetSnapshotTests.swift`).
- Snapshot references are recorded against a local simulator (iPhone 17 Pro, iOS 27.0), so the snapshot suites are skipped in CI (see `.github/workflows/tests.yml`). The full local suite passes.
- Run and record only on the "Cyclometer Tests" simulator, `-destination "id=$(../scripts/test-simulator.sh)"`. It is erased each run, so no Device Hub setting (text size, Bold Text, contrast, language, region, 24-hour time) reaches a reference. Never record on a personal simulator (#648).
- Every snapshot passes `traits: .snapshot(…)` (`CyclometerTests/SnapshotTraits.swift`), e.g. `.image(layout: canvas, traits: .snapshot(.dark))`. It pins text size, Bold Text and contrast at iOS's defaults; the renderer's window has no scene, so an unset trait comes from the simulator. A snapshot testing one of them on purpose overrides it there: `.snapshot { $0.preferredContentSizeCategory = .accessibilityLarge }`. A fixture that draws a dynamic `UIColor` resolves it with these traits too (`color.resolvedColor(with: .snapshot())`), never a bare `setFill()`, which reads the simulator's appearance. Increase Contrast still reaches tinted system controls through UIKit, so the test simulator is what makes a run deterministic.
- When many unrelated snapshots fail at once, suspect the simulator before the code: run one failing suite on a freshly created device.
- Don't snapshot against ambient environment values (`.accentColor`, `.primary` where the token matters) — pass an explicit `cy*` token, or the reference silently encodes whatever the host bundle resolved at record time.
