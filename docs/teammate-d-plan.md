# Teammate D - UI Selection/Navigation Fixes Plan

## Analysis Date: 2026-02-09

---

## Bug Inventory

### Bug 1: Kit/Set expansion broken in Select Mode (GarageView.swift)

**Current behavior:** When isSelectMode is true, tapping a Tool Set row in GarageView
replaces the DisclosureGroup/expand row with a flat Button that only toggles selection.
The toolSetRow(for:normalContent:) helper completely replaces the ToolGroupRowView
(which contains the expand/collapse disclosure) with a flat ToolKitRowStyleWrapper.
Same for toolKitRow(for:normalContent:) which replaces the NavigationLink with a flat
button. Users cannot see what is inside a Kit or Set during select mode.

**Expected behavior:** In select mode, users should still be able to expand kits and sets
to see their contents. The disclosure should remain functional, with an added checkbox
on the group/kit header row for selection.

**Root cause:** toolSetRow(for:normalContent:) has an if isSelectMode branch. The
select-mode branch discards the disclosure group entirely and renders a non-expandable
ToolKitRowStyleWrapper with only a checkbox.

**Proposed fix:** In toolSetRow(), keep the expand/collapse behavior even in select mode.
Render the header with both a checkbox AND the expand/collapse chevron. When expanded,
show child tools with individual checkboxes.

---

### Bug 2: Tool rows inside kits/sets cannot be individually selected (GarageView.swift)

**Current behavior:** In select mode, only the Kit or Set itself can be selected as a
whole unit. Individual tools within are hidden (Bug 1) and have no checkboxes.

**Expected behavior:** Users should be able to expand a Kit/Set and select individual
tools within it, in addition to selecting the entire container.

**Root cause:** ToolGroupRowView struct has no awareness of isSelectMode. Its child tool
rows always render as NavigationLink.

**Proposed fix:** Pass isSelectMode, selectedTools, and a toggle callback into
ToolGroupRowView. When in select mode, replace NavigationLink on child tool rows with
a Button that toggles tool selection.

---

### Bug 3: NavigationLink fires in select mode for tools inside sets (GarageView.swift)

**Current behavior:** Inside ToolGroupRowView, child tools use
NavigationLink(destination: ToolDetailView(...)). In select mode, tapping a tool inside
a set navigates to ToolDetailView instead of toggling its selection.

**Expected behavior:** In select mode, tapping a tool inside a set should toggle its
selection checkbox, not navigate.

**Root cause:** ToolGroupRowView child tool rows always use NavigationLink. The view
has no isSelectMode parameter.

**Proposed fix:** Same as Bug 2 - pass isSelectMode into ToolGroupRowView and
conditionally render Button instead of NavigationLink.

---

### Bug 4: Date picker uses graphical style taking excessive space (NewJobView.swift)

**Current behavior:** The date picker uses .datePickerStyle(.graphical) which displays
a full calendar grid permanently. This consumes significant vertical space.

**Expected behavior:** Use .datePickerStyle(.compact) so the picker shows just the
selected date inline. Tapping reveals the calendar overlay.

**Root cause:** .datePickerStyle(.graphical) on the DatePicker.

**Proposed fix:** Change to .datePickerStyle(.compact).

---

### Bug 5: Consumable inline creation - NOT A BUG

GarageConsumablePickerView already supports inline creation (Feature #92) and
autocomplete suggestions (Feature #95). No fix needed.

---

## PR Breakdown

### PR 1: teammate-d/ui-fixes-1 - Fix kit/set expansion and selection in select mode

Bugs: 1, 2, 3 (tightly coupled)
Files: Views/Garage/GarageView.swift

### PR 2: teammate-d/ui-fixes-2 - Date picker compact style

Bugs: 4
Files: Views/NewJob/NewJobView.swift

---

## Test Plan

### PR 1 Tests

1. Enter select mode -> Tool Sets show chevron + checkbox
2. Tap chevron -> set expands showing child tools with checkboxes
3. Tap tool inside set -> toggles selection (does NOT navigate)
4. Tap set checkbox -> selects/deselects the set as a whole
5. Tool Kits same behavior as sets
6. Select All includes tools from sets/kits
7. Exit select mode -> normal NavigationLink behavior restored

### PR 2 Tests

1. Open New Job -> date picker shows compact inline (not full calendar)
2. Tap date -> calendar overlay appears
3. Default is todays date
