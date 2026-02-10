# FRO Team Workflow

## Branch Strategy

| Branch | Purpose | Direct Commits? |
|--------|---------|-----------------|
| `main` | Release branch. Last-known-good state. | **No** -- merge from `develop` only |
| `develop` | Integration branch. All work merges here first. | **No** -- PRs only |
| `teammate-X/description` | Feature/fix branches | Yes |

## Branch Naming

All branches follow the pattern: `teammate-X/description`

Examples:
- `teammate-a/ci-setup`
- `teammate-b/fix-import-duplication`
- `teammate-c/tool-hierarchy-nav`

## Pull Request Rules

1. **All PRs target `develop`** -- never directly to `main`.
2. **CI must pass** before merge (build + test green).
3. **Keep PRs small** -- one logical change per PR.
4. **Write a clear description** -- what changed, why, and how to test.
5. **Add/update tests** for any model, import, or export changes.

## CI Pipeline

Every push to `develop` and every PR triggers:
- **Build** -- `xcodebuild build` with code signing disabled
- **Test** -- `xcodebuild test` runs the full test suite

CI is defined in `.github/workflows/ci.yml`.

## Release Process

1. Ensure `develop` is stable (CI green, manual QA done).
2. Create a PR from `develop` to `main`.
3. After merge, tag the release: `git tag v0.X.Y && git push --tags`

## Definition of Done (per task)

1. Repro steps documented (or a test that reproduces the failure)
2. Root cause explained in 3-8 sentences
3. Fix implemented in a small PR
4. Unit tests added/updated
5. App builds with zero warnings
6. Manual verification steps written and executed
7. CI green on PR
