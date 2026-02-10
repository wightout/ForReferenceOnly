# FRO (For Reference Only) — Agent Team Prompt

## 1. PROJECT OVERVIEW

**FRO** is an aviation maintenance tool/job tracking iOS app for mechanics to catalog tools, chemicals, consumables, parts, and job records.

- **Tech stack:** SwiftUI + SwiftData (iOS 17+)
- **GitHub:** `wightout/ForReferenceOnly`
- **Architecture:** MVVM + Repository pattern
- **Read `CLAUDE.md` at repo root first** — it has all architecture rules and conventions.

---

## 2. CURRENT STATE

The codebase is functional with the full SwiftData migration complete. Here's what already exists:

### Models (11 SwiftData @Model classes)
`FROTool`, `FROChemical`, `FROConsumable`, `FROPart`, `FROJob`, `FROToolGroup`, `FROToolKit`, `FROJobRevision`, `FROVoiceMemo`, `FROAttachment`, `FROImportStaging`

### Services (23 files)
Core business logic including:
- `SwiftDataRepository` — implements `FRORepository` protocol
- `ImportExportService`, `ImportService` — staged import with conflict resolution
- `ExportService`, `JobExportService`, `JobImportService`, `ToolExportService`, `ToolImportService` — entity-specific import/export
- `ToolService`, `ChemicalService`, `ConsumableService`, `JobRecordService`, `ToolGroupService` — CRUD services
- `SearchService`, `PDFService`, `VoiceCaptureService`, `TranscriptionCandidateService`
- `ToolPhotoService`, `ToolSizeSortingService`, `ToolNameFormatter`
- `ZipUtility`, `CoreDataCompatibility`, `AuthService`

### Views (42+ SwiftUI views)
Organized by feature: Dashboard, Garage, Import, JobDetail, NewJob, Onboarding, Search, Settings, Shared (including autocomplete fields)

### ViewModels
- `ImportStagingViewModel` — drives the staged import UI
- Other views use Services directly via Repository. **Expand MVVM as needed** for new features.

### Tests (13 test files — EXTEND these, don't start from scratch)
- `SwiftDataModelTests`, `SwiftDataRelationshipTests`, `MigrationSmokeTest`
- `FRORepositoryTests`, `ImportExportRoundTripTests`
- `ToolServiceTests`, `ChemicalServiceTests`, `ConsumableServiceTests`
- `JobRecordServiceTests`, `ToolGroupServiceTests`, `SearchServiceTests`
- `ToolSizeSortingServiceTests`, `ForReferenceOnlyTests`

### CI
GitHub Actions workflow at `.github/workflows/ios.yml`

---

## 3. ARCHITECTURE

### Persistence
All data access goes through the `FRORepository` protocol (implemented by `SwiftDataRepository`). **No direct `ModelContext` queries in Views.** The protocol provides: `fetch`, `fetchAll`, `fetchById`, `insert`, `delete`, `save`.

### MVVM (partial)
`ImportStagingViewModel` exists. Other views call Services directly via Repository. Team should add ViewModels as needed when view logic grows complex.

### Import/Export
Isolated in `ImportExportService`. JSON for data transfer. ZIP archives for exports with photos:
- `.frobackup` — full backup archive
- `.frotool` — tool export archive
- `.frojob` — job export archive

### Key Rules
- **Stable UUIDs** — every entity has a UUID `id`, preserved across import/export
- **Delete behavior** — explicit and user-confirmed. ToolGroup delete nullifies tool references (does NOT cascade-delete tools)
- **No duplication as relationship substitute** — use explicit relationships

---

## 4. ENTITY MODEL

### FROTool
Properties: `name`, `aliases: [String]?`, `ownershipType` (personal/borrowed), `borrowedFrom?`, `photoFileNames: [String]?`, `isInGarage`, `notes?`
Relationships: belongs to `FROToolGroup?`, many-to-many with `FROJob`, many-to-many with `FROToolKit`

### FROChemical
Properties: `name`, `category` (other/fluid/lubricant/etc.), `size?`, `spec?`, `isInGarage`, `notes?`
Relationships: many-to-many with `FROJob`
**IMPORTANT:** "fluid" is a CATEGORY value within FROChemical, NOT a separate entity. UI labels may say "Hazmat" but the internal model stays `FROChemical`. Add CodingKeys or JSON mapping for backward compat if needed.

### FROConsumable
Properties: `name`, `category`, `size?`, `spec?`, `isInGarage`, `notes?`
Relationships: many-to-many with `FROJob`

### FROPart
Properties: `partNumber`, `alternatePartNumber?`, `nomenclature`, `nsn?`, `quantity`, `unitOfMeasure?`, `notes?`
Relationships: many-to-many with `FROJob`

### FROJob
Properties: `aircraftType`, `aircraftSerialNumber?`, `nNumber?`, `system`, `component?`, `jobDate`, `taskDescription?`, `tmReferences?`, `notes?`, `recommendations?`, `currentVersion`
Relationships: has-many `tools`, `consumables`, `chemicals`, `parts`, `revisions`; has-one `voiceMemo?`

### FROToolGroup
Properties: `name`, `sortOrder`, `ownershipType`, `toolType?`, `measurementType?`, `photoFileNames: [String]?`
Relationships: self-referencing hierarchy (`parentGroup?` / `childGroups`), has-many `tools` (delete rule: nullify)
**NOTE:** "tool sets" DO NOT EXIST in this codebase. `FROToolGroup` handles all hierarchical grouping.

### FROToolKit
Properties: `name`, `descriptionText?`, `ownershipType`, `toolType?`, `photoFileNames: [String]?`
Relationships: many-to-many with `FROTool`

### FROJobRevision
Properties: `versionNumber`, `snapshotData: Data?`, `editedAt`, `editNotes?`
Relationships: belongs to `FROJob`

### FROVoiceMemo
Properties: `audioFilePath?`, `transcriptionText?`, `transcriptionStatus`, `identifiedTools: [String]?`, `identifiedConsumables: [String]?`, `identifiedChemicals: [String]?`
Relationships: belongs to `FROJob`

### FROAttachment
Properties: `fileName`, `fileType`, `notes?`, `createdAt`

### FROImportStaging
Properties: `importSessionId`, `entityType`, `entityId`, `jsonData: Data`, `status`, `conflictType?`, `matchedEntityId?`, `resolution?`

---

## 5. KNOWN BUGS (Priority Order)

1. **P0: Data integrity** — backup round-trip fidelity, tool hierarchy preservation, SwiftData baseline stability
2. **P1: Tool hierarchy** — Tools / tool kits / tool groups not being added to jobs correctly; duplication issues when selecting tools; navigation within group hierarchy broken
3. **P1: Chemical creation** — Create/add chemical from Job create/edit crashes. This covers all chemical categories including fluids (which are a category of `FROChemical`, not a separate entity).
4. **P2: Entity creation** — Creating entities (tools, chemicals, consumables, parts) from within Job create/edit may crash or not persist
5. **P2: Tool group/kit editing** — Edit views for tool groups and kits, add/remove tools from groups/kits, photo management
6. **P3: Job creation flow** — Consumables not added in-flow, date picker defaults incorrect

---

## 6. FILE ORGANIZATION

```
ForReferenceOnly/
  Models/                    # 11 SwiftData @Model classes
  ViewModels/                # ImportStagingViewModel (expand as needed)
  Views/
    Dashboard/               # DashboardView, JobImportReviewView
    Garage/                  # Add/Edit/Detail/Picker views for tools, chemicals, consumables, groups, kits
    Import/                  # ImportJobView, ImportStagingReviewView
    JobDetail/               # EditJobView, JobDetailView, RevisionDetailView, VersionHistoryView
    NewJob/                  # NewJobView, CandidateReviewView, VoiceCaptureView, PartEntryView
    Onboarding/              # WelcomeView
    Search/                  # SearchView
    Settings/                # AboutView
    Shared/                  # ContentView, autocomplete fields, AddToGaragePromptView
  Services/                  # 23 service files
  Protocols/                 # FRORepository protocol
  Extensions/                # Swift extensions
  Resources/                 # Asset catalogs (app icon)
  ForReferenceOnlyTests/     # 13 test files
  docs/                      # WORKFLOW.md
  CLAUDE.md                  # Project guide — READ THIS FIRST
  Info.plist
```

---

## 7. BUILD & TEST

```bash
# Build (adjust simulator name to what's available on your machine)
xcodebuild build -project ForReferenceOnly.xcodeproj -scheme ForReferenceOnly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Test
xcodebuild test -project ForReferenceOnly.xcodeproj -scheme ForReferenceOnly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# List available simulators if the above doesn't work
xcrun simctl list devices available
```

---

## 8. GIT WORKFLOW

- **main** — last-known-good release. No direct commits.
- **develop** — integration branch. All PRs target this.
- **Branch naming** — `teammate-X/description` (e.g., `teammate-a/ci-setup`)
- **PR rules** — Small PRs. Tests required. CI must pass. Review before merge.

---

## 9. IMPORT POLICY

Staged import + user-driven conflict resolution. No silent merges.
- UUID match → update candidate
- Name match → potential duplicate
- User chooses per-conflict: skip, replace, keep both
- Implementation: `ImportExportService` + `ImportStagingViewModel` + `ImportStagingReviewView`

---

## 10. DEFINITION OF DONE

1. Repro steps documented (or a test that reproduces the failure)
2. Root cause explained in 3-8 sentences
3. Fix implemented in a small PR
4. Unit tests added/updated for any model/import/export changes
5. App builds with zero warnings
6. Manual verification steps written and executed
7. CI green on PR

---

## 11. CRITICAL NOTES FOR AGENTS

- **No "fluids" entity.** "Fluid" is a `category` value within `FROChemical`. Never create a separate Fluid model.
- **No "tool sets."** Use `FROToolGroup` for all hierarchical tool grouping. The term "tool set" does not map to any entity.
- **Chemical vs Hazmat:** The UI may label chemicals as "Hazmat" but the SwiftData model is `FROChemical`. This is a UI-label-only distinction. If import/export JSON uses "hazmat", add CodingKeys or JSON mapping — do NOT rename the model.
- **13 test files exist.** Extend them when adding features or fixing bugs. Don't create a parallel test structure.
- **MVVM is partial.** `ImportStagingViewModel` is the only ViewModel. Other views call Services directly. Add ViewModels when view logic warrants it.
- **Archive formats:** `.frobackup` (full backup), `.frotool` (tool export), `.frojob` (job export) — all ZIP archives containing JSON + optional photo files.
- **All entities use stable UUIDs.** Never generate new UUIDs for existing entities during import. Match by UUID first, then by name for conflict detection.
