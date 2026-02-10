# Contributing to FRO (For Reference Only)

## Getting Started

1. Clone the repo and open `ForReferenceOnly.xcodeproj` in Xcode
2. Select an iPhone simulator target (iPhone 17 series on Xcode 26+)
3. Build and run

## Branch Workflow

All work follows the branch strategy in `docs/WORKFLOW.md`:

- **`main`** — Release branch. Merge from `develop` only.
- **`develop`** — Integration branch. All PRs target here.
- **`teammate-X/description`** — Feature/fix branches.

## Making Changes

1. Create a branch from `develop`: `teammate-X/description`
2. Make your changes — keep PRs small and focused
3. Add or update tests for model, import, or export changes
4. Verify the build compiles with zero warnings
5. Run the test suite: `xcodebuild test -scheme ForReferenceOnly -destination 'platform=iOS Simulator,id=6F09A806-24FA-4CAA-A140-86E7C6A80907'`
6. Open a PR targeting `develop`

## Code Style

- SwiftUI + SwiftData (iOS 17+)
- MVVM pattern — no persistence logic in Views
- All persistence through `FRORepository` protocol
- Stable UUIDs on every entity, preserved across import/export

## Definition of Done

See `CLAUDE.md` for the full checklist. In short: repro steps, root cause, small PR, tests, zero warnings, manual verification, CI green.
