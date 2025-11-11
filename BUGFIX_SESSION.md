# Bug Fix Session - UI Issues

## Issues to Fix

### 1. Eye Button (Toggle Dotfiles) Not Working
**Status**: ✅ FIXED
**Description**: Clicking the eye button to toggle dotfiles visibility doesn't affect rendering. Testing in a project with `.git` - the `.git` directory doesn't appear/disappear when toggled.

**Expected Behavior**:
- Eye button ON → show `.git`, `.cache`, `.config`, etc.
- Eye button OFF → hide all dotfiles

**Files Modified**:
- `src/core/progressive_scanner.f90` - Added `show_hidden_files` flag and filtering logic
- `src/rendering/treemap_renderer.f90` - Updated `toggle_hidden_files()` to call both scanner modules

**Solution**: Added hidden file filtering to progressive scanner at all depth levels (depth 0 and depth > 0). The toggle now properly filters files starting with '.' during scanning.

---

### 2. Collapsed Path in File Selector
**Status**: ✅ FIXED
**Description**: When opening with `./build/sniffly .` the file selector shows `.` instead of the full absolute path.

**Expected Behavior**:
- Command: `./build/sniffly .`
- File selector should show: `/Users/matthewwolffe/Documents/GithubOrgs/FortranGoingOnForty/sniffly`
- Not: `.`

**Files Modified**:
- `app/main.f90` - Added `get_absolute_path()` call to expand relative paths

**Solution**: Modified main.f90 to call `get_absolute_path()` on the command-line argument before passing it to `sniffly_set_scan_path()`. This expands `.` to the full absolute path.

---

### 3. Toggle Flat/3D Rendering Mode Does Nothing
**Status**: ✅ FIXED
**Description**: The toggle flat/3D rendering button doesn't appear to change the visualization at all.

**Expected Behavior**:
- Flat mode → Simple colored rectangles
- 3D/Cushion mode → Shaded rectangles with depth effect

**Files Modified**:
- `src/rendering/treemap_renderer.f90` - Enhanced cushion shading parameters for more visible 3D effect

**Solution**: The toggle was working correctly, but the 3D cushion effect was too subtle to notice. Increased the ridge height factor from 0.5 to 2.0 and adjusted lighting (ambient from 0.4 to 0.3, diffuse from 0.6 to 0.7) to make the 3D effect much more pronounced and visually obvious.

---

## Progress Tracking

- [x] Issue 1: Fix dotfiles toggle ✅
- [x] Issue 2: Fix collapsed path display ✅
- [x] Issue 3: Fix flat/3D rendering toggle ✅

## Summary

All three UI issues have been fixed:

1. **Eye button** - Now properly filters dotfiles in progressive scanner
2. **Path display** - Now shows full absolute paths instead of relative paths
3. **Render mode toggle** - Enhanced cushion shading for clearly visible 3D effect
