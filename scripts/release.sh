#!/bin/bash
# Complete Sniffly Release Process
# Creates both ZIP (for Homebrew cask) and DMG (for manual download)

set -e  # Exit on error (except where we explicitly handle it)

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

VERSION=$(cat VERSION)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Sniffly Release Builder v${VERSION}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Build release binary
echo -e "${BLUE}Step 1: Building release binary...${NC}"
meson setup build --buildtype=release --wipe || meson setup build --buildtype=release
meson compile -C build
echo -e "${GREEN}✓ Binary built${NC}"
echo ""

# Step 2: Create .app bundle
echo -e "${BLUE}Step 2: Creating .app bundle...${NC}"
# Allow the packaging script to fail (library bundling may hit Mach-O header limits)
./scripts/package-macos-fixed.sh || echo -e "${YELLOW}Warning: Packaging had some issues, continuing anyway...${NC}"

# Re-sign the app to fix any signature issues
echo -e "${BLUE}Re-signing app bundle...${NC}"
codesign --force --deep --sign - Sniffly.app 2>&1 || echo "Signing warnings (can be ignored)"
echo -e "${GREEN}✓ App bundle created${NC}"
echo ""

# Step 3: Create DMG for manual download
echo -e "${BLUE}Step 3: Creating DMG for manual download...${NC}"
DMG_NAME="Sniffly-${VERSION}-macOS.dmg"
DMG_TEMP="dmg_temp"
rm -rf "${DMG_TEMP}" "${DMG_NAME}"
mkdir -p "${DMG_TEMP}"
cp -r Sniffly.app "${DMG_TEMP}/"
ln -s /Applications "${DMG_TEMP}/Applications"
hdiutil create -volname "Sniffly" -srcfolder "${DMG_TEMP}" -ov -format UDZO "${DMG_NAME}"
rm -rf "${DMG_TEMP}"
DMG_SIZE=$(du -h "${DMG_NAME}" | cut -f1)
echo -e "${GREEN}✓ DMG created: ${DMG_NAME} (${DMG_SIZE})${NC}"
echo ""

# Step 4: Create ZIP for Homebrew cask
echo -e "${BLUE}Step 4: Creating ZIP for Homebrew cask...${NC}"
ZIP_NAME="Sniffly-${VERSION}-macOS.zip"
rm -f "${ZIP_NAME}"
ditto -c -k --sequesterRsrc --keepParent Sniffly.app "${ZIP_NAME}"
ZIP_SIZE=$(du -h "${ZIP_NAME}" | cut -f1)
echo -e "${GREEN}✓ ZIP created: ${ZIP_NAME} (${ZIP_SIZE})${NC}"
echo ""

# Step 5: Calculate SHA256 for cask
echo -e "${BLUE}Step 5: Calculating SHA256 for Homebrew cask...${NC}"
SHA256=$(shasum -a 256 "${ZIP_NAME}" | awk '{print $1}')
echo -e "${GREEN}SHA256: ${SHA256}${NC}"
echo ""

# Summary
DMG_NAME="Sniffly-${VERSION}-macOS.dmg"
DMG_SIZE=$(du -h "${DMG_NAME}" | cut -f1)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Release ${VERSION} Ready!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Files created:${NC}"
echo -e "  1. ${ZIP_NAME} (${ZIP_SIZE}) - For Homebrew cask"
echo -e "  2. ${DMG_NAME} (${DMG_SIZE}) - For manual download"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. Create GitHub release: https://github.com/FortranGoingOnForty/sniffly/releases/new"
echo -e "  2. Tag: v${VERSION}"
echo -e "  3. Upload BOTH files: ${ZIP_NAME} and ${DMG_NAME}"
echo -e "  4. Update cask file with:"
echo ""
echo -e "${YELLOW}     version \"${VERSION}\"${NC}"
echo -e "${YELLOW}     sha256 \"${SHA256}\"${NC}"
echo ""
echo -e "  5. Commit and push cask changes"
echo ""
