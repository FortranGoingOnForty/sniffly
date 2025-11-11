# Sniffly macOS Packaging Walkthrough

This is a step-by-step guide to package Sniffly for macOS distribution.

## Prerequisites

Before starting, make sure you have:
- ✅ Sniffly built successfully (`./build/sniffly` exists)
- ✅ `dylibbundler` installed: `brew install dylibbundler`
- ✅ An application icon (optional, but recommended)
- 📝 Apple Developer account (only needed for code signing)

## Version Management

The version is controlled by a single `VERSION` file at the project root. To release a new version:

```bash
echo "0.3.0" > VERSION
meson setup build --reconfigure
meson compile -C build
```

The version automatically appears in:
- The binary output (`./build/sniffly --version`)
- Info.plist in the app bundle
- The DMG filename

## Quick Start: Automated Packaging

```bash
# One command to create the .app and .dmg
./scripts/package-macos.sh
```

This creates:
- `Sniffly.app` - The application bundle
- `Sniffly-0.2.0-macOS.dmg` - Distributable installer

### What The Script Does

1. Reads version from `VERSION` file
2. Creates `.app` bundle structure
3. Copies the executable
4. Creates `Info.plist` with version info
5. Bundles GTK4 libraries using `dylibbundler`
6. Creates a distributable DMG

## Step-by-Step Manual Process

If you want to understand what's happening or customize the process:

### Step 1: Build the Release Binary

```bash
# Clean build for release
rm -rf build
meson setup build --buildtype=release
meson compile -C build

# Verify it works
./build/sniffly --version
```

### Step 2: Create the App Bundle Structure

```bash
mkdir -p Sniffly.app/Contents/MacOS
mkdir -p Sniffly.app/Contents/Resources
mkdir -p Sniffly.app/Contents/Frameworks
```

### Step 3: Copy the Executable

```bash
cp build/sniffly Sniffly.app/Contents/MacOS/sniffly
chmod +x Sniffly.app/Contents/MacOS/sniffly
```

### Step 4: Create Info.plist

```bash
cat > Sniffly.app/Contents/Info.plist << 'EOF'
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
    <string>0.2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>sniffly</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
EOF
```

### Step 5: Add an Icon (Optional but Recommended)

You need a `.icns` file. If you have a 1024x1024 PNG:

```bash
# Create iconset directory
mkdir sniffly.iconset

# Generate all sizes
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

# Cleanup
rm -rf sniffly.iconset
```

### Step 6: Bundle GTK4 Libraries

This is the crucial step that makes your app "just work" on any Mac:

```bash
dylibbundler -od -b \
    -x Sniffly.app/Contents/MacOS/sniffly \
    -d Sniffly.app/Contents/Frameworks/ \
    -p @executable_path/../Frameworks/
```

What this does:
- Finds all dylib dependencies (GTK4, Cairo, GLib, etc.)
- Copies them into `Frameworks/`
- Rewrites the executable to look in `@executable_path/../Frameworks/`
- Makes the app fully self-contained

**Expected size**: ~100-150MB (GTK4 is big!)

### Step 7: Test the App Bundle

```bash
open Sniffly.app
```

If it works, you're ready to create the DMG!

### Step 8: Create the DMG

```bash
# Create temporary folder
mkdir dmg_temp
cp -r Sniffly.app dmg_temp/

# Add Applications folder shortcut
ln -s /Applications dmg_temp/Applications

# Create DMG
hdiutil create -volname "Sniffly" \
    -srcfolder dmg_temp \
    -ov -format UDZO \
    Sniffly-0.2.0-macOS.dmg

# Cleanup
rm -rf dmg_temp
```

## Code Signing (Optional but Recommended)

If you have an Apple Developer account:

```bash
# Sign the app
codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: Your Name (TEAM_ID)" \
    Sniffly.app

# Verify signature
codesign -dv Sniffly.app

# Create DMG from signed app
# (repeat Step 8 after signing)

# Notarize (required for distribution outside App Store)
xcrun notarytool submit Sniffly-0.2.0-macOS.dmg \
    --apple-id "your@email.com" \
    --password "app-specific-password" \
    --team-id "YOUR_TEAM_ID" \
    --wait

# Staple notarization ticket
xcrun stapler staple Sniffly-0.2.0-macOS.dmg
```

**Why sign and notarize?**
- Without: Users see "unidentified developer" warning
- With: Clean installation experience, no warnings

**Cost**: $99/year for Apple Developer account

## Distribution

Once you have `Sniffly-0.2.0-macOS.dmg`:

1. **Test on a clean Mac** (or VM) without development tools installed
2. **Upload to your server**:
   ```bash
   scp Sniffly-0.2.0-macOS.dmg user@yourserver.com:/var/www/downloads/
   ```
3. **Create a download page** with:
   - Link to the DMG
   - System requirements (macOS 11.0+)
   - Installation instructions
   - Screenshot/demo

### Example Download Page

```html
<!DOCTYPE html>
<html>
<head>
    <title>Download Sniffly</title>
</head>
<body>
    <h1>Download Sniffly v0.2.0</h1>
    <p>A fast, visual disk space analyzer for macOS</p>

    <a href="Sniffly-0.2.0-macOS.dmg" class="download-button">
        Download for macOS (150 MB)
    </a>

    <h2>Requirements</h2>
    <ul>
        <li>macOS 11.0 (Big Sur) or later</li>
        <li>Apple Silicon or Intel processor</li>
    </ul>

    <h2>Installation</h2>
    <ol>
        <li>Download Sniffly-0.2.0-macOS.dmg</li>
        <li>Open the DMG file</li>
        <li>Drag Sniffly to Applications folder</li>
        <li>Launch from Applications</li>
    </ol>
</body>
</html>
```

## Release Checklist

Before releasing a new version:

- [ ] Update `VERSION` file
- [ ] Test on clean macOS installation
- [ ] Verify `--version` shows correct version
- [ ] Test basic functionality (scan, navigation, etc.)
- [ ] Build release binary (`--buildtype=release`)
- [ ] Bundle GTK4 libraries with dylibbundler
- [ ] Test app bundle works standalone
- [ ] Create DMG
- [ ] (Optional) Code sign and notarize
- [ ] Upload to distribution server
- [ ] Update download page
- [ ] Announce release (social media, website, etc.)

## Troubleshooting

### "Sniffly is damaged and can't be opened"

This happens when macOS quarantines unsigned apps. Users can bypass with:
```bash
xattr -cr /Applications/Sniffly.app
```

Or you need to code sign and notarize the app.

### App crashes immediately

- Check if GTK4 libraries are bundled: `ls Sniffly.app/Contents/Frameworks/`
- Should see many `.dylib` files
- Verify with: `otool -L Sniffly.app/Contents/MacOS/sniffly`
  - Should show `@executable_path/../Frameworks/` paths

### DMG too large (>200MB)

Normal! GTK4 is big. Options:
- Accept it (users download once)
- Require system GTK4 (smaller DMG, but users must `brew install gtk4`)

### Can't sign the app

You need an Apple Developer account ($99/year). For free distribution:
- Skip signing (users will see warning)
- Document how to bypass Gatekeeper

## Version Number Advice

You asked about version numbering. Here's my take:

**Current State of Sniffly (0.2.0 suggestion)**:
- ✅ Core functionality works (scanning, treemap, navigation)
- ✅ Progressive scanning is solid
- ✅ 3D effects, navigation locking
- ⚠️ Some rough edges (had bugs we fixed)
- ⚠️ No installers yet (this guide creates them)
- ❌ Not feature-complete vs original SpaceSniffer

**Version recommendations**:
- **0.1.0** - Tech preview, barely works
- **0.2.0** - Alpha release (current state) ← **I recommend this**
- **0.5.0** - Beta release (feature complete, but bugs)
- **0.9.0** - Release candidate
- **1.0.0** - Stable, production-ready

**Why 0.2.0?**
- Shows progress from initial experiments
- Sets expectations (alpha quality)
- Room to grow before 1.0
- Conservative (you prefer this)

**Semantic versioning for future**:
- `0.x.y` - Pre-1.0 development
- `1.0.0` - First stable release
- `1.1.0` - Add features (backwards compatible)
- `1.0.1` - Bug fixes
- `2.0.0` - Breaking changes

## Next Steps

After successful macOS packaging, consider:
- Linux AppImage (simpler than .deb/.rpm)
- Homebrew cask formula (`brew install --cask sniffly`)
- Automatic updates (Sparkle framework)
- Analytics (crash reporting, usage stats)
- Website with documentation

---

**Questions?** The packaging script at `scripts/package-macos.sh` automates all of this!
