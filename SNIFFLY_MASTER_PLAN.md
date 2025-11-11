# SNIFFLY - Pure Fortran GUI Disk Analyzer
## The SpaceSniffer Clone That Proves Fortran Can Do Anything

---

## 🎯 Project Vision

Build a near 1:1 clone of SpaceSniffer using **pure Fortran** with GTK4, proving that Fortran can create modern, performant GUI applications that rival commercial Windows software. Target macOS and Linux with package manager distribution.

---

## 📋 Executive Summary

**What:** Native GUI disk analyzer with real-time treemap visualization
**Why:** Prove Fortran's capabilities while providing Unix users with a SpaceSniffer alternative
**How:** gtk-fortran + GTK4 + Cairo for rendering, leveraging sniffert's proven algorithms
**When:** 12-week development cycle with 4 major milestones
**Success:** Native performance, handles 1M+ files, packaged for Homebrew/apt/pacman

---

## 🏗️ Technology Stack

### Core Technologies

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| **Language** | Fortran 2008+ (gfortran 9.0+) | Pure Fortran philosophy, proven performance |
| **GUI Framework** | GTK4 via gtk-fortran | Modern, cross-platform, well-maintained |
| **Graphics** | Cairo 1.18+ | Hardware-accelerated 2D drawing |
| **Build System** | Meson + FPM fallback | GTK standard, Fortran-friendly |
| **Dependencies** | GLib 2.80+, GDK4, Pango | GTK ecosystem |

### Why gtk-fortran?

1. **Full GTK4 Support**: Latest gtk-fortran (3.24.41) includes GTK4 bindings
2. **Cairo Integration**: Direct access to Cairo drawing API for custom rendering
3. **Cross-Platform**: Linux, macOS, FreeBSD native support
4. **Active Development**: Maintained by Vincent Magnin, regular updates
5. **Fortran-Native**: High-level interface using Fortran optional arguments
6. **Production-Ready**: Used in scientific visualization applications

---

## 🎨 SpaceSniffer Feature Analysis

### Core Features (Must-Have)

1. **Real-time Treemap Visualization**
   - Animated growth as scanning progresses
   - Nested rectangles proportional to file sizes
   - Smooth transitions on layout changes

2. **Interactive Navigation**
   - Click to zoom into directories
   - Breadcrumb navigation bar
   - Right-click context menus
   - Keyboard shortcuts (same as sniffert)

3. **Visual Enhancements**
   - Cushioned treemap effect (3D shading)
   - Color coding by file type/age
   - Smart label placement (only when space permits)
   - Hover tooltips with full path and details

4. **Scanning Features**
   - Background scanning with progress indicator
   - Pause/resume scanning
   - Skip inaccessible directories gracefully
   - Show free space and unknown space

5. **File Management**
   - Open files/directories in default app
   - Delete with confirmation dialog
   - Show in file manager
   - Copy path to clipboard

6. **Search and Filter**
   - Text search by filename
   - Filter by file type (regex patterns)
   - Filter by size range
   - Filter by date range

7. **Configuration**
   - Layout algorithm selection (Squarified/Cushioned)
   - Color scheme customization
   - Animation speed control
   - Font size adjustment

### Optional Features (Nice-to-Have)

- Export treemap as PNG/SVG
- Compare two directory snapshots
- Bookmarks for frequent directories
- Hidden files toggle
- Multiple tabs for different scans

---

## 📐 Architecture Design

### Module Structure

```
sniffly/
├── meson.build                 # Primary build system
├── fpm.toml                    # Fallback build system
├── app/
│   └── main.f90                # GTK application entry point
├── src/
│   ├── core/                   # Reusable from sniffert
│   │   ├── types.f90           # Core data types (file_node, rect)
│   │   ├── file_system.f90     # POSIX filesystem operations
│   │   ├── disk_scanner.f90    # Background scanning with callbacks
│   │   └── utils.f90           # String formatting, size conversion
│   │
│   ├── layout/                 # Treemap algorithms
│   │   ├── squarified.f90      # Port from sniffert (enhanced)
│   │   ├── cushioned.f90       # Cushion treemap with shading
│   │   └── layout_manager.f90  # Algorithm selection/switching
│   │
│   ├── gui/                    # GTK4 interface
│   │   ├── gtk_app.f90         # GtkApplication setup
│   │   ├── main_window.f90     # Main application window
│   │   ├── treemap_widget.f90  # Custom GtkDrawingArea widget
│   │   ├── toolbar.f90         # Top toolbar with controls
│   │   ├── statusbar.f90       # Bottom status bar
│   │   ├── dialogs.f90         # Confirmation, settings dialogs
│   │   └── menus.f90           # Context menus, menu bar
│   │
│   ├── rendering/              # Cairo drawing
│   │   ├── cairo_renderer.f90  # Core rendering engine
│   │   ├── colors.f90          # Color schemes and gradients
│   │   ├── text_layout.f90     # Pango text rendering
│   │   └── effects.f90         # Cushion shading, animations
│   │
│   └── state/                  # Application state
│       ├── app_state.f90       # Global state management
│       ├── selection.f90       # Selection and navigation
│       ├── config.f90          # User settings persistence
│       └── scan_manager.f90    # Background scan coordination
│
└── test/
    ├── test_layouts.f90        # Layout algorithm tests
    ├── test_rendering.f90      # Rendering tests
    └── test_gui.f90            # GUI interaction tests
```

### Data Flow Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    GTK4 Main Loop                       │
│                  (Event Processing)                     │
└─────────────────────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────┐
│                   Main Window (GTK)                     │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Toolbar: Scan Path | Layout | Color | Search  │   │
│  └─────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────┐   │
│  │         Treemap Widget (GtkDrawingArea)        │   │
│  │                                                 │   │
│  │  ┌────────────────────────────────────────┐    │   │
│  │  │   Cairo Drawing Surface               │    │   │
│  │  │   (Custom rendering via ::draw signal) │    │   │
│  │  └────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Statusbar: Scanning... | Selected: /foo/bar   │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────┐
│              Application State Manager                  │
│  • Current directory tree (file_node)                   │
│  • Layout cache (cached bounds)                         │
│  • Selection state (current node, breadcrumb)           │
│  • Scan progress (% complete, items scanned)            │
└─────────────────────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        ↓                  ↓                  ↓
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│Disk Scanner  │  │Layout Engine │  │Cairo Renderer│
│(Background   │  │(Squarified/  │  │(Drawing API) │
│ Thread)      │  │ Cushioned)   │  │              │
└──────────────┘  └──────────────┘  └──────────────┘
```

### Threading Model

1. **Main Thread (GTK Event Loop)**
   - Handle all GUI events
   - Process user input
   - Trigger redraws (gtk_widget_queue_draw)

2. **Scanning Thread (GLib Thread)**
   - Background directory traversal
   - Periodic callbacks to main thread with updates
   - Use g_idle_add for thread-safe UI updates

3. **Layout Calculation**
   - Triggered by scan updates or window resize
   - Can be deferred if user is interacting
   - Cache results to avoid recalculation

---

## 🎨 Treemap Algorithms

### 1. Squarified Treemap (Already Implemented!)

**Status:** Port from sniffert with minor enhancements
**Algorithm:** Bruls et al. 2000
**Advantages:**
- Excellent aspect ratios (more square rectangles)
- Easy to compare sizes at a glance
- Already proven in sniffert

**Implementation Notes:**
- Reuse existing squarified.f90 from sniffert
- Enhance with real-time updates (incremental layout)
- Add smooth animation between layout changes

### 2. Cushioned Treemap (New Implementation)

**Status:** New development
**Algorithm:** Van Wijk & Van de Wetering 1999
**Visual Effect:** Adds 3D shading to rectangles using bump mapping

**How Cushion Shading Works:**

1. **Recursive Surface Function**
   ```
   For each rectangle at depth d:
   - Base surface: f(x, y) = 0
   - Add height function: h(x, y) = ax² + by²
   - Parameters a, b decrease with depth
   ```

2. **Lighting Model**
   ```
   - Light source direction: L = (lx, ly, lz)
   - Surface normal: N = (-∂f/∂x, -∂f/∂y, 1)
   - Color intensity: I = ambient + diffuse * (N · L)
   ```

3. **Implementation Steps**
   - Calculate cushion parameters for each node
   - Store in enhanced file_node structure
   - Apply during Cairo rendering pass

**Rendering in Cairo:**
```fortran
! For each cushioned rectangle:
! 1. Create linear gradient based on cushion function
! 2. Apply gradient as fill pattern
! 3. Add border for clarity
cairo_pattern_create_linear(x1, y1, x2, y2)
cairo_pattern_add_color_stop_rgba(pattern, 0.0, r1, g1, b1, 1.0)
cairo_pattern_add_color_stop_rgba(pattern, 1.0, r2, g2, b2, 1.0)
cairo_set_source(cr, pattern)
cairo_rectangle(cr, x, y, w, h)
cairo_fill(cr)
```

---

## 🎯 Implementation Phases

### Phase 1: Foundation & GTK Setup (Weeks 1-2)

**Goal:** Get GTK4 + gtk-fortran working with basic window

#### Tasks:
1. **Environment Setup**
   - Install GTK4 development libraries (macOS: Homebrew, Linux: package manager)
   - Install gtk-fortran from source or package
   - Create Meson build configuration
   - Test minimal GTK app (Hello World window)

2. **Project Structure**
   - Create module skeleton
   - Set up git repository structure
   - Configure build system (Meson + FPM fallback)
   - Create basic CI/CD workflow

3. **Basic GTK Application**
   - Implement GtkApplication setup
   - Create main window with title bar
   - Add basic menu bar (File → Scan, Quit)
   - Test on both macOS and Linux

4. **GtkDrawingArea Integration**
   - Create custom treemap widget
   - Implement ::draw signal handler
   - Test basic Cairo drawing (draw rectangle, text)
   - Verify rendering performance (target 60fps)

**Success Criteria:**
- Window opens with custom drawing area
- Can draw colored rectangles and text
- Builds on macOS and Linux
- No memory leaks (valgrind clean)

**Estimated Time:** 2 weeks

---

### Phase 2: Core Data & Scanning (Weeks 3-4)

**Goal:** Port sniffert's scanning logic with GTK integration

#### Tasks:
1. **Port Core Modules**
   - Adapt types.f90 for GUI needs
   - Port file_system.f90 unchanged
   - Port disk_scanner.f90 with callback support
   - Add thread-safe state management

2. **Background Scanning**
   - Implement GLib threading wrapper
   - Create scan_manager for coordinating scans
   - Add progress callbacks to main thread
   - Test with various directory sizes

3. **Progress UI**
   - Add progress bar to main window
   - Show scan statistics (files scanned, total size)
   - Implement pause/resume/cancel controls
   - Add estimated time remaining

4. **State Management**
   - Implement app_state module
   - Track current directory tree
   - Handle scan updates without blocking UI
   - Add basic error handling

**Success Criteria:**
- Can scan /tmp without blocking GUI
- Progress bar updates in real-time
- Can cancel mid-scan cleanly
- No crashes on permission denied

**Estimated Time:** 2 weeks

---

### Phase 3: Layout Algorithms (Weeks 5-6)

**Goal:** Implement both squarified and cushioned layouts

#### Tasks:
1. **Port Squarified Algorithm**
   - Copy squarified.f90 from sniffert
   - Adapt for real-time updates (incremental)
   - Optimize for large datasets (1M+ nodes)
   - Add unit tests comparing to sniffert output

2. **Implement Cushioned Algorithm**
   - Research cushion function parameters
   - Implement recursive cushion calculation
   - Store cushion data in file_node
   - Add toggle between layouts

3. **Layout Manager**
   - Abstract layout selection
   - Cache layout results
   - Invalidate cache on window resize
   - Implement smart recalculation (only changed subtrees)

4. **Performance Optimization**
   - Profile layout calculation time
   - Target < 100ms for 10k nodes
   - Use lazy evaluation for deep trees
   - Consider viewport culling for large trees

**Success Criteria:**
- Both layouts produce visually correct treemaps
- Can switch between layouts in < 1 second
- Handles 100k files without lag
- Layout respects window size constraints

**Estimated Time:** 2 weeks

---

### Phase 4: Cairo Rendering (Weeks 7-8)

**Goal:** Beautiful, performant rendering with cushion effects

#### Tasks:
1. **Basic Treemap Rendering**
   - Implement cairo_renderer module
   - Draw rectangles with borders
   - Render text labels (using Pango)
   - Handle clipping for nested rectangles

2. **Cushion Shading**
   - Implement lighting calculations
   - Create Cairo gradients for cushions
   - Add depth-based color variation
   - Test different light angles

3. **Color Schemes**
   - Implement file type coloring (directories, files, media, code, etc.)
   - Add color by age (old files, recent files)
   - Create multiple color schemes (Light, Dark, High Contrast)
   - Allow user customization

4. **Text Rendering**
   - Use Pango for text layout
   - Smart label placement (only show when space permits)
   - Ellipsize long filenames
   - Show size labels with proper formatting (KB, MB, GB)

5. **Performance**
   - Implement viewport culling (only draw visible rectangles)
   - Batch Cairo operations
   - Profile draw time (target < 16ms / 60fps)
   - Add FPS counter for debugging

**Success Criteria:**
- Treemap looks beautiful with cushion effect
- Smooth scrolling and zooming
- Text is readable at all zoom levels
- Maintains 60fps on 10k visible nodes

**Estimated Time:** 2 weeks

---

### Phase 5: Interactivity (Weeks 9-10)

**Goal:** Full SpaceSniffer-style navigation and interaction

#### Tasks:
1. **Mouse Interaction**
   - Implement hit testing (which rectangle was clicked?)
   - Single-click: select and highlight
   - Double-click: zoom into directory
   - Right-click: show context menu
   - Hover: show tooltip with details

2. **Keyboard Navigation**
   - Arrow keys: navigate siblings
   - Enter: zoom into selected
   - Backspace: zoom out to parent
   - Delete: delete with confirmation (from sniffert)
   - /: focus search box
   - Escape: cancel/clear selection

3. **Navigation UI**
   - Breadcrumb bar at top
   - Back/Forward buttons
   - "Go up" button
   - Animation on zoom transitions

4. **Context Menus**
   - Open in file manager
   - Open file with default app
   - Copy path to clipboard
   - Delete with confirmation
   - Properties dialog (size, modified date, permissions)

5. **Selection State**
   - Highlight selected rectangle
   - Show details in status bar
   - Persist selection across layout changes
   - Visual feedback on hover

**Success Criteria:**
- Navigation feels smooth and intuitive
- All keyboard shortcuts work
- Context menu matches macOS/Linux conventions
- No lag on interaction

**Estimated Time:** 2 weeks

---

### Phase 6: Search & Filter (Week 11)

**Goal:** Find files quickly in large trees

#### Tasks:
1. **Search UI**
   - Add search entry in toolbar
   - Show search results in tree view or list
   - Highlight matching rectangles in treemap
   - Clear search with Escape

2. **Search Implementation**
   - Full-text filename search
   - Regex pattern support
   - Case-insensitive option
   - Search scope (current directory vs entire tree)

3. **Filtering**
   - Filter by file type (extensions)
   - Filter by size range (e.g., files > 100MB)
   - Filter by date range (modified in last 7 days)
   - Combine multiple filters

4. **Filter UI**
   - Filter panel in sidebar (toggleable)
   - Quick filters in toolbar (e.g., "Large files")
   - Visual indication when filters active
   - Reset filters button

**Success Criteria:**
- Can find specific files in < 1 second
- Filters work on 100k+ files
- Search results update in real-time
- Filter state persists across zooms

**Estimated Time:** 1 week

---

### Phase 7: Polish & Configuration (Week 12)

**Goal:** Production-ready with user customization

#### Tasks:
1. **Settings Dialog**
   - General: animation speed, default layout
   - Colors: scheme selection, custom colors
   - Scanning: skip patterns, depth limit
   - Save settings to config file (~/.config/sniffly/config.ini)

2. **Toolbar**
   - Add all main actions
   - Icon design (consistent with GTK)
   - Tooltips for all buttons
   - Responsive layout (collapse on small windows)

3. **Status Bar**
   - Show scan progress
   - Show selected item details
   - Show totals (files, directories, size)
   - Show free space on drive

4. **Error Handling**
   - Graceful handling of permission denied
   - User-friendly error messages
   - Logging for debugging
   - Crash recovery (save scan state)

5. **Animations**
   - Smooth zoom transitions
   - Layout change animations
   - Progress indicator animations
   - Fade in/out for tooltips

6. **Accessibility**
   - Keyboard-only navigation support
   - High-contrast mode
   - Screen reader compatibility (GTK accessibility API)
   - Configurable font sizes

7. **Documentation**
   - User manual (markdown)
   - Keyboard shortcuts reference
   - Build instructions
   - Developer documentation

**Success Criteria:**
- App feels polished and professional
- All settings persist correctly
- No crashes under normal usage
- Passes accessibility audit

**Estimated Time:** 1 week

---

### Phase 8: Testing & Packaging (Weeks 13-14)

**Goal:** Release-ready packages for macOS and Linux

#### Tasks:
1. **Testing**
   - Unit tests for all modules
   - Integration tests for GUI workflows
   - Performance tests (1M files benchmark)
   - Memory leak testing (valgrind)
   - Test on multiple distributions

2. **Packaging - macOS**
   - Create .app bundle
   - Sign with Apple Developer ID
   - Create DMG installer
   - Homebrew formula (homebrew-core PR)
   - Test on macOS 12+ (Monterey, Ventura, Sonoma)

3. **Packaging - Linux**
   - Debian package (.deb) for Ubuntu/Debian
   - RPM package (.rpm) for Fedora/RHEL
   - AUR package for Arch
   - Flatpak for universal Linux
   - AppImage for portability

4. **Distribution**
   - Set up GitHub releases
   - Create release notes
   - Build CI/CD pipeline (GitHub Actions)
   - Automated builds for each platform

5. **Documentation**
   - README with screenshots
   - INSTALL guide for each platform
   - CONTRIBUTING guide
   - LICENSE (choose appropriate)

6. **Marketing**
   - Demo video showing features
   - Comparison with SpaceSniffer
   - Blog post: "Fortran Can Do GUIs!"
   - Submit to package managers

**Success Criteria:**
- Packages install cleanly on target platforms
- No runtime dependencies missing
- Passes package manager guidelines
- Downloads available from GitHub releases

**Estimated Time:** 2 weeks

---

## 🔧 Technical Challenges & Solutions

### Challenge 1: gtk-fortran Learning Curve

**Problem:** gtk-fortran is less documented than GTK's C API
**Solution:**
- Study gtk-fortran examples repo
- Reference GTK C documentation and translate
- Join gtk-fortran mailing list for support
- Contribute documentation back to project

### Challenge 2: Real-time Layout Updates

**Problem:** Layout recalculation can be slow for large trees
**Solution:**
- Incremental layout updates (only changed subtrees)
- Cache layout results aggressively
- Use dirty flagging to track what needs recalc
- Defer layout during rapid resizing (debounce)

### Challenge 3: Memory Management

**Problem:** Large directory trees consume significant memory
**Solution:**
- Use move_alloc to avoid deep copies (already in sniffert)
- Lazy loading for deep trees (only load visible levels)
- Configurable depth limit
- Manual deallocation of pruned subtrees

### Challenge 4: Thread Safety with GTK

**Problem:** GTK is not thread-safe; can't update UI from background thread
**Solution:**
- Use g_idle_add to queue UI updates from scan thread
- Wrap in gtk-fortran interface (c_funloc for callbacks)
- Keep shared state minimal and use mutex where needed
- Test thoroughly with ThreadSanitizer

### Challenge 5: Cushion Shading Performance

**Problem:** Gradient calculation for each rectangle can be slow
**Solution:**
- Pre-calculate cushion parameters during layout
- Use Cairo pattern caching
- Simplify lighting model (2-stop gradients)
- Profile and optimize hot paths

### Challenge 6: Cross-Platform Differences

**Problem:** macOS and Linux have different GTK behaviors
**Solution:**
- Test on both platforms regularly (CI/CD)
- Use GTK4's native backends (Cocoa on macOS)
- Avoid platform-specific code where possible
- Document known differences in README

---

## 📊 Performance Targets

### Scanning Performance

| Metric | Target | Stretch Goal |
|--------|--------|--------------|
| Files per second | 10,000 | 50,000 |
| Memory per file | < 500 bytes | < 300 bytes |
| Initial scan (100k files) | < 10 seconds | < 5 seconds |
| Background scan overhead | < 5% CPU | < 2% CPU |

### Rendering Performance

| Metric | Target | Stretch Goal |
|--------|--------|--------------|
| Frame rate (1k visible nodes) | 60 fps | 120 fps |
| Frame rate (10k visible nodes) | 30 fps | 60 fps |
| Layout calculation (10k nodes) | < 100ms | < 50ms |
| Zoom animation duration | 300ms | 200ms |

### Memory Usage

| Metric | Target | Stretch Goal |
|--------|--------|--------------|
| Base application memory | < 50 MB | < 30 MB |
| Per-file overhead | < 500 bytes | < 300 bytes |
| Layout cache overhead | < 2x file data | < 1.5x file data |
| Total for 1M files | < 1 GB | < 500 MB |

---

## 🎨 Visual Design

### Color Schemes

**Light Theme** (default on macOS)
- Background: #FFFFFF
- Directories: Shades of blue (#E3F2FD → #1976D2)
- Files: Shades of green (#E8F5E9 → #388E3C)
- Selected: Orange highlight (#FF6F00)

**Dark Theme** (default on Linux)
- Background: #1E1E1E
- Directories: Shades of purple (#4A148C → #BA68C8)
- Files: Shades of teal (#004D40 → #26A69A)
- Selected: Yellow highlight (#FDD835)

**High Contrast Theme**
- Strong borders on all rectangles
- High saturation colors
- Larger fonts
- No subtle gradients

### File Type Colors

| Type | Extension Examples | Color |
|------|-------------------|-------|
| Directories | (N/A) | Blue family |
| Documents | .pdf, .doc, .txt | Green family |
| Images | .jpg, .png, .gif | Orange family |
| Videos | .mp4, .mkv, .avi | Red family |
| Audio | .mp3, .flac, .wav | Purple family |
| Code | .c, .py, .js, .f90 | Cyan family |
| Archives | .zip, .tar, .gz | Brown family |
| Executables | .exe, .app, .bin | Gray family |

### Typography

- **Main Labels:** System font (San Francisco on macOS, Ubuntu on Linux)
- **Size Labels:** Monospace font for alignment
- **Minimum Readable Size:** 10pt
- **Label Visibility:** Only show when rectangle width > 60px and height > 20px

---

## 🚀 Distribution Strategy

### Package Managers

**macOS:**
1. **Homebrew** (primary)
   ```bash
   brew install sniffly
   ```
   - Submit formula to homebrew-core
   - Automatic updates
   - High visibility

2. **MacPorts** (secondary)
   ```bash
   sudo port install sniffly
   ```

**Linux:**
1. **Debian/Ubuntu** (APT)
   ```bash
   sudo apt install sniffly
   ```
   - Upload to Debian repositories
   - Backport to older releases

2. **Arch** (AUR)
   ```bash
   yay -S sniffly
   ```
   - Maintain PKGBUILD in AUR
   - Community-maintained

3. **Fedora/RHEL** (DNF)
   ```bash
   sudo dnf install sniffly
   ```
   - Submit to Fedora repositories

4. **Universal** (Flatpak)
   ```bash
   flatpak install sniffly
   ```
   - Works on all distributions
   - Sandboxed environment

### GitHub Releases

- Provide pre-built binaries for:
  - macOS (arm64, x86_64)
  - Linux (x86_64, arm64)
- Include source tarballs
- Automated release via GitHub Actions
- Semantic versioning (v1.0.0, v1.1.0, etc.)

---

## 📚 Dependencies

### Build Dependencies

| Dependency | Version | Package Name (Homebrew) | Package Name (APT) |
|------------|---------|-------------------------|-------------------|
| gfortran | 9.0+ | gcc | gfortran |
| GTK4 | 4.0+ | gtk4 | libgtk-4-dev |
| gtk-fortran | 3.24.41+ | (build from source) | (build from source) |
| GLib | 2.80+ | glib | libglib2.0-dev |
| Cairo | 1.18+ | cairo | libcairo2-dev |
| Pango | 1.50+ | pango | libpango1.0-dev |
| Meson | 0.60+ | meson | meson |
| Ninja | 1.10+ | ninja | ninja-build |

### Runtime Dependencies

| Dependency | Version | Included In |
|------------|---------|-------------|
| GTK4 runtime | 4.0+ | Package |
| GLib runtime | 2.80+ | Package |
| Cairo runtime | 1.18+ | Package |

---

## 🧪 Testing Strategy

### Unit Tests

**Location:** `test/` directory
**Framework:** FUnit or simple assertion framework
**Coverage:** > 80% of non-GUI code

**Test Categories:**
1. Layout algorithms (verify aspect ratios, area conservation)
2. File scanning (mock filesystem)
3. State management (selection, navigation)
4. Color calculations (verify gradients)
5. String formatting (size display)

### Integration Tests

**Framework:** Python + GTK inspector + screenshot comparison

**Test Scenarios:**
1. Launch app and scan /tmp
2. Navigate into directory via click
3. Zoom out via breadcrumb
4. Switch layout algorithm
5. Apply filters
6. Delete file with confirmation
7. Search for file
8. Change color scheme

### Performance Tests

**Benchmarks:**
1. Scan 1M files (measure time, memory)
2. Layout calculation (measure time for various node counts)
3. Rendering (measure FPS for various node counts)
4. Memory growth over time (detect leaks)

**Tools:**
- gprof for profiling
- valgrind for memory leaks
- perf for Linux profiling
- Instruments for macOS profiling

### Manual Testing

**Checklist:**
- [ ] Install on clean macOS system
- [ ] Install on clean Ubuntu system
- [ ] Install on clean Arch system
- [ ] Scan various directories (/usr, /home, /Applications)
- [ ] Resize window aggressively
- [ ] Navigate deep directory trees
- [ ] Delete files and verify
- [ ] Close and reopen (verify settings persist)
- [ ] Run for 1 hour (verify stability)

---

## 🔒 Security Considerations

### File System Access

- **Principle:** Only access what user explicitly scans
- **Implementation:**
  - No background scanning without user action
  - Respect system permissions
  - Skip symlinks to avoid cycles
  - Warn on permission denied

### Deletion Safety

- **Principle:** Make it hard to delete by accident
- **Implementation:**
  - Always show confirmation dialog
  - Show full path and size
  - For large deletions (>1GB), require typing name
  - No "remember my choice" option
  - Log deletions for audit trail

### Sandboxing

- **Flatpak:** Request filesystem access permission
- **macOS:** Request Full Disk Access if needed
- **General:** Run with user privileges (never root)

---

## 📈 Success Metrics

### Development Success

- [ ] All phases completed on schedule
- [ ] No P0 bugs at launch
- [ ] Performance targets met
- [ ] Passes all tests on both platforms

### Adoption Success

- [ ] 1,000 stars on GitHub in first 3 months
- [ ] 10,000 downloads in first 6 months
- [ ] Accepted into Homebrew and apt repositories
- [ ] Featured on Hacker News or /r/programming

### Community Success

- [ ] 5+ external contributors
- [ ] 10+ issues/PRs from community
- [ ] Mentioned in "Fortran can do that?" articles
- [ ] Used as gtk-fortran showcase example

---

## 🎓 Learning Resources

### gtk-fortran

- Official Wiki: https://github.com/vmagnin/gtk-fortran/wiki
- Examples: https://github.com/vmagnin/gtk-fortran/tree/master/examples
- Mailing List: gtk-fortran-devel@lists.sourceforge.net

### GTK4

- API Reference: https://docs.gtk.org/gtk4/
- Tutorial: https://www.gtk.org/docs/getting-started/
- Migration Guide (GTK3→4): https://docs.gtk.org/gtk4/migrating-3to4.html

### Cairo

- API Reference: https://www.cairographics.org/manual/
- Tutorial: https://www.cairographics.org/tutorial/
- Samples: https://www.cairographics.org/samples/

### Treemap Algorithms

- Squarified Treemaps: https://www.win.tue.nl/~vanwijk/stm.pdf
- Cushion Treemaps: https://www.win.tue.nl/~vanwijk/ctm.pdf
- Treemap History: http://www.cs.umd.edu/hcil/treemap-history/

---

## 🗺️ Roadmap

### Version 1.0 (12 weeks)

Core features:
- Real-time scanning with progress
- Squarified and cushioned layouts
- Interactive navigation (click, zoom, breadcrumb)
- Search and filter
- Delete with confirmation
- Settings persistence
- Package for macOS and Linux

### Version 1.1 (Post-launch +1 month)

Polish and community feedback:
- Bug fixes from user reports
- Performance improvements
- Additional color schemes
- Export treemap as image
- Localization support (i18n)

### Version 1.2 (Post-launch +3 months)

Advanced features:
- Compare two directory snapshots
- Show file age heatmap
- Bookmarks for frequent directories
- Multiple tabs
- Plugins/extensions system

### Version 2.0 (Post-launch +6 months)

Major enhancements:
- Network drive support
- Cloud storage integration (investigate)
- Advanced filters (by owner, permissions)
- Duplicate file detection
- Custom layout algorithms

---

## 🤝 Contributing

### For Fortran Developers

This project is a showcase of Fortran's capabilities! Contributions welcome:
- Algorithm optimizations
- New layout algorithms
- Performance improvements
- Code reviews

### For GUI Developers

Help make sniffly beautiful:
- UI/UX improvements
- Icon design
- Color scheme contributions
- Accessibility enhancements

### For Package Maintainers

Help distribute sniffly:
- Create packages for your favorite distro
- Test on various platforms
- Report packaging issues
- Maintain downstream packages

---

## 📄 License

**Recommendation:** MIT or BSD-3-Clause

**Rationale:**
- Permissive enough for wide adoption
- Compatible with GTK's LGPL
- Allows commercial use
- Simple and well-understood

---

## 🎉 Conclusion

This project will prove that Fortran can create modern, beautiful GUI applications that rival commercial software. By combining gtk-fortran's solid bindings with your already-excellent treemap algorithms, sniffly will be a showcase of:

1. **Fortran's Versatility:** Not just for scientific computing!
2. **Open Source Quality:** Unix users deserve great tools
3. **Performance:** Native code, no interpreter overhead
4. **Cross-Platform:** One codebase, multiple platforms

**Let's build this!** 🚀

---

**Next Steps:**
1. Install GTK4 and gtk-fortran
2. Create minimal GTK window test
3. Port core scanning logic
4. Start Phase 1 implementation

**Questions? Need help?**
- gtk-fortran community is friendly and helpful
- GTK documentation is extensive
- This plan is a living document - iterate as needed!

---

**Document Version:** 1.0
**Last Updated:** 2025-11-04
**Status:** Ready to Begin Development
