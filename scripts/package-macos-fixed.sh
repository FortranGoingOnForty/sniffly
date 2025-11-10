#!/bin/bash
# Sniffly macOS Packaging Script - Fixed for GTK4 resources
# Creates a fully standalone .app bundle and .dmg

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Sniffly macOS Packaging (Fixed)${NC}"
echo -e "${BLUE}========================================${NC}"

# Read version
VERSION=$(cat VERSION)
echo -e "${GREEN}Version: ${VERSION}${NC}"

# Check build
if [ ! -f "build/sniffly" ]; then
    echo -e "${RED}ERROR: build/sniffly not found${NC}"
    exit 1
fi

# Clean old bundle
APP_NAME="Sniffly"
APP_BUNDLE="${APP_NAME}.app"
rm -rf "${APP_BUNDLE}"

# Create structure
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
FRAMEWORKS="${CONTENTS}/Frameworks"

echo -e "${BLUE}Step 1: Creating bundle structure...${NC}"
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"
mkdir -p "${FRAMEWORKS}"

# Copy binary (rename to -bin, we'll create a launcher)
echo -e "${BLUE}Step 2: Copying executable...${NC}"
cp build/sniffly "${MACOS}/sniffly-bin"
chmod +x "${MACOS}/sniffly-bin"

# Create launcher script
echo -e "${BLUE}Step 3: Creating launcher script...${NC}"
cat > "${MACOS}/sniffly" << 'EOF'
#!/bin/bash
# Sniffly launcher - sets up GTK4 environment

# Get the app bundle path
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUNDLE_DIR="$(dirname "$(dirname "$DIR")")"
RESOURCES_DIR="${BUNDLE_DIR}/Contents/Resources"

# Set GTK4 environment variables
export GSETTINGS_SCHEMA_DIR="${RESOURCES_DIR}/share/glib-2.0/schemas"
export GTK_DATA_PREFIX="${RESOURCES_DIR}"
export GTK_EXE_PREFIX="${RESOURCES_DIR}"
export GTK_PATH="${RESOURCES_DIR}"
export XDG_DATA_DIRS="${RESOURCES_DIR}/share:${XDG_DATA_DIRS:-}"

# Run the actual binary with all arguments
exec "${DIR}/sniffly-bin" "$@"
EOF
chmod +x "${MACOS}/sniffly"

# Create Info.plist
echo -e "${BLUE}Step 4: Creating Info.plist...${NC}"
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
</dict>
</plist>
EOF

# Bundle GTK4 resources
echo -e "${BLUE}Step 5: Bundling GTK4 resources...${NC}"
mkdir -p "${RESOURCES}/share/glib-2.0/schemas"
mkdir -p "${RESOURCES}/share/gtk-4.0"

# Copy GLib schemas
if [ -d "/opt/homebrew/share/glib-2.0/schemas" ]; then
    echo "  Copying GLib schemas..."
    cp -r /opt/homebrew/share/glib-2.0/schemas/* "${RESOURCES}/share/glib-2.0/schemas/"
fi

# Copy GTK4 data
if [ -d "/opt/homebrew/share/gtk-4.0" ]; then
    echo "  Copying GTK4 data..."
    cp -r /opt/homebrew/share/gtk-4.0/* "${RESOURCES}/share/gtk-4.0/"
fi

# Bundle libraries
echo -e "${BLUE}Step 6: Bundling libraries...${NC}"
./scripts/bundle-libs.sh

# Create PkgInfo
echo -n "APPLSNIF" > "${CONTENTS}/PkgInfo"

# Verify
echo -e "${BLUE}Step 7: Verifying bundle...${NC}"
if [ -f "${MACOS}/sniffly" ] && [ -f "${MACOS}/sniffly-bin" ]; then
    echo -e "${GREEN}✓ App bundle created successfully${NC}"
else
    echo -e "${RED}ERROR: Bundle creation failed${NC}"
    exit 1
fi

# Create DMG
echo -e "${BLUE}Step 8: Creating DMG...${NC}"
DMG_NAME="Sniffly-${VERSION}-macOS.dmg"
DMG_TEMP="dmg_temp"

rm -rf "${DMG_TEMP}"
mkdir -p "${DMG_TEMP}"
cp -r "${APP_BUNDLE}" "${DMG_TEMP}/"
ln -s /Applications "${DMG_TEMP}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${DMG_NAME}"

rm -rf "${DMG_TEMP}"

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
echo -e "  1. Test: open ${APP_BUNDLE}"
echo -e "  2. Test DMG: open ${DMG_NAME}"
echo ""
