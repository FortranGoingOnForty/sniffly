# Sniffly Development Notes

## 2025-11-04: gtk-fortran Installation on macOS ARM64

### Issue
gtk-fortran doesn't build cleanly on Apple Silicon (M2) due to `c_long_double` type not supported by gfortran on ARM64.

### Solution
1. Install dependencies:
   ```bash
   brew install meson ninja gfortran gtk4 pkg-config cmake
   ```

2. Clone and patch gtk-fortran:
   ```bash
   cd ~/Downloads
   git clone https://github.com/vmagnin/gtk-fortran.git
   cd gtk-fortran
   ```

3. Patch `src/glib-auto.f90` to comment out `c_long_double` usage:
   - Lines 5832-5845: Comment out `g_assertion_message_cmpnum` subroutine
   - This function is rarely used and not needed for Sniffly
   - Patched file saved as `glib-auto.f90.patched` for reference

4. Build with explicit flags to avoid ARM march issues:
   ```bash
   FC=gfortran cmake -B build \
     -DCMAKE_BUILD_TYPE=Release \
     -DEXCLUDE_PLPLOT=true \
     -DCMAKE_Fortran_FLAGS_RELEASE="-O3"

   cmake --build build
   sudo cmake --install build
   ```

5. Verify installation:
   ```bash
   pkg-config --modversion gtk-4-fortran
   # Should output: 4.8.0
   ```

### Result
gtk-fortran 4.8.0 installed successfully at `/usr/local/lib`

### References
- gtk-fortran repo: https://github.com/vmagnin/gtk-fortran
- Issue tracker: Known ARM64 compatibility issue
- Patched file: See `glib-auto.f90.patched` in this directory
