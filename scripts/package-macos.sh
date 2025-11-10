#!/bin/bash
# Sniffly macOS Packaging Script
# Creates a .app bundle and .dmg for distribution
#
# Usage: ./scripts/package-macos.sh

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Sniffly macOS Packaging Script${NC}"
echo -e "${BLUE}========================================${NC}"

# Read version from VERSION file
if [ ! -f "VERSION" ]; then
    echo -e "${RED}ERROR: VERSION file not found${NC}"
    exit 1
fi

VERSION=$(cat VERSION)
echo -e "${GREEN}Version: ${VERSION}${NC}"

# Check if build exists
if [ ! -f "build/sniffly" ]; then
    echo -e "${RED}ERROR: build/sniffly not found. Run 'meson compile -C build' first${NC}"
    exit 1
fi

# Create app bundle structure
APP_NAME="Sniffly"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
FRAMEWORKS="${CONTENTS}/Frameworks"

echo -e "${BLUE}Step 1: Creating app bundle structure...${NC}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"
mkdir -p "${FRAMEWORKS}"

# Copy executable directly - no library bundling needed
echo -e "${BLUE}Step 2: Copying executable...${NC}"
cp build/sniffly "${MACOS}/sniffly"
chmod +x "${MACOS}/sniffly"

# Create Info.plist
echo -e "${BLUE}Step 3: Creating Info.plist...${NC}"
cat > "${CONTENTS}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>sniffly</string>
    <key>CFBundleIdentifier</key>
    <string>org.fortrangoingonforty.sniffly</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
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
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Check for icon file
echo -e "${BLUE}Step 4: Checking for icon...${NC}"
if [ -f "assets/sniffly.icns" ]; then
    echo -e "${GREEN}Found icon file, copying...${NC}"
    cp assets/sniffly.icns "${RESOURCES}/sniffly.icns"
else
    echo -e "${RED}WARNING: No icon file found at assets/sniffly.icns${NC}"
    echo -e "${RED}         App will use default icon${NC}"
fi

# Bundle GTK4 libraries manually (simple approach)
echo -e "${BLUE}Step 5: Bundling GTK4 libraries...${NC}"
if [ -f "./scripts/simple-bundle.sh" ]; then
    ./scripts/simple-bundle.sh
else
    echo -e "${RED}ERROR: simple-bundle.sh not found${NC}"
    exit 1
fi

# Create PkgInfo file
echo -e "${BLUE}Step 6: Creating PkgInfo...${NC}"
echo -n "APPLSNIF" > "${CONTENTS}/PkgInfo"

# Verify app bundle
echo -e "${BLUE}Step 7: Verifying app bundle...${NC}"
if [ -f "${MACOS}/sniffly" ] && [ -f "${CONTENTS}/Info.plist" ]; then
    echo -e "${GREEN}✓ App bundle created successfully${NC}"
else
    echo -e "${RED}ERROR: App bundle creation failed${NC}"
    exit 1
fi

# Create DMG
echo -e "${BLUE}Step 8: Creating DMG...${NC}"
DMG_NAME="Sniffly-${VERSION}-macOS.dmg"
DMG_TEMP="dmg_temp"

rm -rf "${DMG_TEMP}"
mkdir -p "${DMG_TEMP}"

# Copy app bundle
cp -r "${APP_BUNDLE}" "${DMG_TEMP}/"

# Create symbolic link to Applications folder
ln -s /Applications "${DMG_TEMP}/Applications"

# Optional: Add background and custom window settings
# (requires additional tools like create-dmg)

# Create the DMG
echo -e "${GREEN}Creating ${DMG_NAME}...${NC}"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${DMG_NAME}"

# Clean up
rm -rf "${DMG_TEMP}"

# Get DMG size
DMG_SIZE=$(du -h "${DMG_NAME}" | cut -f1)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Packaging complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Output files:${NC}"
echo -e "  App Bundle: ${APP_BUNDLE}"
echo -e "  DMG:        ${DMG_NAME} (${DMG_SIZE})"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. Test the app: open ${APP_BUNDLE}"
echo -e "  2. Test the DMG: open ${DMG_NAME}"
echo -e "  3. Upload ${DMG_NAME} to your distribution server"
echo ""

# Optional: Code signing check
if command -v codesign &> /dev/null; then
    echo -e "${BLUE}Code Signing Status:${NC}"
    codesign -dv "${APP_BUNDLE}" 2>&1 | grep -E "Signature|TeamIdentifier" || echo "  Not signed"
    echo ""
    echo -e "${BLUE}To sign the app (requires Apple Developer account):${NC}"
    echo -e '  codesign --deep --force --sign "Developer ID Application: Your Name" Sniffly.app'
    echo ""
fi

echo -e "${GREEN}Done!${NC}"
