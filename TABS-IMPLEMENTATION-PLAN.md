# Sniffly Tabs Implementation Plan

## Overview
Add browser-style tabs to Sniffly for multi-directory viewing without window clutter.

## Design Decisions

### Architecture
- **Tab limit**: 5 tabs maximum (configurable constant)
- **Scan strategy**: Serialize scans (one active scan at a time, queue others)
- **Widget strategy**: Single drawing area, swap data on tab switch
- **Memory strategy**: Keep all tab data in memory (lazy approach for MVP)
- **Layout**: Tab bar on right side of toolbar, grows leftward

### State Management
- Encapsulate ALL per-tab state in `tab_state` type
- No global state except `active_tab_index` and `tabs` array
- Each tab fully independent with own history, scan state, view

---

## Phase 1: Core Infrastructure (Must Have)

### 1.1 State Encapsulation
**Goal**: Move all global state to per-tab structures

**Tasks**:
- [ ] Create `tab_state` type in new `src/gui/tab_manager.f90`
  - [ ] Path (current scan directory)
  - [ ] Navigation history array + position + count
  - [ ] Root node pointer (scan tree)
  - [ ] Current view node pointer
  - [ ] Selected index
  - [ ] Show hidden files flag
  - [ ] Show extensions flag
  - [ ] Render mode (flat/cushioned)
  - [ ] Scan state (embedded `scan_state_type`)
  - [ ] Tab label/title (last path segment)

- [ ] Create `tab_manager` module with:
  - [ ] `tabs(MAX_TABS)` array
  - [ ] `active_tab_index` integer
  - [ ] `num_tabs` counter
  - [ ] Functions:
    - [ ] `create_tab(path)` - Initialize new tab
    - [ ] `close_tab(index)` - Cleanup and remove tab
    - [ ] `switch_to_tab(index)` - Make tab active
    - [ ] `get_active_tab()` - Return pointer to current tab
    - [ ] `get_tab(index)` - Return pointer to specific tab

- [ ] Audit `gtk_app.f90` for global state:
  - [ ] `global_scan_path` → per-tab
  - [ ] `nav_history`, `nav_history_pos`, `nav_history_count` → per-tab
  - [ ] `navigating_history` flag → per-tab

- [ ] Audit `treemap_renderer.f90` for global state:
  - [ ] `current_view` → per-tab
  - [ ] `root_node` → per-tab
  - [ ] `selected_index` → per-tab
  - [ ] `show_hidden_files` → per-tab
  - [ ] `show_extensions` → per-tab
  - [ ] `render_mode` → per-tab

- [ ] Audit `progressive_scanner.f90`:
  - [ ] `scan_state` → per-tab (one scan context per tab)
  - [ ] Modify scan functions to accept `tab_index` parameter
  - [ ] Track which tab owns active scan

### 1.2 Scan Serialization
**Goal**: Prevent concurrent scans and I/O contention

**Tasks**:
- [ ] Add scan queue to `tab_manager.f90`:
  - [ ] `scan_queue(MAX_TABS)` - tab indices waiting to scan
  - [ ] `scan_queue_head`, `scan_queue_tail`, `scan_queue_size`
  - [ ] `active_scan_tab_index` - which tab is scanning (0 = none)

- [ ] Create scan queueing functions:
  - [ ] `request_scan(tab_index, path)` - Add to queue or start immediately
  - [ ] `process_scan_queue()` - Start next scan when current finishes
  - [ ] `cancel_scan_for_tab(tab_index)` - Remove from queue or stop if active

- [ ] Modify `progressive_scanner.f90`:
  - [ ] Add `active_tab_for_scan` parameter
  - [ ] Scan completion callback triggers `process_scan_queue()`
  - [ ] Only update UI if scanning tab is active

- [ ] Update scan buttons:
  - [ ] Show "Waiting..." status if tab queued but not scanning
  - [ ] Cancel button removes from queue or stops active scan

### 1.3 Tab UI Components
**Goal**: Create visual tab bar and interaction

**Tasks**:
- [ ] Create `src/gui/tab_widget.f90`:
  - [ ] `create_tab_bar()` - Returns GTK box containing tabs
  - [ ] `create_tab_button(tab_index, label)` - Individual tab with close X
  - [ ] `create_add_tab_button()` - Plus button for new tabs
  - [ ] `update_tab_highlights()` - Yellow border on active tab
  - [ ] `refresh_tab_bar()` - Rebuild entire tab bar (on add/close)

- [ ] Tab button design:
  - [ ] Width: 120px (enough for label + close button)
  - [ ] Height: 28px (compact)
  - [ ] Active: 2px yellow border (#FFD700)
  - [ ] Label: Last segment of path (truncate if needed)
  - [ ] Close button: Small X on right (8x8px)

- [ ] Layout integration in `gtk_app.f90`:
  - [ ] Add horizontal box below toolbar
  - [ ] Tab bar aligned to right side
  - [ ] Grows leftward as tabs added
  - [ ] Plus button always on left edge of tab bar

- [ ] Tab interactions:
  - [ ] Click tab → `switch_to_tab(index)`
  - [ ] Click close X → `close_tab(index)` (with confirmation if scanning)
  - [ ] Click plus → `create_tab(current_path_parent)` or show directory picker

### 1.4 Tab Switching Logic
**Goal**: Seamlessly switch between tab contexts

**Tasks**:
- [ ] Implement `switch_to_tab(index)` in `tab_manager.f90`:
  - [ ] Save current tab state (selected index, scroll position if any)
  - [ ] Set `active_tab_index = index`
  - [ ] Load new tab state into rendering context
  - [ ] Update breadcrumb to new tab's path
  - [ ] Update status bar with new tab's stats
  - [ ] Update treemap widget data pointers
  - [ ] Trigger full redraw

- [ ] Update all navigation functions:
  - [ ] Get active tab first: `tab = get_active_tab()`
  - [ ] Operate on tab's state, not globals
  - [ ] Update tab's history, not global history

- [ ] Update all button handlers:
  - [ ] Back/Forward use active tab's history
  - [ ] Up navigates active tab's tree
  - [ ] Rescan targets active tab

### 1.5 Resource Cleanup
**Goal**: Prevent memory leaks on tab close

**Tasks**:
- [ ] Implement `close_tab(index)` in `tab_manager.f90`:
  - [ ] Check if last tab → prevent close (must have at least 1)
  - [ ] Check if scan active → confirm with user dialog
  - [ ] Cancel scan if active: `cancel_scan_for_tab(index)`
  - [ ] Deallocate file tree: `recursive_deallocate_node(tab.root_node)`
  - [ ] Clear history array
  - [ ] Shift remaining tabs down (compact array)
  - [ ] Decrement `num_tabs`
  - [ ] If closed active tab → activate tab to the right (or left if last)
  - [ ] Refresh tab bar UI

- [ ] Create recursive deallocation:
  - [ ] `recursive_deallocate_node(node)` in types or tab_manager
  - [ ] Free children array recursively
  - [ ] Deallocate path strings
  - [ ] Nullify pointers

- [ ] Add confirmation dialog:
  - [ ] `show_close_tab_confirmation(tab_index)` if scan active
  - [ ] "Tab is scanning. Close anyway?" with Cancel/Close buttons

### 1.6 Keyboard Shortcuts
**Goal**: Cmd-1 through Cmd-5 switch tabs, Cmd-T new tab

**Tasks**:
- [ ] Add to key handler in `treemap_widget.f90` or `gtk_app.f90`:
  - [ ] Cmd-1 → `switch_to_tab(1)`
  - [ ] Cmd-2 → `switch_to_tab(2)`
  - [ ] ...
  - [ ] Cmd-5 → `switch_to_tab(5)`
  - [ ] Cmd-T → `create_tab()` with directory picker
  - [ ] Cmd-W → `close_tab(active_tab_index)` with confirmation

- [ ] Handle out of bounds:
  - [ ] If `num_tabs < requested_index` → ignore or beep
  - [ ] Show feedback if tab doesn't exist

---

## Phase 2: Should Have Features

### 2.1 Tab Close Safety
**Goal**: Prevent accidental data loss

**Tasks**:
- [ ] Prevent closing last tab:
  - [ ] Disable close button if `num_tabs == 1`
  - [ ] Grey out close X
  - [ ] Cmd-W does nothing if last tab

- [ ] Confirm close if scan active:
  - [ ] Native dialog: "Scanning in progress. Close tab anyway?"
  - [ ] Only show if scan > 10% complete (skip if just started)

- [ ] Confirm close if large tree:
  - [ ] If tree has > 10,000 nodes → confirm
  - [ ] "This tab contains a large scan. Close anyway?"

### 2.2 Tab Tooltips
**Goal**: Show full path on hover

**Tasks**:
- [ ] Add tooltip to each tab button:
  - [ ] Full path of tab's current directory
  - [ ] Scan status: "Scanning (45%)", "Ready", "Queued"
  - [ ] Item count: "1,234 items"

- [ ] Use GTK tooltip API:
  - [ ] `gtk_widget_set_tooltip_text(tab_button, full_info)`
  - [ ] Update tooltip on scan progress, navigation

### 2.3 Graceful Memory Degradation
**Goal**: Handle low memory conditions

**Tasks**:
- [ ] Warn on tab creation if memory high:
  - [ ] Check system memory (platform-specific)
  - [ ] If > 80% used → warn "System memory low. New tab may be slow."

- [ ] Limit tab count dynamically:
  - [ ] If memory pressure detected → disable plus button
  - [ ] Show message: "Maximum tabs reached (memory limit)"

### 2.4 Tab Reordering
**Goal**: Let users organize tabs

**Tasks**:
- [ ] Add drag-and-drop to tab buttons:
  - [ ] GTK drag source on each tab
  - [ ] GTK drop target on tab bar
  - [ ] On drop: reorder `tabs` array
  - [ ] Update `active_tab_index` if it changed
  - [ ] Refresh tab bar

- [ ] Alternative: Shift-Left/Right arrow to move active tab:
  - [ ] Cmd-Shift-[ → move tab left
  - [ ] Cmd-Shift-] → move tab right

---

## Phase 3: Nice to Have Features

### 3.1 Tab Color Coding
**Goal**: Visual distinction between tabs

**Tasks**:
- [ ] Assign color to each tab:
  - [ ] Predefined palette: Blue, Green, Orange, Purple, Teal
  - [ ] Cycle through colors as tabs created
  - [ ] 3px colored bar on top of tab button

- [ ] Color persistence:
  - [ ] Store color in `tab_state`
  - [ ] Let user click to cycle colors (shift-click tab?)

### 3.2 Recently Closed Tabs
**Goal**: Undo accidental tab close

**Tasks**:
- [ ] Track last 5 closed tabs:
  - [ ] `recently_closed_tabs` array with path + timestamp
  - [ ] Don't store full tree (too much memory)

- [ ] Restore closed tab:
  - [ ] Cmd-Shift-T → reopen last closed tab
  - [ ] Rescan directory (don't restore old tree)
  - [ ] Right-click on plus button → "Recently Closed" menu

### 3.3 Tab Persistence Across Sessions
**Goal**: Remember open tabs on quit/relaunch

**Tasks**:
- [ ] Save tab state on quit:
  - [ ] Write `~/.config/sniffly/tabs.conf`
  - [ ] Format: one path per line
  - [ ] Include active tab marker

- [ ] Restore tabs on launch:
  - [ ] Read config file
  - [ ] Create tab for each path
  - [ ] Don't scan immediately (lazy)
  - [ ] Scan active tab only, others on-demand

### 3.4 Duplicate Tab
**Goal**: Explore same directory in parallel

**Tasks**:
- [ ] Add "Duplicate Tab" action:
  - [ ] Right-click tab → "Duplicate"
  - [ ] Or Cmd-D keyboard shortcut
  - [ ] Create new tab with same path
  - [ ] Copy history if desired

### 3.5 Tab Renaming
**Goal**: Custom labels for tabs

**Tasks**:
- [ ] Double-click tab label to edit:
  - [ ] Show inline text entry
  - [ ] Save custom name in `tab_state.custom_label`
  - [ ] Use custom label instead of path segment

- [ ] Clear custom name:
  - [ ] Right-click → "Reset Label"
  - [ ] Reverts to automatic path-based label

### 3.6 Split View Within Tab
**Goal**: Advanced layout (future consideration)

**Tasks**:
- [ ] Allow horizontal split within tab:
  - [ ] Two treemaps side-by-side
  - [ ] Shared tab context, independent views
  - [ ] This is VERY advanced - only if highly requested

---

## Implementation Order

### Sprint 1: Foundation (1-2 weeks)
1. State encapsulation (1.1) - CRITICAL
2. Scan serialization (1.2) - CRITICAL
3. Basic tab manager module

### Sprint 2: UI & Switching (1 week)
4. Tab UI components (1.3)
5. Tab switching logic (1.4)
6. Keyboard shortcuts (1.6)

### Sprint 3: Safety & Polish (1 week)
7. Resource cleanup (1.5)
8. Tab close safety (2.1)
9. Tab tooltips (2.2)

### Sprint 4: Enhancements (1 week)
10. Tab reordering (2.4)
11. Memory degradation handling (2.3)
12. Testing and bug fixes

### Sprint 5: Nice-to-Haves (Optional)
13. Color coding (3.1)
14. Recently closed (3.2)
15. Tab persistence (3.3)
16. Other nice-to-haves as desired

---

## Testing Strategy

### Unit Tests
- [ ] Tab creation and destruction
- [ ] Scan queue operations
- [ ] History isolation between tabs
- [ ] Memory deallocation (valgrind)

### Integration Tests
- [ ] Switch tabs during scan
- [ ] Close tab during scan
- [ ] Multiple tabs with different settings
- [ ] Keyboard shortcuts work correctly

### Stress Tests
- [ ] 5 tabs with large directories (1M+ files each)
- [ ] Rapid tab switching
- [ ] Create/close tabs rapidly
- [ ] Memory leak detection over time

### Edge Cases
- [ ] Close last tab (should prevent)
- [ ] Switch to nonexistent tab index
- [ ] Scan queue with 5 queued scans
- [ ] Tab close during scan completion callback

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Missed global state → cross-tab bugs | HIGH | Systematic audit, grep for `save ::` |
| Memory leaks on tab close | HIGH | Valgrind testing, careful deallocation |
| UI sluggishness with 5 active scans | MEDIUM | Serialize scans, only 1 active |
| Complex state management bugs | MEDIUM | Defensive programming, assertions |
| Keyboard shortcuts conflict | LOW | Document shortcuts, test thoroughly |

---

## Success Criteria

**MVP (Phase 1)**:
- [ ] Can create up to 5 tabs
- [ ] Each tab has independent scan tree
- [ ] Switching tabs updates UI correctly
- [ ] Closing tabs doesn't leak memory
- [ ] Scans are serialized (no concurrent scans)
- [ ] Keyboard shortcuts work (Cmd-1 through Cmd-5)

**Full Feature (Phase 2)**:
- [ ] Tab tooltips show full path and status
- [ ] Can't close last tab
- [ ] Confirm dialog on close if scanning
- [ ] Tab reordering works

**Polished (Phase 3)**:
- [ ] Color coded tabs
- [ ] Recently closed tabs
- [ ] Tab state persists across sessions

---

## Open Questions

1. **Tab limit**: Stick with 5 or make configurable?
   - Recommendation: Hardcode 5 for MVP, make constant easy to change

2. **Scan queue size**: What if user queues 5 scans rapidly?
   - Recommendation: Queue size = MAX_TABS, show queue position in tooltip

3. **Tab close during other tab's scan**: Allow or prevent?
   - Recommendation: Allow (only affects closed tab, not active scan)

4. **Initial tab count**: Start with 1 tab or allow opening with multiple paths?
   - Recommendation: Always start with 1 tab, user creates more

5. **Tab bar overflow**: What if tabs don't fit horizontally?
   - Recommendation: With 5 max tabs @ 120px = 600px, should fit on most screens
   - If needed: Scrollable tab bar or shrink tab width

---

## File Structure

New files to create:
- `src/gui/tab_manager.f90` - Core tab state and management
- `src/gui/tab_widget.f90` - GTK tab bar UI components

Modified files:
- `src/gui/gtk_app.f90` - Remove globals, use active tab
- `src/gui/treemap_renderer.f90` - Accept tab context parameter
- `src/gui/treemap_widget.f90` - Key handler for tab shortcuts
- `src/core/progressive_scanner.f90` - Per-tab scan state
- `meson.build` - Add new source files

---

## Next Steps

1. Review this plan with user
2. Create feature branch: `git checkout -b tabs-feature`
3. Start with Phase 1.1 (State Encapsulation)
4. Commit frequently with descriptive messages
5. Test thoroughly after each sprint
