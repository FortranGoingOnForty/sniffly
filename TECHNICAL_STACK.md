# Sniffly Technical Stack Deep Dive

## Core Stack Justification

### Why Pure Fortran?

**Philosophy:** Prove that Fortran can build modern GUI applications that rival commercial software written in C++/C#.

**Practical Advantages:**
1. **Performance:** Native compilation, no VM/interpreter overhead
2. **Memory Safety:** Strong typing, bounds checking (with compiler flags)
3. **Existing Code:** Leverage proven algorithms from sniffert
4. **Mathematical Operations:** Natural for size calculations, layout algorithms
5. **Array Operations:** Efficient bulk operations on file trees

**Challenges Addressed:**
- String handling: Use allocatable character arrays (Fortran 2003+)
- Pointers: Use Fortran's C interoperability for GTK callbacks
- OOP: Use Fortran 2008 type-bound procedures where beneficial

---

## GTK4 via gtk-fortran

### Why GTK4 (not Qt, wxWidgets, etc.)?

**Technical Reasons:**
1. **gtk-fortran exists:** Mature, maintained Fortran bindings
2. **Native on Linux:** GTK is the de facto standard
3. **macOS Support:** GTK4 uses native Cocoa backend
4. **Modern:** GTK4 is actively developed, not legacy
5. **Cairo Integration:** Built-in 2D drawing library

**Comparison to Alternatives:**

| Framework | Fortran Bindings | Native Look | Performance | Verdict |
|-----------|-----------------|-------------|-------------|---------|
| GTK4 | gtk-fortran | Yes (Linux/macOS) | Excellent | ✅ Chosen |
| Qt | None (would need C++ wrapper) | Yes | Excellent | ❌ No bindings |
| wxWidgets | None | Yes | Good | ❌ No bindings |
| FLTK | None | No | Excellent | ❌ No bindings, dated look |
| Tk | None (would need Tcl) | No | Poor | ❌ Dated, slow |

**gtk-fortran Maturity:**
- First release: 2011
- Current version: 3.24.41 (2024)
- Active maintainer: Vincent Magnin
- Production use: Scientific visualization tools
- Platform support: Linux, macOS, FreeBSD, Windows (MSYS2)

### GTK4 Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Your Fortran Code                     │
│                   (sniffly modules)                      │
└─────────────────────────────────────────────────────────┘
                           │
                           ↓ (iso_c_binding)
┌─────────────────────────────────────────────────────────┐
│                      gtk-fortran                         │
│        (Fortran interfaces to GTK C functions)           │
└─────────────────────────────────────────────────────────┘
                           │
                           ↓ (FFI)
┌─────────────────────────────────────────────────────────┐
│                    GTK4 C Library                        │
│  ┌─────────────┬──────────────┬────────────────────┐    │
│  │   Widgets   │    GDK       │      GSK           │    │
│  │  (buttons,  │  (events,    │  (GPU rendering)   │    │
│  │   windows)  │   input)     │                    │    │
│  └─────────────┴──────────────┴────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────┐
│                    Platform Backend                      │
│   Linux: Wayland/X11    macOS: Cocoa    BSD: X11       │
└─────────────────────────────────────────────────────────┘
```

---

## Cairo for 2D Graphics

### Why Cairo?

**Technical Strengths:**
1. **Vector Graphics:** Resolution-independent rendering
2. **Anti-aliasing:** Beautiful, smooth edges
3. **Hardware Acceleration:** GPU-backed on modern systems
4. **Compositing:** Alpha blending, gradients, patterns
5. **Text Rendering:** Pango integration for complex text

**Cairo Features We'll Use:**

| Feature | Usage in Sniffly |
|---------|-----------------|
| `cairo_rectangle()` | Draw treemap rectangles |
| `cairo_fill()` | Fill rectangles with color |
| `cairo_stroke()` | Draw borders |
| `cairo_set_source_rgb()` | Set solid colors |
| `cairo_pattern_create_linear()` | Cushion gradients |
| `cairo_clip()` | Clip nested rectangles |
| `cairo_save()`/`restore()` | State management |
| Pango integration | Render file names |

**Performance Characteristics:**
- **Fast Paths:** Solid fills, axis-aligned rectangles
- **Slow Paths:** Bezier curves, complex paths (we won't use)
- **Caching:** Cairo surfaces can be cached
- **Expected Performance:** 60fps for 1000s of rectangles

### Cairo vs. OpenGL

We chose Cairo over OpenGL because:
- **Simpler API:** 2D-focused, easier to learn
- **Better Integration:** Built into GTK4
- **Text Rendering:** Pango support out of the box
- **Sufficient Performance:** 60fps achievable for our use case

If performance becomes an issue (unlikely), we can:
1. Use GTK4's GSK (GPU Scene Kit) backend
2. Batch render calls
3. Implement viewport culling (only draw visible nodes)

---

## Pango for Text

### Why Pango?

**Features:**
1. **Font Management:** System font detection, fallbacks
2. **Text Layout:** Ellipsization, wrapping, alignment
3. **Internationalization:** Full Unicode support, RTL text
4. **Integration:** Native Cairo rendering

**Pango Features We'll Use:**

```fortran
! Create Pango layout
layout = pango_cairo_create_layout(cairo_context)

! Set text
call pango_layout_set_text(layout, c_str("filename.txt"))

! Set font
font_desc = pango_font_description_from_string(c_str("Sans 10"))
call pango_layout_set_font_description(layout, font_desc)

! Set ellipsization for long text
call pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END)
call pango_layout_set_width(layout, width * PANGO_SCALE)

! Render
call pango_cairo_show_layout(cairo_context, layout)
```

---

## GLib for Core Utilities

### Threading

**GLib Threads** (not pthreads) for portability:

```fortran
! Start background scan thread
thread = g_thread_new(c_str("scanner"), c_funloc(scan_thread_func), c_loc(scan_data))

! Thread-safe UI updates from background thread
call g_idle_add(c_funloc(update_ui_callback), c_loc(progress_data))
```

**Why g_idle_add?**
- GTK is **not thread-safe**
- g_idle_add queues callback on main thread
- Callback runs in GTK event loop
- Safe to update UI from callback

### Event Loop

GTK's main loop handles:
- User input (mouse, keyboard)
- Window events (resize, close)
- Timers and idle callbacks
- Background task callbacks (g_idle_add)

```fortran
! Start GTK main loop (blocks until app quits)
call gtk_main()
```

### GLib Data Structures

We'll primarily use Fortran's native arrays, but GLib provides:
- `GList`/`GSList`: Linked lists (if needed for dynamic UI)
- `GHashTable`: Hash maps (for quick file lookup)
- `GString`: Dynamic strings (if Fortran strings insufficient)

---

## Build System: Meson

### Why Meson (not Make, CMake, FPM)?

**Meson Advantages:**
1. **GTK Standard:** All GTK projects use Meson
2. **Dependency Detection:** Auto-finds GTK, Cairo, etc. via pkg-config
3. **Fast:** Ninja backend, parallel builds
4. **Cross-Platform:** Works on Linux, macOS, BSD
5. **Clean Syntax:** Python-like, easy to read

**Meson vs. FPM:**
- FPM is great for pure Fortran projects
- FPM doesn't handle C library dependencies well
- We'll provide **both** Meson (primary) and FPM (fallback) builds

**Sample meson.build:**

```meson
project('sniffly', 'fortran',
  version: '1.0.0',
  default_options: ['warning_level=3'])

# Dependencies
gtk4_dep = dependency('gtk4')
cairo_dep = dependency('cairo')
pango_dep = dependency('pango')

# Source files
src = [
  'src/core/types.f90',
  'src/core/file_system.f90',
  'src/core/disk_scanner.f90',
  'src/layout/squarified.f90',
  'src/layout/cushioned.f90',
  'src/gui/gtk_app.f90',
  'src/rendering/cairo_renderer.f90',
  'app/main.f90',
]

# Executable
executable('sniffly', src,
  dependencies: [gtk4_dep, cairo_dep, pango_dep],
  install: true)
```

**Building:**
```bash
meson setup build
meson compile -C build
meson install -C build
```

---

## Development Tools

### Compiler

**gfortran 9.0+** (GCC Fortran compiler)

**Why gfortran?**
- Free and open source
- Excellent Fortran 2008 support
- C interoperability works well
- Available on all platforms

**Compiler Flags:**
```bash
# Debug build
-g -Wall -Wextra -fcheck=all -fbacktrace

# Release build
-O3 -march=native -flto
```

**Alternative:** Intel Fortran (ifx) also works but not required

### Debugger

**GDB** (GNU Debugger)
```bash
gdb ./build/sniffly
```

**LLDB** (macOS default)
```bash
lldb ./build/sniffly
```

### Profiling

**Linux: perf**
```bash
perf record ./sniffly /large/directory
perf report
```

**macOS: Instruments**
```bash
instruments -t "Time Profiler" ./sniffly /large/directory
```

**gprof** (cross-platform)
```bash
# Compile with -pg flag
gfortran -pg -o sniffly ...
./sniffly /large/directory
gprof sniffly gmon.out
```

### Memory Analysis

**valgrind** (Linux)
```bash
valgrind --leak-check=full ./sniffly /tmp
```

**AddressSanitizer** (both platforms)
```bash
gfortran -fsanitize=address -o sniffly ...
./sniffly /tmp
```

---

## Dependency Installation

### macOS (Homebrew)

```bash
# Install GTK4 and dependencies
brew install gtk4 cairo pango glib

# Install gtk-fortran (build from source)
git clone https://github.com/vmagnin/gtk-fortran.git
cd gtk-fortran
cmake -B build
cmake --build build
sudo cmake --install build

# Install build tools
brew install gfortran meson ninja
```

### Ubuntu/Debian

```bash
# Install GTK4 and dependencies
sudo apt install libgtk-4-dev libcairo2-dev libpango1.0-dev libglib2.0-dev

# Install gtk-fortran (build from source)
git clone https://github.com/vmagnin/gtk-fortran.git
cd gtk-fortran
cmake -B build
cmake --build build
sudo cmake --install build

# Install build tools
sudo apt install gfortran meson ninja-build
```

### Arch Linux

```bash
# Install GTK4 and dependencies
sudo pacman -S gtk4 cairo pango glib2

# gtk-fortran from AUR
yay -S gtk-fortran

# Install build tools
sudo pacman -S gcc-fortran meson ninja
```

### Fedora/RHEL

```bash
# Install GTK4 and dependencies
sudo dnf install gtk4-devel cairo-devel pango-devel glib2-devel

# Install gtk-fortran (build from source)
git clone https://github.com/vmagnin/gtk-fortran.git
cd gtk-fortran
cmake -B build
cmake --build build
sudo cmake --install build

# Install build tools
sudo dnf install gcc-gfortran meson ninja-build
```

---

## GTK4 Inspector

**What is it?**
- Built-in GUI debugger for GTK apps
- Inspect widget hierarchy
- View CSS styles
- Monitor signals and events
- Performance profiling

**How to Enable:**
```bash
# Set environment variable
export GTK_DEBUG=interactive

# Run app (inspector opens automatically)
./sniffly
```

**Features:**
- Widget tree browser
- Property editor (live changes)
- CSS inspector
- Signal log
- Performance metrics

---

## Testing Infrastructure

### Unit Testing: FUnit

**Why FUnit?**
- Pure Fortran testing framework
- Simple assertion API
- Integrates with Meson

**Sample Test:**
```fortran
module test_squarified
  use squarified
  use funit
  implicit none
contains

  @test
  subroutine test_aspect_ratio()
    real :: ratio

    ratio = aspect_ratio(10, 10)
    @assertEqual(1.0, ratio, tolerance=0.01)

    ratio = aspect_ratio(20, 10)
    @assertEqual(2.0, ratio, tolerance=0.01)
  end subroutine

end module test_squarified
```

### Integration Testing: Python

**Why Python?**
- Easy to script GTK interactions
- Screenshot comparison libraries
- Rich assertion libraries

**Sample Test:**
```python
import gi
gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, GLib
import subprocess
import time

def test_launch_and_scan():
    # Launch sniffly
    proc = subprocess.Popen(['./sniffly'])
    time.sleep(2)

    # TODO: Automate UI interaction
    # For now, manual testing with checklist

    proc.terminate()
    assert proc.returncode == 0 or proc.returncode is None
```

---

## Continuous Integration

### GitHub Actions Workflow

**.github/workflows/build.yml:**
```yaml
name: Build and Test

on: [push, pull_request]

jobs:
  build-linux:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install dependencies
        run: |
          sudo apt update
          sudo apt install -y libgtk-4-dev gfortran meson ninja-build
      - name: Build gtk-fortran
        run: |
          git clone https://github.com/vmagnin/gtk-fortran.git
          cd gtk-fortran
          cmake -B build && cmake --build build
          sudo cmake --install build
      - name: Build sniffly
        run: |
          meson setup build
          meson compile -C build
      - name: Run tests
        run: meson test -C build

  build-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install dependencies
        run: |
          brew install gtk4 gfortran meson ninja
      - name: Build gtk-fortran
        run: |
          git clone https://github.com/vmagnin/gtk-fortran.git
          cd gtk-fortran
          cmake -B build && cmake --build build
          sudo cmake --install build
      - name: Build sniffly
        run: |
          meson setup build
          meson compile -C build
      - name: Run tests
        run: meson test -C build
```

---

## Alternative Stacks Considered

### 1. Rust + gtk-rs

**Pros:**
- Excellent GTK bindings
- Memory safety guarantees
- Growing ecosystem

**Cons:**
- Not Fortran (defeats the purpose!)
- Would need to rewrite all sniffert logic
- Steeper learning curve

**Verdict:** ❌ Wrong language

### 2. Fortran + QML (Qt Quick)

**Pros:**
- Modern declarative UI
- Hardware-accelerated

**Cons:**
- No Fortran bindings for QML
- Would need C++/Python bridge
- Qt is heavy dependency

**Verdict:** ❌ No Fortran support

### 3. Fortran + Web (Electron-style)

**Pros:**
- HTML/CSS for UI
- Easy prototyping

**Cons:**
- Huge resource usage
- Slow startup
- Not native look & feel
- Would need REST API layer

**Verdict:** ❌ Defeats performance goals

### 4. Fortran + Custom OpenGL

**Pros:**
- Maximum performance
- Full control

**Cons:**
- Reinvent wheel (buttons, text input, etc.)
- Months of UI infrastructure work
- Platform-specific window management

**Verdict:** ❌ Too much work

---

## Summary: Why This Stack is Optimal

| Requirement | Solution | Rationale |
|-------------|----------|-----------|
| Pure Fortran | gtk-fortran | Only mature Fortran GUI option |
| Cross-platform | GTK4 | Native on Linux, good on macOS |
| 2D rendering | Cairo | Built-in, hardware-accelerated |
| Text rendering | Pango | Unicode, fonts, ellipsization |
| Build system | Meson | GTK standard, dependency handling |
| Threading | GLib | Safe GTK integration |
| Performance | Native compilation | No interpreter overhead |
| Maintainability | Reuse sniffert | Proven algorithms |

---

## Risk Mitigation

### Risk: gtk-fortran bugs or limitations

**Mitigation:**
- Join gtk-fortran community early
- Contribute fixes upstream
- Fallback: C shim layer for problematic functions

### Risk: GTK4 not looking native on macOS

**Mitigation:**
- GTK4 uses Cocoa backend (better than GTK3)
- Test early and often on macOS
- Accept "good enough" if perfect not achievable

### Risk: Performance insufficient

**Mitigation:**
- Profile early (Week 4)
- Viewport culling for large trees
- Consider GSK (GTK's GPU backend) if needed

### Risk: Build complexity scares users

**Mitigation:**
- Provide pre-built binaries
- Package for all major package managers
- Clear installation instructions
- CI/CD for automated builds

---

## Conclusion

This stack provides:
1. ✅ **Pure Fortran** (proving the point)
2. ✅ **Modern GUI** (GTK4)
3. ✅ **Cross-platform** (macOS, Linux)
4. ✅ **Performant** (native code)
5. ✅ **Maintainable** (reuse sniffert)
6. ✅ **Packageable** (standard tools)

**We're ready to build!** 🚀
