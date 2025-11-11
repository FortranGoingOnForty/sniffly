# Installing Sniffly

Sniffly is a fast, visual disk space analyzer built with Fortran and GTK4.

## Installation Methods

### Option 1: Download DMG (Recommended)

1. Download the latest release: [Sniffly-0.2.4-macOS.dmg](https://github.com/FortranGoingOnForty/sniffly/releases/latest)
2. Open the DMG
3. Drag `Sniffly.app` to your Applications folder
4. **First launch:** Right-click Sniffly → "Open" → Click "Open" again to bypass Gatekeeper

### Option 2: Homebrew (For Brew Users)

```bash
# Install Sniffly (once we publish the cask)
# No dependencies needed - everything is bundled!
brew install --cask sniffly
```

### Option 3: Build from Source

```bash
# Install dependencies
brew install gtk4 gtk-4-fortran meson

# Clone and build
git clone https://github.com/FortranGoingOnForty/sniffly.git
cd sniffly
meson setup build --buildtype=release
meson compile -C build

# Run
./build/sniffly
```

## System Requirements

- macOS 11.0 or later
- Apple Silicon or Intel Mac

## Usage

### Launch from Applications
Double-click Sniffly in your Applications folder.

### Launch from Terminal
```bash
# Scan your home directory (default)
/Applications/Sniffly.app/Contents/MacOS/sniffly

# Scan a specific directory
/Applications/Sniffly.app/Contents/MacOS/sniffly ~/Documents

# Show help
/Applications/Sniffly.app/Contents/MacOS/sniffly --help

# Show version
/Applications/Sniffly.app/Contents/MacOS/sniffly --version
```

## Troubleshooting

### "Sniffly is damaged and can't be opened"

This happens because the app isn't signed with an Apple Developer certificate. To bypass:

**Method 1: Right-click to open**
1. Right-click (or Control-click) Sniffly.app
2. Click "Open"
3. Click "Open" again in the dialog

**Method 2: Remove quarantine attribute**
```bash
xattr -cr /Applications/Sniffly.app
```

### Window doesn't appear

If Sniffly starts but no window appears, try running from terminal to see debug output:
```bash
/Applications/Sniffly.app/Contents/MacOS/sniffly ~/Downloads
```

## Uninstalling

### DMG Installation
```bash
rm -rf /Applications/Sniffly.app
rm ~/Library/Logs/Sniffly.log
```

### Homebrew Installation
```bash
brew uninstall --cask sniffly
```
