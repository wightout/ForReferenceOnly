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

| Model | Key Relationships | Notes |
|-------|-------------------|-------|
| `FROTool` | → `FROToolGroup?`, → `[FROJob]?`, → `[FROToolKit]?` | `isInGarage` flag for garage filtering |
| `FROToolGroup` | → `[FROTool]?` | Hierarchical grouping (NOT "tool sets") |
| `FROToolKit` | → `[FROTool]?` | Named collection of tools |
| `FROJob` | → `[FROJobRevision]?`, → `[FROTool]?`, → `[FROConsumable]?`, → `[FROChemical]?`, → `[FROPart]?` | Main work record |
| `FROJobRevision` | → `FROJob?` | Revision history |
| `FROChemical` | → `[FROJob]?` | Includes fluids as a category (no separate Fluid entity) |
| `FROConsumable` | → `[FROJob]?` | Expendable items |
| `FROPart` | → `[FROJob]?` | Replacement parts |
| `FROVoiceMemo` | — | Voice capture attachments |
| `FROAttachment` | — | Unified photo/file storage |
| `FROImportStaging` | — | Staged import conflict resolution |

**Important**: `CoreDataCompatibility.swift` defines type aliases (`Tool = FROTool`, etc.) — use `FRO*` names in new code.

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
# Build (Xcode 26+ / iOS 26.2 — use iPhone 17 series)
xcodebuild build -project ForReferenceOnly.xcodeproj -scheme ForReferenceOnly \
  -destination 'platform=iOS Simulator,id=6F09A806-24FA-4CAA-A140-86E7C6A80907'

# Test
xcodebuild test -project ForReferenceOnly.xcodeproj -scheme ForReferenceOnly \
  -destination 'platform=iOS Simulator,id=6F09A806-24FA-4CAA-A140-86E7C6A80907'
```

**Note**: iPhone 16 simulators are not available on Xcode 26. Use a specific device ID to avoid ambiguity with duplicate simulator names.

## Import Policy
Staged import + user-driven conflict resolution. No silent merges.
- UUID match = update candidate
- Name match = potential duplicate
- User chooses per-conflict: skip, replace, keep both

## Known Bugs & Status

| # | Priority | Bug | Status |
|---|----------|-----|--------|
| 1 | P0 | Backup round-trip — data integrity, hierarchy preservation | Open (needs verification) |
| 2 | P1 | Tool hierarchy — tools/kits/groups not added to jobs correctly | Root cause fixed (`inMemory: true` removed) — needs verification |
| 3 | P1 | Chemical creation crash from Job create/edit | Root cause fixed (`inMemory: true` removed) — needs verification |
| 4 | P3 | Job creation flow — consumables in-flow, date picker defaults | Root cause fixed (`inMemory: true` removed) — needs verification |

**Root cause (bugs 2-4)**: All `.sheet()` and `NavigationLink(destination:)` modifiers were wrapping child views in `.modelContainer(for: [...], inMemory: true)`, creating throwaway in-memory stores. Data saved in any sheet was lost on dismiss. Fixed by removing all 62 occurrences across 32 view files.

## Critical Notes

- **Single ModelContainer**: The app should use ONE `ModelContainer` created in `ForReferenceOnlyApp.swift` and passed via SwiftUI environment. `SharedModelContainer.shared` in `CoreDataCompatibility.swift` creates a SEPARATE container — services using it operate on a different store than views. This dual-container issue needs future consolidation.
- **No `inMemory: true` on sheets**: Never add `.modelContainer(for:..., inMemory: true)` to sheet or navigation destinations. Child views inherit the parent's container automatically.
- **"Fluid" is not a standalone entity**: It's a category within `FROChemical`. Don't create a Fluid model.
- **"Tool groups" not "tool sets"**: The entity is `FROToolGroup`. There is no ToolSet.

## Current Priority Order
1. P0: Data integrity — backup round-trip, hierarchy preservation
2. P1: Tool hierarchy — verify fix, test add-to-job flow
3. P1: Chemical creation — verify fix, test from job create/edit
4. P2: Subsets — edit, add/remove tools, photos
5. P3: Job creation — verify fix, test consumables in-flow

## Test Infrastructure

13 test files exist in `ForReferenceOnlyTests/`:
- Model tests (CRUD, relationships, validation)
- Service tests (import/export, tool operations)
- Extend existing tests rather than starting from scratch
