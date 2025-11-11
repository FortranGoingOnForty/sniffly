# Sniffly Packaging Guide

This document explains how to package Sniffly for distribution on macOS and Linux.

## Current State

Sniffly is built using:
- **Meson** build system
- **GTK4** for the GUI
- **gtk-fortran** bindings
- **gfortran** compiler (GCC Fortran)

The executable is currently located at `build/sniffly` after running `meson compile -C build`.

---

## macOS Packaging (.dmg)

### Overview
On macOS, applications are distributed as:
1. **.app bundles** - Directory structure that looks like a single file
2. **.dmg files** - Disk images containing the .app bundle

### Steps to Create a macOS .app Bundle

#### 1. Create the Bundle Structure

```bash
# Create the app bundle directories
mkdir -p Sniffly.app/Contents/MacOS
mkdir -p Sniffly.app/Contents/Resources
mkdir -p Sniffly.app/Contents/Frameworks
```

#### 2. Copy the Executable

```bash
# Copy the compiled binary
cp build/sniffly Sniffly.app/Contents/MacOS/sniffly
```

#### 3. Create Info.plist

Create `Sniffly.app/Contents/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>sniffly</string>
    <key>CFBundleIdentifier</key>
    <string>org.fortrangoingonforty.sniffly</string>
    <key>CFBundleName</key>
    <string>Sniffly</string>
    <key>CFBundleDisplayName</key>
    <string>Sniffly</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>SNIF</string>
    <key>CFBundleIconFile</key>
    <string>sniffly</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
</dict>
</plist>
```

#### 4. Create an Application Icon

You need a `.icns` file. Create one from a PNG using:

```bash
# Create iconset directory
mkdir sniffly.iconset

# Create different sizes (you'll need a source image)
# 16x16, 32x32, 128x128, 256x256, 512x512, 1024x1024
sips -z 16 16     icon-1024.png --out sniffly.iconset/icon_16x16.png
sips -z 32 32     icon-1024.png --out sniffly.iconset/icon_16x16@2x.png
sips -z 32 32     icon-1024.png --out sniffly.iconset/icon_32x32.png
sips -z 64 64     icon-1024.png --out sniffly.iconset/icon_32x32@2x.png
sips -z 128 128   icon-1024.png --out sniffly.iconset/icon_128x128.png
sips -z 256 256   icon-1024.png --out sniffly.iconset/icon_128x128@2x.png
sips -z 256 256   icon-1024.png --out sniffly.iconset/icon_256x256.png
sips -z 512 512   icon-1024.png --out sniffly.iconset/icon_256x256@2x.png
sips -z 512 512   icon-1024.png --out sniffly.iconset/icon_512x512.png
sips -z 1024 1024 icon-1024.png --out sniffly.iconset/icon_512x512@2x.png

# Convert to .icns
iconutil -c icns sniffly.iconset -o Sniffly.app/Contents/Resources/sniffly.icns
```

#### 5. Bundle GTK4 Libraries

This is the tricky part! The app needs GTK4 libraries. You have two options:

**Option A: Use Homebrew's GTK4 (requires user to have GTK4 installed)**
```bash
# User must run: brew install gtk4
# Then the app will find libraries via dylib search paths
```

**Option B: Bundle libraries (recommended for distribution)**

```bash
# Copy GTK4 libraries into the bundle
cp -r /opt/homebrew/lib/libgtk-4*.dylib Sniffly.app/Contents/Frameworks/
cp -r /opt/homebrew/lib/libglib-2.0*.dylib Sniffly.app/Contents/Frameworks/
cp -r /opt/homebrew/lib/libgobject-2.0*.dylib Sniffly.app/Contents/Frameworks/
# ... and all other GTK4 dependencies

# Use install_name_tool to fix library paths
install_name_tool -change /opt/homebrew/lib/libgtk-4.dylib \
    @executable_path/../Frameworks/libgtk-4.dylib \
    Sniffly.app/Contents/MacOS/sniffly
```

**Better Option: Use `dylibbundler`**
```bash
# Install dylibbundler
brew install dylibbundler

# Automatically bundle all dependencies
dylibbundler -od -b \
    -x Sniffly.app/Contents/MacOS/sniffly \
    -d Sniffly.app/Contents/Frameworks/ \
    -p @executable_path/../Frameworks/
```

#### 6. Create the .dmg

```bash
# Create a temporary directory for DMG contents
mkdir dmg_temp
cp -r Sniffly.app dmg_temp/

# Optional: Create a symbolic link to /Applications for easy drag-install
ln -s /Applications dmg_temp/Applications

# Create the DMG
hdiutil create -volname "Sniffly" \
    -srcfolder dmg_temp \
    -ov -format UDZO \
    Sniffly-0.1.0-macOS.dmg

# Clean up
rm -rf dmg_temp
```

#### 7. Code Signing (Optional but Recommended)

```bash
# Sign the app (requires Apple Developer account)
codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: Your Name" \
    Sniffly.app

# Notarize with Apple (required for distribution outside App Store)
xcrun notarytool submit Sniffly-0.1.0-macOS.dmg \
    --apple-id "your@email.com" \
    --password "app-specific-password" \
    --team-id "YOUR_TEAM_ID" \
    --wait

# Staple the notarization ticket
xcrun stapler staple Sniffly-0.1.0-macOS.dmg
```

---

## Linux Packaging

### Option 1: AppImage (Recommended - Works on All Distros)

AppImage is a universal package format that works across all Linux distributions.

#### Create AppImage Structure

```bash
# Create AppDir structure
mkdir -p Sniffly.AppDir/usr/bin
mkdir -p Sniffly.AppDir/usr/lib
mkdir -p Sniffly.AppDir/usr/share/applications
mkdir -p Sniffly.AppDir/usr/share/icons/hicolor/256x256/apps

# Copy executable
cp build/sniffly Sniffly.AppDir/usr/bin/

# Copy icon
cp assets/sniffly.png Sniffly.AppDir/usr/share/icons/hicolor/256x256/apps/sniffly.png
cp assets/sniffly.png Sniffly.AppDir/sniffly.png

# Create .desktop file
cat > Sniffly.AppDir/sniffly.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Sniffly
Comment=Disk Space Analyzer
Exec=sniffly
Icon=sniffly
Categories=Utility;System;
Terminal=false
EOF

# Copy to required location
cp Sniffly.AppDir/sniffly.desktop Sniffly.AppDir/usr/share/applications/

# Create AppRun script
cat > Sniffly.AppDir/AppRun << 'EOF'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
export XDG_DATA_DIRS="${HERE}/usr/share:${XDG_DATA_DIRS}"
exec "${HERE}/usr/bin/sniffly" "$@"
EOF

chmod +x Sniffly.AppDir/AppRun

# Download appimagetool
wget https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x appimagetool-x86_64.AppImage

# Build AppImage
./appimagetool-x86_64.AppImage Sniffly.AppDir Sniffly-0.1.0-x86_64.AppImage
```

**Note**: AppImage requires GTK4 to be installed on the system. For a fully self-contained AppImage, you'd need to bundle GTK4 libraries.

### Option 2: Debian Package (.deb)

For Debian/Ubuntu users:

```bash
# Create package structure
mkdir -p sniffly-0.1.0/DEBIAN
mkdir -p sniffly-0.1.0/usr/bin
mkdir -p sniffly-0.1.0/usr/share/applications
mkdir -p sniffly-0.1.0/usr/share/icons/hicolor/256x256/apps

# Copy files
cp build/sniffly sniffly-0.1.0/usr/bin/
cp assets/sniffly.png sniffly-0.1.0/usr/share/icons/hicolor/256x256/apps/
cp assets/sniffly.desktop sniffly-0.1.0/usr/share/applications/

# Create control file
cat > sniffly-0.1.0/DEBIAN/control << 'EOF'
Package: sniffly
Version: 0.1.0
Section: utils
Priority: optional
Architecture: amd64
Depends: libgtk-4-1, libglib2.0-0
Maintainer: FortranGoingOnForty <your@email.com>
Description: Disk Space Analyzer
 A fast, beautiful disk space analyzer built with Fortran and GTK4.
 Visualizes disk usage with interactive treemaps.
EOF

# Build the package
dpkg-deb --build sniffly-0.1.0
```

### Option 3: RPM Package (Fedora/RedHat)

```bash
# Create RPM build directories
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Create spec file
cat > ~/rpmbuild/SPECS/sniffly.spec << 'EOF'
Name:           sniffly
Version:        0.1.0
Release:        1%{?dist}
Summary:        Disk Space Analyzer
License:        MIT
URL:            https://github.com/FortranGoingOnForty/sniffly
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  meson, gcc-gfortran, gtk4-devel
Requires:       gtk4

%description
A fast, beautiful disk space analyzer built with Fortran and GTK4.

%prep
%setup -q

%build
meson setup build
meson compile -C build

%install
install -Dm755 build/sniffly %{buildroot}%{_bindir}/sniffly
install -Dm644 assets/sniffly.desktop %{buildroot}%{_datadir}/applications/sniffly.desktop
install -Dm644 assets/sniffly.png %{buildroot}%{_datadir}/icons/hicolor/256x256/apps/sniffly.png

%files
%{_bindir}/sniffly
%{_datadir}/applications/sniffly.desktop
%{_datadir}/icons/hicolor/256x256/apps/sniffly.png

%changelog
* Mon Jan 01 2024 Your Name <your@email.com> - 0.1.0-1
- Initial release
EOF

# Create source tarball
tar czf ~/rpmbuild/SOURCES/sniffly-0.1.0.tar.gz ../sniffly/

# Build RPM
rpmbuild -ba ~/rpmbuild/SPECS/sniffly.spec
```

---

## Automated Packaging with CI/CD

### GitHub Actions Example

Create `.github/workflows/release.yml`:

```yaml
name: Release Build

on:
  push:
    tags:
      - 'v*'

jobs:
  build-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install dependencies
        run: |
          brew install meson gtk4 gcc
      - name: Build
        run: |
          meson setup build
          meson compile -C build
      - name: Create DMG
        run: |
          # Add DMG creation steps here
      - name: Upload Release Asset
        uses: actions/upload-artifact@v3
        with:
          name: Sniffly-macOS.dmg
          path: Sniffly-*.dmg

  build-linux:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y meson gfortran libgtk-4-dev
      - name: Build
        run: |
          meson setup build
          meson compile -C build
      - name: Create AppImage
        run: |
          # Add AppImage creation steps here
      - name: Upload Release Asset
        uses: actions/upload-artifact@v3
        with:
          name: Sniffly-Linux-x86_64.AppImage
          path: Sniffly-*.AppImage
```

---

## Quick Start Summary

### macOS
1. Build the app: `meson compile -C build`
2. Create .app bundle structure
3. Use `dylibbundler` to bundle GTK4 libraries
4. Create .dmg with `hdiutil`
5. (Optional) Code sign and notarize

**Result**: `Sniffly-0.1.0-macOS.dmg`

### Linux
1. Build the app: `meson compile -C build`
2. Create AppDir structure
3. Use `appimagetool` to create AppImage
4. Or create .deb/.rpm for specific distros

**Result**: `Sniffly-0.1.0-x86_64.AppImage` or `.deb`/`.rpm`

---

## Distribution Checklist

- [ ] Create application icon (1024x1024 PNG)
- [ ] Create .desktop file for Linux
- [ ] Test on clean system without development tools
- [ ] Document system requirements (GTK4, etc.)
- [ ] Add installation instructions to README
- [ ] Create GitHub releases page
- [ ] Consider Homebrew formula for macOS
- [ ] Consider Flatpak for Linux (alternative to AppImage)

---

## Notes on GTK4 Dependencies

Sniffly requires GTK4 at runtime. You have three options:

1. **User installation**: Require users to install GTK4 (`brew install gtk4` on macOS, `apt install libgtk-4-1` on Debian)
2. **Bundle libraries**: Include GTK4 in your app bundle (increases size ~100MB but works anywhere)
3. **Hybrid**: Bundle on macOS, rely on system packages on Linux

For the best user experience, option 2 (bundling) is recommended for macOS, while option 1 (system packages) works well for Linux where GTK4 is commonly available.

---

## Future Improvements

- **Flatpak**: Cross-distro sandboxed app (like macOS .app)
- **Snap**: Alternative Linux universal package
- **Homebrew Cask**: Easy installation on macOS (`brew install --cask sniffly`)
- **AUR Package**: For Arch Linux users
- **Windows**: Cross-compile with MinGW-w64 (if desired)
