# Global State Audit for Tabs Feature

## Overview
This document identifies all global state that needs to be encapsulated into per-tab state.

---

## gtk_app.f90

### Per-Tab State (MUST MOVE)
| Variable | Line | Purpose |
|----------|------|---------|
| `global_scan_path` | 58 | Current directory being viewed |
| `nav_history(MAX_HISTORY)` | 65 | Navigation history array |
| `nav_history_count` | 66 | Number of entries in history |
| `nav_history_pos` | 67 | Current position in history |
| `navigating_history` | 68 | Flag for back/forward navigation |
| `pending_synthetic_nav` | 82 | Synthetic navigation pending flag |
| `pending_synthetic_child_name` | 83 | Child name for synthetic nav |
| `synthetic_nav_attempts` | 84 | Attempt counter |

### Global State (STAYS)
| Variable | Line | Purpose | Notes |
|----------|------|---------|-------|
| `app_ptr` | 48 | GTK application | App-level |
| `main_window_ptr` | 49 | Main window | App-level |
| `status_label_ptr` | 50 | Status bar label | Shared, updated per active tab |
| `progress_bar_ptr` | 51 | Progress bar widget | Shared, updated per active tab |
| `path_entry_ptr` | 52 | Path display entry | Shared, updated per active tab |
| `app_is_shutting_down` | 55 | Shutdown flag | Global state |
| `pending_scan_path` | 61 | Initial scan path | Only for startup |
| `back_btn_ptr` | 71 | Back button widget | Shared UI |
| `forward_btn_ptr` | 72 | Forward button widget | Shared UI |
| `cancel_scan_btn_ptr` | 73 | Cancel button widget | Shared UI |
| `info_btn_ptr` | 76 | Info button widget | Shared UI |
| `copy_path_btn_ptr` | 77 | Copy path button widget | Shared UI |
| `open_finder_btn_ptr` | 78 | Open finder button widget | Shared UI |
| `delete_btn_ptr` | 79 | Delete button widget | Shared UI |

---

## treemap_renderer.f90

### Per-Tab State (MUST MOVE)
| Variable | Line | Purpose |
|----------|------|---------|
| `current_view_node` | 57 | Pointer to current view in tree |
| `has_data` | 58 | Whether scan data exists |
| `scanned_path` | 59 | Path that was scanned |
| `layout_calculated` | 67 | Layout calculation flag |
| `last_width` | 68 | Last rendered width |
| `last_height` | 68 | Last rendered height |
| `show_file_extensions` | 71 | Toggle for file extensions |
| `use_age_based_coloring` | 72 | Toggle for age-based colors |
| `show_allocated_size` | 73 | Toggle allocated vs actual size |
| `show_hidden_files` | 74 | Toggle dotfiles visibility |
| `use_cushion_shading` | 75 | Toggle 3D vs flat rendering |
| `path_names(MAX_PATH_DEPTH)` | 80 | Path components for navigation |
| `path_depth` | 81 | Depth of current path |

### Global State (STAYS)
| Variable | Line | Purpose | Notes |
|----------|------|---------|-------|
| `dir_cache(MAX_CACHE_SIZE)` | 63 | Directory scan cache | Shared cache across tabs |
| `cache_count` | 64 | Cache entry count | Shared |
| `show_progress_cb` | 84 | Progress callback | Shared callbacks |
| `hide_progress_cb` | 85 | Hide progress callback | Shared callbacks |
| `update_progress_cb` | 86 | Update progress callback | Shared callbacks |
| `scan_completion_cb` | 87 | Completion callback | Shared callbacks |
| `widget_for_redraw` | 90 | Drawing widget pointer | Shared widget |

---

## progressive_scanner.f90

### Per-Tab State (MUST MOVE)
| Variable | Line | Purpose |
|----------|------|---------|
| `show_hidden_files` | 15 | Toggle hidden files in scan |
| `scan_state` | 43 | Complete scan state (queue, progress, root node) |
| `scan_idle_id` | 46 | GTK idle callback ID for cancellation |

### Global State (STAYS)
| Variable | Line | Purpose | Notes |
|----------|------|---------|-------|
| `update_callback` | 66 | Scan update callback | Shared callback |
| `complete_callback` | 67 | Scan completion callback | Shared callback |
| `initial_level_cb` | 68 | Initial level callback | Shared callback |

---

## Summary

### Total Variables to Move: 29

**gtk_app.f90**: 8 variables
**treemap_renderer.f90**: 13 variables
**progressive_scanner.f90**: 3 variables (including entire scan_state struct)

### Critical Observations

1. **Scan State is Complex**: The `scan_state` in progressive_scanner.f90 is a large struct containing:
   - Queue for breadth-first scanning
   - Progress tracking
   - Root node pointer
   - All scan context

   This entire structure needs to be per-tab.

2. **View Settings Are Per-Tab**: Each tab should remember its own:
   - Show/hide extensions
   - Flat vs cushioned rendering
   - Hidden files visibility
   - Color scheme

3. **Navigation History is Per-Tab**: Each tab maintains its own back/forward history.

4. **Cache Can Stay Global**: The directory scan cache can be shared across tabs for efficiency.

5. **Widget Pointers Stay Global**: All GTK widget pointers stay global, but their content is updated when switching tabs.

---

## Next Steps

1. Create `tab_state` type in `tab_manager.f90` containing all 29 variables
2. Create `tabs(MAX_TABS)` array to hold tab states
3. Add `active_tab_index` to track current tab
4. Refactor all functions to operate on tab state instead of globals
5. Create tab switching logic to swap active state
