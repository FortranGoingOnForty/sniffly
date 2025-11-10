#!/bin/bash
# Simple library bundling - copy libs and update binary paths only
# Don't touch the bundled libraries themselves

set -e

APP_BUNDLE="Sniffly.app"
FRAMEWORKS="${APP_BUNDLE}/Contents/Frameworks"
MACOS_BIN="${APP_BUNDLE}/Contents/MacOS/sniffly"

echo "=== Simple Library Bundling ==="

# Copy all GTK4-related libraries recursively
echo "Step 1: Copying GTK4 libraries..."
mkdir -p "$FRAMEWORKS"

# Function to copy a library and its dependencies
copy_lib_and_deps() {
    local lib=$1
    local libname=$(basename "$lib")

    if [ -f "$FRAMEWORKS/$libname" ]; then
        return  # Already copied
    fi

    if [ ! -f "$lib" ]; then
        return  # Doesn't exist
    fi

    echo "  Copying $libname"
    cp "$lib" "$FRAMEWORKS/"
    chmod 644 "$FRAMEWORKS/$libname"

    # Get dependencies and copy them too
    otool -L "$lib" | grep "/opt/homebrew" | awk '{print $1}' | while read dep; do
        if [ -f "$dep" ]; then
            copy_lib_and_deps "$dep"
        fi
    done
}

# Start with the main libraries the binary needs
for lib in libgtk-4-fortran libgtk-4 libcairo libgio libglib libgfortran; do
    find /opt/homebrew -name "${lib}*.dylib" -o -name "${lib}*.*.dylib" 2>/dev/null | head -1 | while read libpath; do
        if [ -n "$libpath" ]; then
            copy_lib_and_deps "$libpath"
        fi
    done
done

# Also copy from /usr/local for gtk-4-fortran
if [ -f "/usr/local/lib/libgtk-4-fortran.4.8.0.dylib" ]; then
    copy_lib_and_deps "/usr/local/lib/libgtk-4-fortran.4.8.0.dylib"
fi

echo ""
echo "Step 2: Updating binary to use bundled libraries..."
# Only update the main binary's paths - don't touch the libraries
for lib in "$FRAMEWORKS"/*.dylib; do
    if [ -f "$lib" ]; then
        libname=$(basename "$lib")
        # Try to change the binary's reference to this library
        install_name_tool -change "/opt/homebrew/opt/*/lib/$libname" "@executable_path/../Frameworks/$libname" "$MACOS_BIN" 2>/dev/null || true
        install_name_tool -change "/usr/local/lib/$libname" "@executable_path/../Frameworks/$libname" "$MACOS_BIN" 2>/dev/null || true
    fi
done

# Update specific known paths in the binary
install_name_tool -change "@rpath/libgtk-4-fortran.4.8.0.dylib" "@executable_path/../Frameworks/libgtk-4-fortran.4.8.0.dylib" "$MACOS_BIN" 2>/dev/null || true
install_name_tool -change "/opt/homebrew/opt/gtk4/lib/libgtk-4.1.dylib" "@executable_path/../Frameworks/libgtk-4.1.dylib" "$MACOS_BIN" 2>/dev/null || true
install_name_tool -change "/opt/homebrew/opt/cairo/lib/libcairo.2.dylib" "@executable_path/../Frameworks/libcairo.2.dylib" "$MACOS_BIN" 2>/dev/null || true
install_name_tool -change "/opt/homebrew/opt/glib/lib/libgio-2.0.0.dylib" "@executable_path/../Frameworks/libgio-2.0.0.dylib" "$MACOS_BIN" 2>/dev/null || true
install_name_tool -change "/opt/homebrew/opt/glib/lib/libglib-2.0.0.dylib" "@executable_path/../Frameworks/libglib-2.0.0.dylib" "$MACOS_BIN" 2>/dev/null || true
install_name_tool -change "/opt/homebrew/opt/gcc/lib/gcc/current/libgfortran.5.dylib" "@executable_path/../Frameworks/libgfortran.5.dylib" "$MACOS_BIN" 2>/dev/null || true

echo ""
echo "Step 3: Fixing bundled libraries to reference each other..."
# Fix all the bundled libraries to reference each other instead of /opt/homebrew
for lib in "$FRAMEWORKS"/*.dylib; do
    if [ -f "$lib" ]; then
        libname=$(basename "$lib")

        # Fix the library's ID
        install_name_tool -id "@executable_path/../Frameworks/$libname" "$lib" 2>/dev/null || true

        # Fix only the actual dependencies (much faster than trying all combinations)
        otool -L "$lib" | grep "/opt/homebrew\|/usr/local" | awk '{print $1}' | while read dep_path; do
            dep_name=$(basename "$dep_path")
            if [ -f "$FRAMEWORKS/$dep_name" ]; then
                install_name_tool -change "$dep_path" "@executable_path/../Frameworks/$dep_name" "$lib" 2>/dev/null || true
            fi
        done
    fi
done

echo ""
echo "Step 4: Re-signing everything (CRITICAL)..."
# After install_name_tool modifications, code signatures are invalid
# macOS will SIGKILL the app if signatures don't match
# Use ad-hoc signing (no certificate needed)
echo "  Re-signing main binary..."
codesign --remove-signature "$MACOS_BIN" 2>/dev/null || true
codesign -s - -f "$MACOS_BIN"

echo "  Re-signing bundled libraries..."
for lib in "$FRAMEWORKS"/*.dylib; do
    if [ -f "$lib" ]; then
        codesign --remove-signature "$lib" 2>/dev/null || true
        codesign -s - -f "$lib" 2>/dev/null || true
    fi
done

echo ""
echo "Step 5: Verifying..."
TOTAL_LIBS=$(ls -1 "$FRAMEWORKS" | wc -l | tr -d ' ')
echo "Total libraries bundled: $TOTAL_LIBS"

echo ""
echo "=== Bundling Complete ==="
