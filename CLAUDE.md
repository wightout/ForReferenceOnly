# FRO (For Reference Only) — Project Guide

## Overview
Aviation maintenance tool/job tracking iOS app. SwiftUI + SwiftData (iOS 17+).

## Architecture Rules
- **MVVM** — Views contain NO persistence, import/export, or business logic.
- **Persistence** — Only through `FRORepository` protocol (SwiftData-backed). No direct `ModelContext` queries in Views.
- **Import/Export** — Isolated in `ImportExportService`. JSON for data transfer; zip/package for exports with photos.
- **Stable UUIDs** — Every entity has a UUID `id` property, preserved across import/export.
- **Relationships** — Explicit modeling. No duplication as a relationship substitute.
- **Delete behavior** — Explicit and user-confirmed if destructive. Deleting a ToolGroup nullifies tool references (does NOT cascade-delete tools).

## Entity Model (SwiftData)
- `FROJob`, `FROJobRevision`, `FROTool`, `FROToolGroup`, `FROToolKit`
- `FROConsumable`, `FROChemical`, `FROPart`, `FROVoiceMemo`
- `FROAttachment` (unified photo/file), `FROImportStaging` (staged imports)

## File Organization
```
ForReferenceOnly/
  Models/          # SwiftData @Model classes
  ViewModels/      # ObservableObject view models
  Views/           # SwiftUI views (organized by feature)
  Services/        # Business logic services
  Extensions/      # Swift extensions
  Protocols/       # Protocol definitions
  Resources/       # Asset catalogs
```

## Git Workflow
- **main** — last-known-good release. No direct commits.
- **develop** — integration branch. All PRs target this.
- **Branch naming** — `teammate-X/description` (e.g., `teammate-a/ci-setup`)
- **PR rules** — Small PRs. Tests required. CI must pass. Review before merge.

## Definition of Done (per task)
1. Repro steps documented (or a test that reproduces the failure)
2. Root cause explained in 3-8 sentences
3. Fix implemented in a small PR
4. Unit tests added/updated for any model/import/export changes
5. App builds with zero warnings
6. Manual verification steps written and executed
7. CI green on PR

## Build & Test
```bash
# Build
xcodebuild build -project ForReferenceOnly.xcodeproj -scheme ForReferenceOnly -destination 'platform=iOS Simulator,name=iPhone 16'

# Test
xcodebuild test -project ForReferenceOnly.xcodeproj -scheme ForReferenceOnly -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Import Policy
Staged import + user-driven conflict resolution. No silent merges.
- UUID match = update candidate
- Name match = potential duplicate
- User chooses per-conflict: skip, replace, keep both

## Current Priority Order
1. P0: Data integrity — backup round-trip, hierarchy preservation, SwiftData baseline
2. P1: Tool hierarchy — duplication, selection in kits/sets, navigation
3. P2: Subsets — edit, add/remove tools, photos
4. P3: Job creation — consumables in-flow, date picker defaults
