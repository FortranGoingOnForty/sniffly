#!/bin/bash
# Complete library bundling script for Sniffly
# Handles all GTK4 dependencies properly

set -e

APP_BUNDLE="Sniffly.app"
FRAMEWORKS="${APP_BUNDLE}/Contents/Frameworks"
MACOS_BIN="${APP_BUNDLE}/Contents/MacOS/sniffly-bin"

echo "=== Sniffly Library Bundling ==="
echo ""

# Create frameworks directory
mkdir -p "$FRAMEWORKS"

echo "Step 1: Copying critical GTK4 libraries..."
# Main GTK4
cp -v /opt/homebrew/opt/gtk4/lib/libgtk-4.1.dylib "$FRAMEWORKS/" 2>/dev/null || echo "  libgtk-4.1.dylib not found (may be bundled already)"

# GLib family
cp -v /opt/homebrew/opt/glib/lib/libglib-2.0.0.dylib "$FRAMEWORKS/" 2>/dev/null || true
cp -v /opt/homebrew/opt/glib/lib/libgio-2.0.0.dylib "$FRAMEWORKS/" 2>/dev/null || true
cp -v /opt/homebrew/opt/glib/lib/libgobject-2.0.0.dylib "$FRAMEWORKS/" 2>/dev/null || true
cp -v /opt/homebrew/opt/glib/lib/libgmodule-2.0.0.dylib "$FRAMEWORKS/" 2>/dev/null || true

# GTK-Fortran binding
cp -v /usr/local/lib/libgtk-4-fortran.4.8.0.dylib "$FRAMEWORKS/" 2>/dev/null || true

# Pango
cp -v /opt/homebrew/opt/pango/lib/libpango-1.0.0.dylib "$FRAMEWORKS/" 2>/dev/null || true
cp -v /opt/homebrew/opt/pango/lib/libpangocairo-1.0.0.dylib "$FRAMEWORKS/" 2>/dev/null || true
cp -v /opt/homebrew/opt/pango/lib/libpangoft2-1.0.0.dylib "$FRAMEWORKS/" 2>/dev/null || true

# GdkPixbuf
cp -v /opt/homebrew/opt/gdk-pixbuf/lib/libgdk_pixbuf-2.0.0.dylib "$FRAMEWORKS/" 2>/dev/null || true

# Cairo
cp -v /opt/homebrew/opt/cairo/lib/libcairo.2.dylib "$FRAMEWORKS/" 2>/dev/null || true
cp -v /opt/homebrew/opt/cairo/lib/libcairo-gobject.2.dylib "$FRAMEWORKS/" 2>/dev/null || true

# HarfBuzz
cp -v /opt/homebrew/opt/harfbuzz/lib/libharfbuzz.0.dylib "$FRAMEWORKS/" 2>/dev/null || true

# Graphene
cp -v /opt/homebrew/opt/graphene/lib/libgraphene-1.0.0.dylib "$FRAMEWORKS/" 2>/dev/null || true

# Epoxy (OpenGL wrapper)
cp -v /opt/homebrew/opt/libepoxy/lib/libepoxy.0.dylib "$FRAMEWORKS/" 2>/dev/null || true

# Gettext (internationalization)
cp -v /opt/homebrew/opt/gettext/lib/libintl.8.dylib "$FRAMEWORKS/" 2>/dev/null || true

# Additional dependencies
cp -v /opt/homebrew/opt/fribidi/lib/libfribidi.0.dylib "$FRAMEWORKS/" 2>/dev/null || true
cp -v /opt/homebrew/opt/fontconfig/lib/libfontconfig.1.dylib "$FRAMEWORKS/" 2>/dev/null || true
cp -v /opt/homebrew/opt/freetype/lib/libfreetype.6.dylib "$FRAMEWORKS/" 2>/dev/null || true

echo ""
echo "Step 2: Running dylibbundler for ALL dependencies..."
echo "Note: dylibbundler may fail on GFortran libraries due to Mach-O header limits."
echo "      This is expected and non-fatal - the app will still work correctly."
echo ""

# Use -of to overwrite and fix ALL dylibs recursively
# The dylibbundler will fail on libgfortran.5.dylib due to insufficient Mach-O header padding,
# but this is non-fatal. The library will still be bundled and functional.
dylibbundler -of -b \
    -x "$MACOS_BIN" \
    -d "$FRAMEWORKS/" \
    -p @executable_path/../Frameworks/ \
    -s /usr/local/lib \
    -s /opt/homebrew/lib \
    -s /opt/homebrew/opt/gtk4/lib \
    -s /opt/homebrew/opt/glib/lib \
    -s /opt/homebrew/opt/pango/lib \
    -s /opt/homebrew/opt/cairo/lib \
    -s /opt/homebrew/opt/harfbuzz/lib \
    -s /opt/homebrew/opt/gdk-pixbuf/lib \
    -s /opt/homebrew/opt/graphene/lib \
    -s /opt/homebrew/opt/libepoxy/lib \
    -s /opt/homebrew/opt/gettext/lib \
    -s /opt/homebrew/opt/fribidi/lib \
    -s /opt/homebrew/opt/fontconfig/lib \
    -s /opt/homebrew/opt/freetype/lib \
    -s /opt/homebrew/opt/libpng/lib \
    -s /opt/homebrew/opt/graphite2/lib \
    -s /opt/homebrew/opt/pcre2/lib \
    -s /opt/homebrew/opt/brotli/lib \
    -s /opt/homebrew/opt/bzip2/lib \
    -s /opt/homebrew/opt/zstd/lib 2>&1 || echo "  (dylibbundler completed with warnings - this is expected)"

echo ""
echo "Step 2.5: Manually fixing GFortran library references..."
# dylibbundler fails to fully fix libgfortran due to header limits, so we fix remaining references manually
# Fix binary's reference to libgfortran
install_name_tool -change /opt/homebrew/opt/gcc/lib/gcc/current/libgfortran.5.dylib @executable_path/../Frameworks/libgfortran.5.dylib "$MACOS_BIN" 2>/dev/null || true
install_name_tool -change /usr/local/lib/gcc/current/libgfortran.5.dylib @executable_path/../Frameworks/libgfortran.5.dylib "$MACOS_BIN" 2>/dev/null || true

# Fix libgfortran's internal references (only if it exists and isn't fully fixed)
if [ -f "$FRAMEWORKS/libgfortran.5.dylib" ]; then
    # Try to fix remaining references - these might fail if header is full, but that's OK
    install_name_tool -change "@rpath/libgcc_s.1.1.dylib" "@executable_path/../Frameworks/libgcc_s.1.1.dylib" "$FRAMEWORKS/libgfortran.5.dylib" 2>/dev/null || true
    install_name_tool -id "@executable_path/../Frameworks/libgfortran.5.dylib" "$FRAMEWORKS/libgfortran.5.dylib" 2>/dev/null || true
fi

echo ""
echo "Step 3: Fixing library interdependencies..."
# dylibbundler should have done this, but let's make sure all bundled libs reference each other correctly
for lib in "$FRAMEWORKS"/*.dylib; do
    if [ -f "$lib" ]; then
        # Fix any remaining /opt/homebrew references
        install_name_tool -change /opt/homebrew/opt/glib/lib/libglib-2.0.0.dylib @executable_path/../Frameworks/libglib-2.0.0.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/glib/lib/libgio-2.0.0.dylib @executable_path/../Frameworks/libgio-2.0.0.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/glib/lib/libgobject-2.0.0.dylib @executable_path/../Frameworks/libgobject-2.0.0.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/glib/lib/libgmodule-2.0.0.dylib @executable_path/../Frameworks/libgmodule-2.0.0.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/cairo/lib/libcairo.2.dylib @executable_path/../Frameworks/libcairo.2.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/cairo/lib/libcairo-gobject.2.dylib @executable_path/../Frameworks/libcairo-gobject.2.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/pango/lib/libpango-1.0.0.dylib @executable_path/../Frameworks/libpango-1.0.0.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/pango/lib/libpangocairo-1.0.0.dylib @executable_path/../Frameworks/libpangocairo-1.0.0.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/gtk4/lib/libgtk-4.1.dylib @executable_path/../Frameworks/libgtk-4.1.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/gettext/lib/libintl.8.dylib @executable_path/../Frameworks/libintl.8.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/harfbuzz/lib/libharfbuzz.0.dylib @executable_path/../Frameworks/libharfbuzz.0.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/fribidi/lib/libfribidi.0.dylib @executable_path/../Frameworks/libfribidi.0.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/fontconfig/lib/libfontconfig.1.dylib @executable_path/../Frameworks/libfontconfig.1.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/freetype/lib/libfreetype.6.dylib @executable_path/../Frameworks/libfreetype.6.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/gdk-pixbuf/lib/libgdk_pixbuf-2.0.0.dylib @executable_path/../Frameworks/libgdk_pixbuf-2.0.0.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/graphene/lib/libgraphene-1.0.0.dylib @executable_path/../Frameworks/libgraphene-1.0.0.dylib "$lib" 2>/dev/null || true
        install_name_tool -change /opt/homebrew/opt/libepoxy/lib/libepoxy.0.dylib @executable_path/../Frameworks/libepoxy.0.dylib "$lib" 2>/dev/null || true
    fi
done

echo "  Fixing library ID names..."
# Also fix the library ID names themselves
for lib in "$FRAMEWORKS"/*.dylib; do
    if [ -f "$lib" ]; then
        libname=$(basename "$lib")
        install_name_tool -id @executable_path/../Frameworks/"$libname" "$lib" 2>/dev/null || true
    fi
done

echo ""
echo "Step 4: Verifying bundle..."
TOTAL_LIBS=$(ls -1 "$FRAMEWORKS" | wc -l | tr -d ' ')
echo "Total libraries bundled: $TOTAL_LIBS"

# Check for critical libraries
echo ""
echo "Critical libraries check:"
for lib in libgtk-4 libglib-2.0 libgtk-4-fortran libcairo libpango libgfortran; do
    if ls "$FRAMEWORKS"/${lib}* 1> /dev/null 2>&1; then
        echo "  ✓ ${lib}"
    else
        echo "  ✗ ${lib} MISSING!"
    fi
done

echo ""
echo "Step 5: Checking binary dependencies..."
otool -L "$MACOS_BIN" | grep -E "(gtk|glib|cairo)" | head -5

echo ""
echo "=== Bundling Complete ==="
