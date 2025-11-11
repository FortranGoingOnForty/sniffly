# Sniffly Toolbar Feature Targets

## Vision
Redesign the Sniffly toolbar to match SpaceSniffer's usability while maintaining clean, intuitive design. Focus on most-used operations with clear iconography.

---

## Phase 1: Core Toolbar Redesign (PRIORITY)

### Remove
- **Quit button** - Defer to OS window close button (red X on macOS, X on Windows/Linux)

### Add/Reorganize

#### Left Section
1. **Open Directory Button** (Filing Cabinet Icon)
   - Opens OS native file picker (GtkFileChooserDialog)
   - Allows user to select directory to scan
   - Keyboard shortcut: `Cmd+O` / `Ctrl+O`

2. **Path Display** (Read-only text entry or label)
   - Shows current scan root path
   - Click filing cabinet icon next to it to trigger Open Directory
   - Should support text selection for copy/paste

3. **Scan Button** (Magnifying Glass Icon)
   - Positioned immediately after path display
   - Triggers rescan of current directory
   - Keyboard shortcut: `F5` or `Cmd+R`

4. **Progress Bar**
   - Keep current implementation
   - Expands to fill remaining space
   - Shows scan progress with percentage

#### Right Section (floated right)
5. **Open in Finder/Explorer Button** (File with Arrow Icon)
   - Opens currently selected item in OS file browser
   - macOS: `open -R <path>` (reveals in Finder)
   - Linux: `xdg-open <path>` or `nautilus <path>`
   - Windows: `explorer /select,<path>`
   - Disabled when no selection
   - Keyboard shortcut: `Cmd+Shift+R` / `Ctrl+Shift+R`

6. **Delete Button** (Red Trash/X Icon)
   - Deletes currently selected item
   - Priority: System trash → `rm` command as fallback
   - Shows confirmation dialog
   - Disabled when no selection
   - Keyboard shortcut: `d` or `Delete`
   - Right-click context menu also triggers this

---

## Phase 2: Enhanced File Operations

### Additional Toolbar Buttons
7. **Copy Path Button** (Clipboard Icon)
   - Copies full path of selected item to clipboard
   - Keyboard shortcut: `Cmd+Shift+C` / `Ctrl+Shift+C`

8. **Properties/Details Button** (Info Icon)
   - Opens side panel or dialog with file/folder details:
     - Full path
     - Size (human-readable + bytes)
     - Item count (for directories)
     - Created/modified dates
     - Permissions
     - File type
   - Keyboard shortcut: `i` or `Cmd+I`

9. **Refresh Button** (Circular Arrow Icon)
   - Forces rescan without cache
   - Clears directory cache before scanning
   - Keyboard shortcut: `Cmd+Shift+R` / `Ctrl+Shift+R`

---

## Phase 3: Search & Filter Features

### Filter Toolbar (Second Row, Collapsible)
10. **Search/Filter Entry**
    - Filter by filename pattern (wildcards: `*.txt`, `*cache*`)
    - Live filtering as you type
    - Keyboard shortcut: `Cmd+F` / `Ctrl+F` to focus

11. **File Type Filter Dropdown**
    - Quick filters: All, Documents, Images, Videos, Audio, Archives, Code
    - Based on file extensions
    - Multiple selection support

12. **Size Filter Range**
    - Min/max size sliders or entry fields
    - Quick presets: "Large files (>100MB)", "Tiny files (<1MB)"

13. **Date Filter**
    - Filter by modified date: Last day, week, month, year, custom range
    - "Old files" (not modified in 1+ years) preset

14. **Show Hidden Files Toggle**
    - Toggle visibility of hidden files/folders (starting with `.`)
    - Keyboard shortcut: `Cmd+Shift+H`

---

## Phase 4: Navigation & History

15. **Back/Forward Buttons** (Arrow Icons)
    - Navigate through directory history
    - Like a web browser
    - Keyboard shortcuts: `Cmd+[` / `Cmd+]` or `Alt+Left` / `Alt+Right`

16. **Up to Parent Button** (Up Arrow Icon)
    - Navigate to parent directory
    - Alternative to Backspace key
    - Shows parent path in tooltip

17. **Breadcrumb Navigation** (Already implemented!)
    - Enhance: Make each path segment clickable
    - Click any segment to jump to that level

---

## Phase 5: Advanced Features (SpaceSniffer Parity)

### View Options
18. **Toggle File Extensions**
    - Show/hide file extensions in labels
    - Keyboard shortcut: `e`

19. **Age-based Coloring**
    - Color files by modification date:
      - Blue = Recent (< 1 month)
      - Yellow = Medium (1-12 months)
      - Red = Old (> 1 year)
    - Toggle on/off

20. **Size Display Mode**
    - Toggle between actual size vs. allocated size (disk usage)
    - Useful for showing real disk space usage

### Export & Reporting
21. **Export to CSV/JSON**
    - Export directory tree with sizes
    - Useful for archiving or analysis

22. **Copy File List**
    - Copy list of all files matching current filter
    - Plain text format, one path per line

### Multi-Selection
23. **Multiple Selection Support**
    - `Cmd+Click` / `Ctrl+Click` to select multiple items
    - `Shift+Click` to select range
    - Show total size of selection in status bar
    - Bulk delete support

24. **Select All Matching Pattern**
    - Select all items matching a wildcard pattern
    - Example: "Select all *.log files"

### Comparison Mode
25. **Compare Two Scans**
    - Scan directory, then scan again later
    - Highlight differences (new, deleted, grown, shrunk files)
    - Useful for tracking disk usage changes over time

---

## Implementation Notes

### Icon Sources
- Use GTK stock icons where possible (`gtk_image_new_from_icon_name`)
- Common icon names:
  - `folder-open` - Open directory
  - `view-refresh` - Rescan/refresh
  - `edit-find` - Search
  - `edit-delete` - Delete
  - `edit-copy` - Copy path
  - `document-properties` - Properties/info
  - `go-up` - Navigate up
  - `go-previous` / `go-next` - Back/forward
  - `document-open` - Open in Finder

### GTK Components Needed
- `GtkFileChooserDialog` - For directory picker
- `GtkPopover` or `GtkDialog` - For properties panel
- `GtkEntry` - For search/filter input
- `GtkComboBox` - For filter dropdowns
- `GtkSwitch` - For toggles (hidden files, etc.)
- `GtkClipboard` - For copy path functionality

### Platform-Specific Code
- **Open in Finder/Explorer**: Use system commands via `iso_c_binding`
- **Delete to Trash**:
  - macOS: `osascript -e 'tell app "Finder" to delete POSIX file "..."'`
  - Linux: `gio trash <path>` or `trash-put <path>`
  - Fallback: `rm -rf` with confirmation
- **Copy to Clipboard**: Use GTK clipboard API

### Keyboard Shortcuts Summary
| Shortcut | Action |
|----------|--------|
| `Cmd+O` / `Ctrl+O` | Open directory picker |
| `F5` / `Cmd+R` | Rescan current directory |
| `Cmd+Shift+R` | Open in Finder/Explorer |
| `d` / `Delete` | Delete selected item |
| `Cmd+Shift+C` | Copy path to clipboard |
| `i` / `Cmd+I` | Show properties |
| `Cmd+F` | Focus search/filter |
| `Cmd+Shift+H` | Toggle hidden files |
| `Cmd+[` / `Cmd+]` | Back/forward in history |
| `Backspace` | Navigate to parent |
| `q` | Quit (already implemented) |
| `Space` | Select item (already implemented) |
| `Enter` | Navigate into item (already implemented) |
| `Arrow keys` | Navigate treemap (already implemented) |

---

## Current Status (Updated 2025-11-05)
- ✅ Basic toolbar with Scan button
- ✅ Progress bar (moved to toolbar)
- ✅ Breadcrumb display (path only, not clickable yet)
- ✅ Keyboard navigation (arrows, enter, backspace, space)
- ✅ Mouse hover and selection
- ✅ Directory caching for fast re-scans
- ✅ **Phase 1 Complete**: Open Directory, Path Display, Scan, Open in Finder, Copy Path, Delete buttons
- ✅ **Tooltips**: Hover shows filename, size, item count
- ✅ **Status Bar Stats**: Shows "N items (M files) - X.XX GB"
- ✅ **Color by File Type**: Images, videos, audio, documents, code, archives colored
- ✅ **Size Labels**: Shows formatted sizes on rectangles (when space permits)
- ✅ **Copy Path to Clipboard**: Toolbar button + Cmd+Shift+C shortcut
- ✅ **Cushioned Treemap**: Van Wijk algorithm for 3D shading effect

## Next Steps
1. ✅ ~~Implement Phase 1 core toolbar redesign~~ **DONE**
2. ✅ ~~Add GtkFileChooserDialog for directory picker~~ **DONE**
3. ✅ ~~Implement "Open in Finder" functionality~~ **DONE**
4. ✅ ~~Add delete functionality with system trash support~~ **DONE**
5. Enhance breadcrumb bar to be clickable (navigate to parent levels)
6. Add keyboard shortcut handler for Copy Path (Cmd+Shift+C)
7. Implement context menu (right-click)
8. Add Properties/Info dialog
9. Implement Back/Forward navigation history

---

## Design Decisions (CONFIRMED)
- ✅ **Drag-and-drop**: YES - Drag directory onto app window to initiate scan
- ✅ **Filter toolbar**: Always visible (we have plenty of header space)
- ✅ **Context menu**: YES - Right-click context menu on selections
- ✅ **Undo for delete**: YES - Implement Cmd/Ctrl+Z undo for delete operations
- ✅ **Settings dialog**: Defer to later phases

## Priority: ALL FEATURES - Full SpaceSniffer parity!
