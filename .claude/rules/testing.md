---
paths:
  - "Cyclometer/CyclometerTests/**"
---

**Testing conventions** (target `CyclometerTests`):
- Reducer logic — Swift Testing (`@Suite`/`@Test`/`#expect`) + TCA `TestStore` with `withDependencies` for mocks (e.g. `SpeedFeatureTests.swift`).
- UI — `pointfreeco/swift-snapshot-testing` via XCTest, fixed-size canvases, light + dark variants (e.g. `SpeedWidgetSnapshotTests.swift`).
- Snapshot references are recorded against a local simulator (iPhone 17 Pro, iOS 27.0), so the snapshot suites are skipped in CI (see `.github/workflows/tests.yml`). The full local suite passes.
- Don't snapshot against ambient environment values (`.accentColor`, `.primary` where the token matters) — pass an explicit `cy*` token, or the reference silently encodes whatever the host bundle resolved at record time.
