# Sniffly Project Summary

**Status:** Planning Complete ✅
**Date:** 2025-11-04
**Next Step:** Begin Phase 1 Development

---

## What We're Building

**Sniffly** is a pure Fortran GUI application that visualizes disk space usage with interactive treemap diagrams. It's a near 1:1 clone of SpaceSniffer (a popular Windows tool) but for Unix systems (macOS and Linux).

### The Big Idea

Prove that Fortran isn't just for scientific computing—it can build beautiful, modern GUI applications that rival commercial software written in C++/C#.

---

## Technology Stack (Final Decision)

| Component | Technology | Why |
|-----------|-----------|-----|
| **Language** | Fortran 2008+ | Pure Fortran philosophy, performance |
| **GUI Framework** | GTK4 | Modern, cross-platform, has Fortran bindings |
| **Bindings** | gtk-fortran 3.24.41+ | Only mature Fortran GUI library |
| **Graphics** | Cairo 1.18+ | Hardware-accelerated 2D drawing |
| **Text** | Pango | Font rendering, ellipsization |
| **Build System** | Meson (primary) | GTK standard, handles dependencies |
| **Platforms** | macOS, Linux | Priority targets (no Windows) |

---

## Core Features

### Must-Have (v1.0)

1. **Real-time Treemap Visualization**
   - Animated growth during scanning
   - Nested rectangles proportional to file sizes
   - Smooth layout transitions

2. **Two Layout Algorithms**
   - Squarified treemap (already implemented in sniffert)
   - Cushioned treemap (3D shading effect like SpaceSniffer)

3. **Interactive Navigation**
   - Click to zoom into directories
   - Breadcrumb navigation bar
   - Context menus (right-click)
   - Keyboard shortcuts (same as sniffert: q, c, d, arrows)

4. **Search and Filter**
   - Search by filename (regex support)
   - Filter by file type, size, date
   - Highlight matching files

5. **Safe File Deletion**
   - Delete with confirmation dialog
   - Show full path and size
   - Large deletions require typing name

6. **Visual Customization**
   - Multiple color schemes (Light, Dark, High Contrast)
   - Color by file type, age, or custom
   - Configurable fonts and sizes

7. **High Performance**
   - Handle 1M+ files
   - 60fps rendering
   - Background scanning without blocking UI

### Nice-to-Have (Post-v1.0)

- Export treemap as PNG/SVG
- Compare two directory snapshots
- Bookmarks for frequent directories
- Hidden files toggle
- Multiple tabs

---

## Architecture Overview

```
┌─────────────────────────────────────────┐
│         GTK4 Main Window                │
│  ┌───────────────────────────────────┐  │
│  │ Toolbar: Scan | Layout | Search   │  │
│  ├───────────────────────────────────┤  │
│  │                                   │  │
│  │   Treemap Widget (Custom)        │  │
│  │   ┌───────────────────────────┐  │  │
│  │   │  Cairo Drawing Surface    │  │  │
│  │   │  (Rectangles, gradients)  │  │  │
│  │   └───────────────────────────┘  │  │
│  │                                   │  │
│  ├───────────────────────────────────┤  │
│  │ Status: Scanning /foo/bar        │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
           │
           ↓
┌─────────────────────────────────────────┐
│      Application State Manager          │
│  • Directory tree (file_node)           │
│  • Layout cache                         │
│  • Selection state                      │
│  • Scan progress                        │
└─────────────────────────────────────────┘
           │
    ┌──────┴───────┐
    ↓              ↓
┌────────┐    ┌────────┐
│Scanner │    │Renderer│
│(thread)│    │(Cairo) │
└────────┘    └────────┘
```

### Module Organization

```
src/
├── core/          # Reused from sniffert
│   ├── types.f90
│   ├── file_system.f90
│   ├── disk_scanner.f90
│   └── utils.f90
│
├── layout/        # Treemap algorithms
│   ├── squarified.f90  (port from sniffert)
│   ├── cushioned.f90   (new implementation)
│   └── layout_manager.f90
│
├── gui/           # GTK4 interface
│   ├── gtk_app.f90
│   ├── main_window.f90
│   ├── treemap_widget.f90
│   └── dialogs.f90
│
├── rendering/     # Cairo drawing
│   ├── cairo_renderer.f90
│   ├── colors.f90
│   └── effects.f90
│
└── state/         # App state
    ├── app_state.f90
    ├── selection.f90
    └── scan_manager.f90
```

---

## Development Timeline

**Total Duration:** 12-14 weeks to v1.0

| Phase | Weeks | Goal | Key Deliverables |
|-------|-------|------|-----------------|
| **Phase 1** | 1-2 | Foundation & GTK Setup | Basic GTK window, Cairo drawing |
| **Phase 2** | 3-4 | Core Data & Scanning | Background scanning, state management |
| **Phase 3** | 5-6 | Layout Algorithms | Squarified + Cushioned layouts |
| **Phase 4** | 7-8 | Cairo Rendering | Beautiful rendering, cushion effects |
| **Phase 5** | 9-10 | Interactivity | Navigation, context menus, keyboard |
| **Phase 6** | 11 | Search & Filter | Search box, filtering UI |
| **Phase 7** | 12 | Polish & Config | Settings, animations, accessibility |
| **Phase 8** | 13-14 | Testing & Packaging | Packages for macOS/Linux |

### Current Status

✅ **Planning Complete** (Week 0)
- All documentation written
- Architecture designed
- Stack chosen and validated

🚧 **Phase 1 Starting** (Week 1)
- Install dependencies
- Build hello world GTK app
- Set up project structure

---

## Key Technical Decisions

### 1. Pure Fortran (No C++/Python hybrid)

**Decision:** Use ONLY Fortran via gtk-fortran
**Rationale:** Proves the point that Fortran can do GUIs
**Trade-off:** Steeper learning curve, less examples
**Mitigation:** gtk-fortran is mature and well-documented

### 2. GTK4 (Not Qt, wxWidgets, or custom OpenGL)

**Decision:** GTK4 via gtk-fortran
**Rationale:**
- Only mature Fortran GUI bindings exist
- Native on Linux, good on macOS (Cocoa backend)
- Cairo integration for custom drawing

**Trade-off:** Not as native-looking on macOS as Qt
**Mitigation:** GTK4 is much better than GTK3 on macOS

### 3. Cushioned Treemap (Not Spiral)

**Decision:** Implement cushioned treemap (like SpaceSniffer)
**Rationale:** Research shows SpaceSniffer uses cushioned, not spiral
**Implementation:** Van Wijk algorithm with Cairo gradients
**Benefit:** More visually appealing than flat squarified

### 4. Meson Build System (Not Make or pure FPM)

**Decision:** Meson primary, FPM fallback
**Rationale:**
- Meson is GTK standard
- Handles pkg-config dependencies elegantly
- Cross-platform without pain

**Trade-off:** Fortran community less familiar with Meson
**Mitigation:** Provide clear build instructions

### 5. Package Manager Distribution (Not just GitHub releases)

**Decision:** Target Homebrew, apt, pacman
**Rationale:** Users expect `brew install sniffly`, not "build from source"
**Implementation:** Create packages in Phase 8
**Benefit:** Wider adoption, professional image

---

## Success Metrics

### Technical Success

- ✅ Builds on macOS and Linux without errors
- ✅ Handles 1M+ files in < 10 seconds scan time
- ✅ Renders at 60fps with 1000s of visible nodes
- ✅ Uses < 1GB RAM for 1M files
- ✅ No memory leaks (valgrind clean)

### Community Success

- 🎯 1,000 GitHub stars in first 3 months
- 🎯 10,000 downloads in first 6 months
- 🎯 Accepted into Homebrew and major Linux repos
- 🎯 5+ external contributors
- 🎯 Featured on Hacker News or /r/programming

### Philosophy Success

- 🎯 Proves Fortran can build modern GUIs
- 🎯 Becomes showcase example for gtk-fortran
- 🎯 Inspires other Fortran GUI projects
- 🎯 Mentioned in "Fortran can do that?!" articles

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| gtk-fortran bugs/limitations | Medium | High | Join community early, contribute fixes |
| Performance insufficient | Low | High | Profile early, optimize, viewport culling |
| GTK4 not native on macOS | Low | Medium | Accept "good enough", focus on functionality |
| Build complexity scares users | Medium | Medium | Package managers, pre-built binaries |
| Cushion algorithm too complex | Low | Low | Well-documented (Van Wijk paper), examples exist |
| Timeline slips | Medium | Low | Phases are independent, can adjust scope |

---

## Documentation Created

All planning documents are complete and ready:

1. **README.md** - Project overview, status, quick links
2. **SNIFFLY_MASTER_PLAN.md** - Complete 14-week roadmap (comprehensive!)
3. **TECHNICAL_STACK.md** - Deep dive on all technology choices
4. **QUICKSTART.md** - 30-minute setup guide with examples
5. **GETTING_STARTED.md** - Contributor guide, workflow, style
6. **PROJECT_SUMMARY.md** - This document
7. **LICENSE** - MIT License
8. **meson.build** - Build configuration
9. **.gitignore** - Git ignore rules

**Total Documentation:** ~15,000 words across 9 files

---

## Project Structure Created

```
sniffly/
├── README.md
├── SNIFFLY_MASTER_PLAN.md
├── TECHNICAL_STACK.md
├── QUICKSTART.md
├── GETTING_STARTED.md
├── PROJECT_SUMMARY.md
├── LICENSE
├── meson.build
├── .gitignore
│
├── app/                 # (empty, ready for main.f90)
├── src/
│   ├── core/            # (empty, ready for modules)
│   ├── layout/
│   ├── gui/
│   ├── rendering/
│   └── state/
├── test/                # (empty, ready for tests)
├── docs/                # (empty, ready for docs)
└── examples/            # (empty, ready for examples)
```

---

## Next Steps (Immediate)

### Week 1: Environment Setup

1. **Install Dependencies**
   ```bash
   # macOS
   brew install gtk4 gfortran meson ninja

   # Ubuntu
   sudo apt install libgtk-4-dev gfortran meson ninja-build
   ```

2. **Build gtk-fortran**
   ```bash
   git clone https://github.com/vmagnin/gtk-fortran.git
   cd gtk-fortran
   cmake -B build && cmake --build build
   sudo cmake --install build
   ```

3. **Test GTK4 Works**
   - Follow QUICKSTART.md hello world example
   - Verify window opens
   - Verify Cairo drawing works

4. **Create First Modules**
   - Port `src/types.f90` from sniffert
   - Port `src/file_system.f90` from sniffert
   - Create `app/main.f90` with basic GTK app

### Week 2: Basic UI

1. **Create gtk_app Module**
   - Initialize GTK application
   - Create main window
   - Add menu bar skeleton

2. **Create treemap_widget Module**
   - Custom GtkDrawingArea
   - Connect draw signal
   - Draw static rectangles (test)

3. **Test Build System**
   - Update meson.build with sources
   - Build and run
   - Verify end-to-end compilation

---

## Long-term Vision

### Version 1.0 (Week 14)

- ✅ Feature parity with terminal sniffert
- ✅ Beautiful GUI with cushion effects
- ✅ Packages for macOS and Linux
- ✅ Documentation complete

### Version 1.x (Months 2-6)

- Multiple tabs for different scans
- Export treemap as images
- Compare directory snapshots
- Cloud storage integration (?)

### Version 2.0 (6+ months)

- Plugin system for custom layouts
- Network drive scanning
- Advanced filtering (by owner, permissions)
- Duplicate file detection

---

## Relationship to sniffert

Sniffly is the GUI companion to sniffert:

| Feature | sniffert (terminal) | sniffly (GUI) |
|---------|-------------------|---------------|
| **Interface** | Terminal (ncurses) | Native window (GTK4) |
| **Input** | Keyboard only | Mouse + keyboard |
| **Visual** | ASCII art | Beautiful cushion maps |
| **Performance** | Lightweight | More resource-intensive |
| **Use Case** | SSH, servers | Desktop workstations |
| **Shared Code** | Types, scanning, layout algorithms | |

Both prove Fortran can do modern UIs!

---

## Why This Will Succeed

1. **Solid Foundation**
   - Proven algorithms from sniffert
   - gtk-fortran is mature and maintained
   - GTK4 is modern and well-documented

2. **Clear Plan**
   - 8 phases with specific deliverables
   - Each phase builds on previous
   - Realistic timeline with buffer

3. **Technical Excellence**
   - Performance targets defined
   - Testing strategy planned
   - Package distribution planned

4. **Community Appeal**
   - "Fortran can do that?!" factor
   - Useful tool people actually need
   - Open source, easy to contribute

5. **Proven Demand**
   - SpaceSniffer is popular on Windows
   - Unix users want equivalent
   - No good open-source alternative exists

---

## Quotes to Remember

> "Why Fortran?"
> **"Why not? It's fast, proven, and this proves it can do anything."**

> "Is gtk-fortran mature enough?"
> **"Yes! It's been around since 2011, actively maintained, and production-ready."**

> "Can Fortran really do GUIs?"
> **"Watch us. We're building a SpaceSniffer clone that will blow your mind."**

---

## Final Checklist

Planning Phase Complete:

- ✅ Research SpaceSniffer features
- ✅ Research gtk-fortran capabilities
- ✅ Choose technology stack
- ✅ Design architecture
- ✅ Create module structure
- ✅ Write comprehensive documentation
- ✅ Create project structure
- ✅ Define success metrics
- ✅ Assess risks
- ✅ Create timeline

**Status: Ready to Begin Development! 🚀**

---

## Contact & Links

- **Project Location:** `/Users/matthewwolffe/Documents/GithubOrgs/FortranGoingOnForty/sniffly`
- **Related Project:** `../sniffert` (terminal version)
- **Main Documentation:** `SNIFFLY_MASTER_PLAN.md`
- **Quick Start:** `QUICKSTART.md`

---

**Sniffly: Proving Fortran Can Build Beautiful GUIs**

*Created: 2025-11-04*
*Planning Phase: Complete ✅*
*Next Phase: Development Begins 🚀*
