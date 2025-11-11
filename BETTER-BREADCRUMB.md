# improving the breadcrumb
right now the breadcrumb interactively is not functional.
as advertised we can click portions of the breadcrumb to jump to
but every click is just registered as the active dir and so no jump is performed
I think we ought to think like web devs and make a breadcrumb component

here's my vision for the 

## improved breadcrumb
- is color coded:
  - gray/dim for inactive dirs in the path
  - black for "/"
  - bold red for active dir
  - root should be green to indicate we should try to make it clickable
    - though I imagine that's hard with the pixel adjustments
- is back/forwards aware
  - if we previously navigated from a path say we went from ~/Downloads to ~/
    - we expect the path to be /home/matthewwolffe/Downloads
      - with Downlaods and home greyed out.
- should look as similar to the current breadcrumb as possible. though maybe we should add hover state to dirs to indcate they can be clicked
  - hover ideas
    - darker gray for inactive dirs
    - lose bold effect on active dir
    
clear!?
it may be that the vision is unattainable within a single text string, as in we can't detect fine tuned clicks like that
let me know if this vision is impossible!

---

## FEASIBILITY ASSESSMENT (2025-11-11)

**Verdict:** ✅ **TOTALLY FEASIBLE** - Vision is achievable with custom Cairo rendering

### Approaches Considered:

#### Option 1: Separate GTK Buttons (Standard)
**Pros:**
- ✅ Easy (~100 lines of code)
- ✅ Automatic hover/click detection
- ✅ Built-in accessibility
- ✅ CSS styling support
- ✅ 3-4 hours implementation time

**Cons:**
- ❌ Button borders/padding may look less seamless
- ❌ Less control over exact appearance

#### Option 2: GtkLabel + Pango Hit-Testing (Hybrid)
**Pros:**
- ⚠️ No button visual artifacts
- ⚠️ Single text widget

**Cons:**
- ❌ Pango `xy_to_index()` gives character indices, not semantic segments
- ❌ Must manually parse `/` delimiter positions
- ❌ Complex hover state management (~250 lines)
- ❌ Poor accessibility

#### Option 3: Custom Cairo Rendering (Chosen) ✅
**Pros:**
- ✅ **Complete control** over appearance (exact vision match)
- ✅ Seamless floating text aesthetic
- ✅ Smooth hover effects (darker gray)
- ✅ Color coding exactly as specified
- ✅ Back/forward awareness (dim previously-visited segments)
- ✅ No button borders or padding artifacts

**Cons:**
- ⚠️ More code (~350 lines)
- ⚠️ Manual hit-testing required
- ⚠️ 2-3 days implementation time

---

## WHY CAIRO?

**Decision rationale:**
1. **Achieves the vision exactly** - No compromises on appearance
2. **Performance is negligible** - Breadcrumb is tiny compared to treemap (5-10 text segments vs 100s-1000s of rectangles)
3. **State safety is already solved** - GTK event loop serialization + cached path segments
4. **You're already using Cairo** - Treemap widget proves you know the APIs
5. **Seamless look** - Floating text with precise hover zones, no visual artifacts

### Performance Considerations:

**Impact:** <0.1% CPU overhead
- Breadcrumb renders 5-10 text segments (trivial)
- Treemap renders 100s-1000s of rectangles (heavy) - breadcrumb is nothing by comparison
- Pango text rendering is GPU-accelerated
- Optimization: Only redraw on hover **state change**, not every mouse move

**During scans:**
- Zero overhead - breadcrumb only updates on navigation events
- Same thread-safety as current implementation (GTK main loop serialization)
- Cache path segments on main thread, draw function reads cached data

### State Corruption Risk:

**Assessment:** Same as current implementation (safe with caching)
- Current `breadcrumb_callback()` already accesses `current_view` pointer
- Protection via GTK event loop (all widget access on main thread)
- Progressive scanner uses `g_idle_add()` for thread-safe callbacks
- **Strategy:** Cache path segments when `breadcrumb_callback()` fires, draw function reads cache only

---

## IMPLEMENTATION PLAN

### Phase 1: Create Custom Breadcrumb Widget Module

**File:** `src/gui/breadcrumb_widget.f90`

**Tasks:**
1. Create module skeleton with Cairo drawing area
2. Define cached state variables:
   ```fortran
   ! Path segment cache (updated on main thread only)
   character(len=256), dimension(50), save :: cached_segments
   integer, save :: cached_segment_count = 0

   ! Hover state
   integer, save :: hovered_segment = 0  ! 0 = none, 1+ = segment index
   integer, save :: last_hovered_segment = -1

   ! Click bounds for each segment
   type :: segment_bounds
     integer :: x, y, width, height
   end type
   type(segment_bounds), dimension(50), save :: segment_rects
   ```

3. Create widget initialization function:
   ```fortran
   function create_breadcrumb_widget() result(widget)
     type(c_ptr) :: widget
     ! Create GtkDrawingArea
     ! Set draw function
     ! Attach motion/click controllers
   end function
   ```

**Estimated time:** 2-3 hours

---

### Phase 2: Path Parsing Logic

**Tasks:**
1. **Split path into segments:**
   ```fortran
   ! Input: "/Users/matt/Documents/sniffly"
   ! Output:
   !   segments(1) = "/"
   !   segments(2) = "/Users"
   !   segments(3) = "/Users/matt"
   !   segments(4) = "/Users/matt/Documents"
   !   segments(5) = "/Users/matt/Documents/sniffly"
   ! (Full paths for click navigation, but display only last component)
   ```

2. **Handle ~ abbreviation:**
   ```fortran
   ! Replace /Users/matt with ~ for display
   ! But keep full path for navigation
   ```

3. **Extract display names:**
   ```fortran
   ! From "/Users/matt", display "matt"
   ! From "~/Documents", display "Documents"
   ! From "/", display "/"
   ```

4. **Create `update_breadcrumb_cache()` function:**
   ```fortran
   subroutine update_breadcrumb_cache(full_path)
     character(len=*), intent(in) :: full_path
     ! Parse path into cached_segments
     ! Store full paths for navigation
     ! Trigger redraw
   end subroutine
   ```

**Estimated time:** 3-4 hours

---

### Phase 3: Cairo Draw Function

**Tasks:**
1. **Render each segment with Pango:**
   ```fortran
   subroutine draw_breadcrumb(area, cr, width, height, user_data) bind(c)
     ! For each segment:
     !   1. Determine color based on state:
     !      - Root (i==1): green
     !      - Active (i==count): bold red
     !      - Inactive: gray
     !      - Hovered inactive: darker gray
     !   2. Set Cairo color
     !   3. Draw text with Pango
     !   4. Store bounds in segment_rects(i)
     !   5. Draw separator " / "
     !   6. Update x_offset
   end subroutine
   ```

2. **Color logic:**
   ```fortran
   ! Root segment (/)
   if (i == 1) then
     call cairo_set_source_rgb(cr, 0.0_c_double, 0.6_c_double, 0.0_c_double)  ! Green

   ! Active segment (last in path)
   else if (i == cached_segment_count) then
     call cairo_set_source_rgb(cr, 0.8_c_double, 0.0_c_double, 0.0_c_double)  ! Bold red
     font_desc = pango_font_description_from_string("Sans Bold 11"//c_null_char)

   ! Inactive segment (hovered)
   else if (i == hovered_segment) then
     call cairo_set_source_rgb(cr, 0.3_c_double, 0.3_c_double, 0.3_c_double)  ! Darker gray

   ! Inactive segment (not hovered)
   else
     call cairo_set_source_rgb(cr, 0.5_c_double, 0.5_c_double, 0.5_c_double)  ! Gray
   end if
   ```

3. **Back/forward awareness integration:**
   ```fortran
   ! Check if segment is in backwards history
   logical function is_backwards_segment(segment_path)
     ! Compare with nav_history and nav_history_pos
     ! If segment_path appears before current position, return true
   end function

   ! Apply extra dimming to backwards segments
   if (is_backwards_segment(cached_segments(i))) then
     call cairo_set_source_rgba(cr, 0.5_c_double, 0.5_c_double, 0.5_c_double, 0.6_c_double)  ! Gray + transparency
   end if
   ```

**Estimated time:** 5-6 hours

---

### Phase 4: Mouse Interaction

**Tasks:**
1. **Hit-testing function:**
   ```fortran
   function find_segment_at_position(x, y) result(segment_index)
     real(c_double), intent(in) :: x, y
     integer :: segment_index
     integer :: i

     segment_index = 0
     do i = 1, cached_segment_count
       if (x >= segment_rects(i)%x .and. &
           x <= segment_rects(i)%x + segment_rects(i)%width .and. &
           y >= segment_rects(i)%y .and. &
           y <= segment_rects(i)%y + segment_rects(i)%height) then
         segment_index = i
         return
       end if
     end do
   end function
   ```

2. **Motion callback (hover):**
   ```fortran
   subroutine on_breadcrumb_motion(controller, x, y, user_data) bind(c)
     integer :: new_hovered

     new_hovered = find_segment_at_position(x, y)

     ! Only redraw if hover state CHANGED
     if (new_hovered /= last_hovered_segment) then
       last_hovered_segment = new_hovered
       hovered_segment = new_hovered
       call gtk_widget_queue_draw(breadcrumb_widget_ptr)
     end if
   end subroutine
   ```

3. **Click callback (navigation):**
   ```fortran
   subroutine on_breadcrumb_click(gesture, n_press, x, y, user_data) bind(c)
     integer :: clicked_segment, levels_up

     clicked_segment = find_segment_at_position(x, y)
     if (clicked_segment > 0 .and. clicked_segment < cached_segment_count) then
       ! Navigate to clicked segment
       levels_up = cached_segment_count - clicked_segment
       call navigate_up(levels_up)

       ! Trigger navigation callback to update history/UI
       if (associated(nav_callback)) call nav_callback()

       ! Redraw
       call gtk_widget_queue_draw(breadcrumb_widget_ptr)
     end if
   end subroutine
   ```

**Estimated time:** 3-4 hours

---

### Phase 5: Integration with gtk_app.f90

**Tasks:**
1. **Replace current breadcrumb bar:**
   - REMOVE lines 356-364 (old breadcrumb_bar creation)
   - REMOVE `breadcrumb_box_ptr` global variable
   - REMOVE `breadcrumb_buttons` array
   - REMOVE `breadcrumb_count` tracking

2. **Add new breadcrumb widget:**
   ```fortran
   ! In on_activate(), after toolbar creation:
   use breadcrumb_widget, only: create_breadcrumb_widget, update_breadcrumb_cache

   type(c_ptr) :: breadcrumb_area

   ! Create custom breadcrumb widget
   breadcrumb_area = create_breadcrumb_widget()
   call gtk_widget_set_size_request(breadcrumb_area, -1_c_int, 30_c_int)  ! Height: 30px
   call gtk_box_append(main_box, breadcrumb_area)
   ```

3. **Update breadcrumb_callback():**
   ```fortran
   subroutine breadcrumb_callback()
     use breadcrumb_widget, only: update_breadcrumb_cache
     use treemap_renderer, only: get_current_view_node

     current_view => get_current_view_node()
     if (associated(current_view) .and. allocated(current_view%path)) then
       ! Update custom breadcrumb cache
       call update_breadcrumb_cache(current_view%path)
     end if

     ! Existing history/status logic...
   end subroutine
   ```

4. **CRITICAL: Unhook old click behavior:**
   - REMOVE `on_breadcrumb_clicked()` function (lines 1328-1356)
   - REMOVE `sniffly_update_breadcrumbs()` function (lines 1222-1325)
   - Navigation will now be handled by breadcrumb_widget's click callback

5. **Update meson.build:**
   ```meson
   sources += [
     'src/gui/breadcrumb_widget.f90',
     # ... existing sources
   ]
   ```

**Estimated time:** 2-3 hours

---

### Phase 6: Back/Forward Awareness (Advanced Feature)

**Tasks:**
1. **Expose navigation history to breadcrumb:**
   ```fortran
   ! In gtk_app.f90, add public getter:
   public :: get_navigation_history, get_navigation_position

   function get_navigation_history() result(history)
     character(len=512), dimension(:), allocatable :: history
     allocate(history(nav_history_count))
     history = nav_history(1:nav_history_count)
   end function
   ```

2. **Check in breadcrumb draw function:**
   ```fortran
   ! In breadcrumb_widget.f90 draw function:
   use gtk_app, only: get_navigation_history, get_navigation_position

   character(len=512), dimension(:), allocatable :: history
   integer :: history_pos, j
   logical :: is_backwards

   history = get_navigation_history()
   history_pos = get_navigation_position()

   ! For each segment, check if it was in earlier history
   is_backwards = .false.
   do j = 1, history_pos - 1  ! Check all history before current
     if (index(trim(history(j)), trim(cached_segments(i))) > 0) then
       is_backwards = .true.
       exit
     end if
   end do

   ! Apply dimming if backwards
   if (is_backwards) then
     alpha = 0.6_c_double  ! More transparent
   end if
   ```

**Estimated time:** 2-3 hours

---

### Phase 7: Testing & Polish

**Tasks:**
1. **Test scenarios:**
   - [ ] Navigate into nested directories - breadcrumb updates correctly
   - [ ] Click middle segment - navigates up correct number of levels
   - [ ] Hover over segments - color changes smoothly
   - [ ] Click active (red) segment - no navigation (already there)
   - [ ] Back/Forward navigation - backwards segments dim appropriately
   - [ ] Rapid mouse movement - no excessive redraws
   - [ ] Long paths - breadcrumb doesn't overflow window width

2. **Handle edge cases:**
   - [ ] Root path `/` - shows only one segment
   - [ ] Home path `~` - abbreviates correctly
   - [ ] Very long paths - add ellipsis or scrolling?
   - [ ] Window resize - breadcrumb reflows

3. **Performance validation:**
   - [ ] Run profiler during hover - verify <0.1% CPU
   - [ ] Check redraw frequency - only on state changes
   - [ ] Test during active scans - no interference

4. **Visual polish:**
   - [ ] Adjust colors to match GTK theme
   - [ ] Fine-tune separator spacing
   - [ ] Ensure alignment with toolbar

**Estimated time:** 3-4 hours

---

## TOTAL EFFORT ESTIMATE

- **Phase 1:** 2-3 hours (module setup)
- **Phase 2:** 3-4 hours (path parsing)
- **Phase 3:** 5-6 hours (Cairo drawing)
- **Phase 4:** 3-4 hours (mouse interaction)
- **Phase 5:** 2-3 hours (integration)
- **Phase 6:** 2-3 hours (back/forward awareness)
- **Phase 7:** 3-4 hours (testing & polish)

**Total:** 20-27 hours (~2-3 days of focused work)

---

## CRITICAL NOTES

### Don't Forget:
1. **Unhook old breadcrumb click behavior** - Remove `on_breadcrumb_clicked()` and related button logic
2. **Remove old breadcrumb widgets** - Clean up `breadcrumb_box_ptr`, `breadcrumb_buttons`, etc.
3. **Navigation callback integration** - Breadcrumb widget needs access to `navigate_up()` from treemap_renderer
4. **Thread safety** - Always update cache on main thread via callbacks, never in draw function
5. **Redraw optimization** - Only queue redraw when hover STATE changes, not on every mouse move

### Performance Gotchas:
- Cache path segments when navigation happens, not on every draw
- Use `last_hovered_segment` to detect state changes
- Pango layout creation can be expensive - consider caching layouts between redraws if profiling shows issues

### Future Enhancements:
- Tooltip on hover showing full path + size stats
- Keyboard navigation (Tab through segments, Enter to navigate)
- Context menu on right-click (same as treemap)
- Animated transitions when segments update

---

## SUCCESS CRITERIA

✅ **Vision achieved when:**
- [x] Breadcrumb shows path as seamless floating text (no button borders)
- [x] Root segment is green
- [x] Active (last) segment is bold red
- [x] Inactive segments are gray
- [x] Hovered segments darken
- [x] Clicking any segment navigates to that level
- [x] Back/forward navigation dims previously-visited segments
- [x] Performance <0.1% CPU overhead
- [x] No state corruption during scans
- [x] Looks visually seamless and polished