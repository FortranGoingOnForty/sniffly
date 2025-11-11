# SpaceSniffer Feature Parity Checklist

## 🎯 Goal: Near 1:1 Clone of SpaceSniffer for Unix

### ✅ Completed (Phase 1-2)
- [x] GTK4 window with Cairo rendering
- [x] Real directory scanning
- [x] Squarified treemap layout algorithm
- [x] Basic color coding
- [x] Handles large directories (32GB tested)
- [x] Window resize/redraw

### 🚧 In Progress (Phase 3-4)
- [x] **Directory Chooser** - Command-line argument support (GUI dialog deferred)
- [x] **File Names on Rectangles** - Show names when space permits
- [x] **Toolbar** - Scan and Quit buttons
- [x] **Status Bar** - Show ready status
- [x] **Top-Level Rendering** - Show only direct children (no deep nesting)
- [ ] **Size Labels** - Display MB/GB on large rectangles

### 📋 Critical Features (Phase 5-6)
- [ ] **Click to Select** - Highlight selected rectangle
- [ ] **Double-click to Zoom** - Navigate into directories
- [ ] **Breadcrumb Bar** - Show current path, allow navigation back
- [ ] **Hover Tooltips** - Show full path and details on hover
- [ ] **Context Menu** - Right-click: Open, Delete, Properties
- [ ] **Keyboard Navigation** - Arrow keys, Enter, Backspace
- [ ] **Delete with Confirmation** - Safe deletion workflow

### 🎨 Visual Enhancements (Phase 7)
- [ ] **Cushioned Treemap** - 3D shading effect (Van Wijk algorithm)
- [ ] **Better Color Schemes** - By file type, age, or extension
- [ ] **Smart Label Placement** - Only show when readable
- [ ] **Selection Highlight** - Clear visual feedback
- [ ] **Hover Effect** - Lighten/darken on mouse over
- [ ] **Smooth Animations** - Fade in/out, zoom transitions

### 🔍 Advanced Features (Phase 8)
- [ ] **Search Bar** - Find files by name (regex)
- [ ] **Filter Panel** - By type, size, date
- [ ] **Real-time Scanning** - Animate growth as files are found
- [ ] **Pause/Resume Scan** - Control during scanning
- [ ] **Free Space Display** - Show available disk space
- [ ] **Multiple Color Modes** - Switch between schemes

### 📊 Information Display
- [ ] **Status Bar Items:**
  - Currently scanning: /path/to/dir
  - Items scanned: 1,234 / 5,678
  - Total size: 32.5 GB
  - Selected: filename.ext (1.2 MB)
  - Free space: 128 GB

### 🖱️ Mouse & Keyboard
- [ ] **Mouse:**
  - Left click: Select
  - Double-click: Zoom in
  - Right-click: Context menu
  - Hover: Show tooltip

- [ ] **Keyboard:**
  - Arrow keys: Navigate siblings
  - Enter: Zoom into selected
  - Backspace: Zoom out to parent
  - Delete: Delete selected (with confirmation)
  - Ctrl+F: Search
  - Ctrl+Q: Quit
  - /: Focus search
  - Escape: Clear selection

### 🎨 Visual Polish
- [ ] **Colors:**
  - Directories: Blue family
  - Documents: Green family
  - Images: Orange family
  - Videos: Red family
  - Audio: Purple family
  - Code: Cyan family
  - Archives: Brown family

- [ ] **Fonts:**
  - Names: System font, bold for directories
  - Sizes: Monospace for alignment
  - Min size: 10pt readable

### 🔧 Settings/Preferences
- [ ] **Configurable:**
  - Layout algorithm (Squarified vs Cushioned)
  - Color scheme
  - Animation speed
  - Font size
  - Skip directories (.git, node_modules, etc.)
  - Scan depth limit

---

## 📈 Current Progress: ~45% Complete

### What Works Now:
✅ Scanning (4GB+ tested, scans entire tree)
✅ Layout calculation (squarified treemap algorithm)
✅ Smart rendering (shows only top-level, not nested)
✅ Window resizing with proper layout recalculation
✅ Directory selection (via command-line argument)
✅ File/directory names on rectangles (when space permits)
✅ Toolbar with Scan and Quit buttons
✅ Status bar showing scan status

### Immediate Priorities (Next 3 Commits):
1. **Click-to-select** - Highlight selected rectangle
2. **Double-click navigation** - Zoom into directories
3. **Breadcrumbs** - Show current path and navigate back

### Next Week Goals:
4. Click selection
5. Zoom navigation
6. Breadcrumbs
7. Tooltips

---

## 🎯 Success Criteria

A successful SpaceSniffer clone must:
- ✅ Scan and visualize any directory
- ⏳ Show file names and sizes clearly
- ⏳ Allow navigation (click, zoom, back)
- ⏳ Provide deletion with safety
- ⏳ Look professional (toolbar, status bar)
- ⏳ Handle large directories (millions of files)
- ⏳ Be as fast or faster than SpaceSniffer

---

**We're making great progress, but we're just getting started!** 🚀
