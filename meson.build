# Sniffly - Pure Fortran GUI Disk Analyzer
# Build configuration using Meson

project('sniffly', ['fortran', 'c'],
  version: '0.1.0',
  license: 'MIT',
  default_options: [
    'warning_level=3',
    'buildtype=debugoptimized',
  ])

# Minimum Meson version
meson_version_required = '>=0.60.0'

# Project information
project_description = 'Pure Fortran GUI disk analyzer inspired by SpaceSniffer'
project_url = 'https://github.com/FortranGoingOnForty/sniffly'

# Print build configuration
message('===========================================')
message('Configuring Sniffly v' + meson.project_version())
message('Build type: ' + get_option('buildtype'))
message('===========================================')

# Check for dependencies
message('Checking dependencies...')

# GTK4 via gtk-fortran (required)
gtk4_dep = dependency('gtk-4-fortran',
  version: '>=4.0',
  required: true,
  fallback: ['gtk-fortran', 'gtk4_dep'])

# Cairo (required for drawing)
cairo_dep = dependency('cairo',
  version: '>=1.16',
  required: true)

# Optional: threads for background scanning
thread_dep = dependency('threads', required: false)

# Collect all dependencies
dependencies = [
  gtk4_dep,
  cairo_dep,
]

if thread_dep.found()
  dependencies += thread_dep
  message('Threading support: enabled')
else
  message('Threading support: disabled (will use single-threaded scanning)')
endif

# Print dependency versions
message('GTK4-Fortran version: ' + gtk4_dep.version())
message('Cairo version: ' + cairo_dep.version())

# Source files
# Note: Order matters for Fortran modules (dependencies must come first)

# C helper sources (for file system operations)
c_sources = [
  'src/core/dir_helpers.c',
]

# Fortran source files
core_sources = [
  'src/core/types.f90',           # Must be first (no dependencies)
  'src/core/file_system.f90',     # Depends on types
  'src/core/disk_scanner.f90',    # Depends on types, file_system
]

layout_sources = [
  # Layout algorithms
  'src/layout/squarified.f90',    # Depends on types
  # 'src/layout/cushioned.f90',
  # 'src/layout/layout_manager.f90',
]

gui_sources = [
  # GTK4 interface
  'src/gui/treemap_widget.f90',  # Must come before gtk_app (dependency)
  'src/gui/gtk_app.f90',
  # 'src/gui/main_window.f90',
  # 'src/gui/toolbar.f90',
  # 'src/gui/statusbar.f90',
  # 'src/gui/dialogs.f90',
  # 'src/gui/menus.f90',
]

rendering_sources = [
  # Cairo rendering
  'src/rendering/treemap_renderer.f90',  # Depends on types, disk_scanner, squarified_layout, cairo
  # 'src/rendering/colors.f90',
  # 'src/rendering/text_layout.f90',
  # 'src/rendering/effects.f90',
]

state_sources = [
  # Application state (will add later)
  # 'src/state/app_state.f90',
  # 'src/state/selection.f90',
  # 'src/state/config.f90',
  # 'src/state/scan_manager.f90',
]

app_sources = [
  'app/main.f90',
]

# Combine all sources (C first, then Fortran in dependency order)
all_sources = c_sources + core_sources + layout_sources + gui_sources + rendering_sources + state_sources + app_sources

# Compiler flags
fortran = meson.get_compiler('fortran')
fortran_args = []

# Warning flags
if fortran.get_id() == 'gcc'
  fortran_args += [
    '-Wall',
    '-Wextra',
    '-Wimplicit-interface',
    '-fcheck=all',  # Runtime checks in debug mode
    '-fbacktrace',  # Backtrace on error
  ]
endif

# Build executable
executable('sniffly',
  sources: all_sources,
  dependencies: dependencies,
  fortran_args: fortran_args,
  install: true,
  install_dir: get_option('bindir'))

# Tests (to be added)
# subdir('test')

# Installation
# install_man('docs/sniffly.1')  # Man page (when created)

# Configuration summary
summary({
  'Version': meson.project_version(),
  'Build type': get_option('buildtype'),
  'Install prefix': get_option('prefix'),
  'GTK4-Fortran': gtk4_dep.version(),
  'Cairo': cairo_dep.version(),
  'Threading': thread_dep.found() ? 'yes' : 'no',
}, section: 'Configuration')

message('===========================================')
message('Sniffly configuration complete!')
message('Next steps:')
message('  1. Add source files to src/ directories')
message('  2. Uncomment source lists in meson.build')
message('  3. Uncomment executable() to build')
message('  4. Run: meson compile -C build')
message('===========================================')
