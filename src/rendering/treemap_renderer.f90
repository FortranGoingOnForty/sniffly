! Treemap Renderer Module for Sniffly
! Coordinates scanning, layout calculation, and Cairo rendering
module treemap_renderer
  use, intrinsic :: iso_c_binding
  use types
  use disk_scanner, only: build_tree
  use progressive_scanner, only: start_progressive_scan, stop_progressive_scan, &
                                  is_scan_active, register_scan_update_callback, &
                                  register_scan_complete_callback, &
                                  register_initial_level_complete_callback
  use squarified_layout, only: calculate_treemap
  use cairo, only: cairo_set_source_rgb, cairo_rectangle, cairo_fill, &
                   cairo_stroke, cairo_set_line_width, cairo_select_font_face, &
                   cairo_set_font_size, cairo_move_to, cairo_line_to, cairo_show_text, &
                   cairo_set_source_rgba, cairo_text_extents
  use g, only: g_main_context_default, g_main_context_iteration
  use gtk, only: gtk_widget_queue_draw
  use iso_fortran_env, only: int64
  implicit none
  private

  public :: scan_and_render, init_renderer, get_root_node, scan_and_render_with_hover, &
            scan_and_render_with_interaction, find_node_at_position, navigate_into_node, &
            navigate_up, get_breadcrumb_path, get_path_depth, get_node_count, &
            get_node_center_by_index, find_node_in_direction, register_progress_callback, &
            scan_directory, invalidate_layout, get_current_view_node, remove_selected_node_from_view, &
            clear_cache, toggle_file_extensions, toggle_age_based_coloring, toggle_size_display_mode, &
            toggle_hidden_files, toggle_render_mode, set_redraw_widget, register_scan_completion_callback

  ! Callback interfaces for progress updates
  abstract interface
    subroutine show_progress_callback()
    end subroutine show_progress_callback

    subroutine hide_progress_callback()
    end subroutine hide_progress_callback

    subroutine update_progress_callback(fraction, message)
      use, intrinsic :: iso_c_binding
      real(c_double), intent(in) :: fraction
      character(len=*), intent(in) :: message
    end subroutine update_progress_callback

    subroutine scan_completion_callback()
    end subroutine scan_completion_callback
  end interface

  ! Directory cache entry
  type :: cache_entry
    character(len=512) :: path
    type(file_node), allocatable :: node
    logical :: valid
  end type cache_entry

  ! Global state
  type(file_node), save, target :: root_node
  type(file_node), pointer, save :: current_view_node => null()
  logical, save :: has_data = .false.
  character(len=512), save :: scanned_path = ""

  ! Directory cache (stores scanned trees)
  integer, parameter :: MAX_CACHE_SIZE = 50
  type(cache_entry), dimension(MAX_CACHE_SIZE), save :: dir_cache
  integer, save :: cache_count = 0

  ! Layout cache state
  logical, save :: layout_calculated = .false.
  integer, save :: last_width = 0, last_height = 0

  ! View settings (Phase 5 features)
  logical, save :: show_file_extensions = .true.     ! Toggle file extensions in labels
  logical, save :: use_age_based_coloring = .false.  ! Color by file age instead of type
  logical, save :: show_allocated_size = .false.     ! Show allocated size vs actual size
  logical, save :: show_hidden_files = .true.        ! Toggle visibility of dotfiles/hidden files
  logical, save :: use_cushion_shading = .true.      ! Toggle cushioned (3D) vs flat rendering

  ! Navigation path stack (for breadcrumbs)
  ! Simple approach: track path as array of names
  integer, parameter :: MAX_PATH_DEPTH = 100
  character(len=256), save :: path_names(MAX_PATH_DEPTH)
  integer, save :: path_depth = 0

  ! Progress callback pointers
  procedure(show_progress_callback), pointer, save :: show_progress_cb => null()
  procedure(hide_progress_callback), pointer, save :: hide_progress_cb => null()
  procedure(update_progress_callback), pointer, save :: update_progress_cb => null()
  procedure(scan_completion_callback), pointer, save :: scan_completion_cb => null()

  ! Widget pointer for progressive scan redraws
  type(c_ptr), save :: widget_for_redraw = c_null_ptr

contains

  ! Initialize renderer
  subroutine init_renderer()
    has_data = .false.
    scanned_path = ""
  end subroutine init_renderer

  ! Invalidate layout cache to force recalculation
  subroutine invalidate_layout()
    layout_calculated = .false.
    print *, "Layout cache invalidated"
  end subroutine invalidate_layout

  ! Register progress callbacks
  subroutine register_progress_callback(show_cb, hide_cb, update_cb)
    procedure(show_progress_callback) :: show_cb
    procedure(hide_progress_callback) :: hide_cb
    procedure(update_progress_callback) :: update_cb

    show_progress_cb => show_cb
    hide_progress_cb => hide_cb
    update_progress_cb => update_cb
    print *, "Progress callbacks registered"
  end subroutine register_progress_callback

  ! Set widget for progressive scan redraws
  subroutine set_redraw_widget(widget)
    type(c_ptr), intent(in) :: widget
    widget_for_redraw = widget
    print *, "Redraw widget registered for progressive scanning"
  end subroutine set_redraw_widget

  ! Callback for progressive scan updates (called after each directory is scanned)
  subroutine on_progressive_scan_update()
    use progressive_scanner, only: get_scan_progress
    real :: progress
    character(len=256) :: status_msg
    integer :: dirs_done, total_dirs

    ! Get progress from progressive scanner
    progress = get_scan_progress()

    ! Update progress bar and status
    if (associated(update_progress_cb)) then
      write(status_msg, '(A,F5.1,A)') 'Scanning directories... ', progress * 100.0, '%'
      call update_progress_cb(real(progress, c_double), trim(status_msg))
    end if

    ! Decay flash intensities for all visible nodes
    call decay_flash_highlights()

    ! Invalidate layout to force recalculation with new data
    call invalidate_layout()

    ! Trigger widget redraw if available
    if (c_associated(widget_for_redraw)) then
      call gtk_widget_queue_draw(widget_for_redraw)
    end if
  end subroutine on_progressive_scan_update

  ! Register scan completion callback
  subroutine register_scan_completion_callback(callback)
    procedure(scan_completion_callback) :: callback
    scan_completion_cb => callback
    print *, "Scan completion callback registered"
  end subroutine register_scan_completion_callback

  ! Callback for initial level completion (depth 0 done)
  subroutine on_initial_level_complete()
    print *, "Initial level complete - starting UI rendering (subdirectories will continue scanning)"

    ! Mark initial scan as complete so UI can start rendering
    if (associated(scan_completion_cb)) then
      call scan_completion_cb()
    end if

    ! Trigger first redraw (progress bar stays visible)
    if (c_associated(widget_for_redraw)) then
      call gtk_widget_queue_draw(widget_for_redraw)
    end if
  end subroutine on_initial_level_complete

  ! Callback for progressive scan completion (fully done)
  subroutine on_progressive_scan_complete()
    print *, "Progressive scan FULLY complete - hiding progress bar"

    ! Update progress to 100% and hide progress bar
    if (associated(update_progress_cb)) then
      call update_progress_cb(1.0_c_double, 'Scan complete')
    end if
    if (associated(hide_progress_cb)) then
      call hide_progress_cb()
    end if

    ! Final redraw
    if (c_associated(widget_for_redraw)) then
      call gtk_widget_queue_draw(widget_for_redraw)
    end if

    print *, "Scan complete. Final root size: ", root_node%size, " bytes"
  end subroutine on_progressive_scan_complete

  ! Get root node (for external access)
  function get_root_node() result(node_ptr)
    type(file_node), pointer :: node_ptr
    node_ptr => root_node
  end function get_root_node

  ! Get current view node (for external access)
  function get_current_view_node() result(node_ptr)
    type(file_node), pointer :: node_ptr
    node_ptr => current_view_node
  end function get_current_view_node

  ! Scan directory and prepare for rendering
  subroutine scan_directory(path)
    use, intrinsic :: iso_c_binding
    use disk_scanner, only: set_progress_callback
    use file_system, only: get_absolute_path
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: expanded_path
    integer :: cache_index, i
    character(len=512) :: status_msg
    type(c_ptr) :: context

    ! Expand relative paths (like ./) to absolute paths for meaningful breadcrumbs
    expanded_path = get_absolute_path(path)
    print *, "Scanning: ", trim(expanded_path)

    ! Mark as having data IMMEDIATELY to prevent recursive scans
    has_data = .true.
    scanned_path = trim(expanded_path)

    ! Register progress callback with disk_scanner
    if (associated(update_progress_cb)) then
      call set_progress_callback(update_progress_cb)
    end if

    ! Show progress bar and status
    if (associated(show_progress_cb)) call show_progress_cb()

    ! Process events to make widget visible
    context = g_main_context_default()
    do i = 1, 5
      do while (g_main_context_iteration(context, 0_c_int) /= 0_c_int)
      end do
    end do

    ! Now update with initial message
    write(status_msg, '(A,A)') 'Scanning: ', trim(expanded_path)
    if (associated(update_progress_cb)) call update_progress_cb(0.1_c_double, status_msg)

    ! Process events again to show the update
    do i = 1, 5
      do while (g_main_context_iteration(context, 0_c_int) /= 0_c_int)
      end do
    end do

    ! Check cache first
    cache_index = cache_lookup(expanded_path)
    if (cache_index > 0) then
      ! Use cached scan (already colored)
      if (associated(update_progress_cb)) call update_progress_cb(0.5_c_double, 'Loading from cache...')
      ! Process events
      do while (g_main_context_iteration(context, 0_c_int) /= 0_c_int)
      end do
      ! Deallocate old root_node before loading from cache
      call deallocate_tree(root_node)
      root_node = dir_cache(cache_index)%node  ! Deep copy from cache
      ! Apply colors to cached tree
      call color_tree(root_node, 0)
    else
      ! Use progressive scanning for real-time treemap updates
      if (associated(update_progress_cb)) call update_progress_cb(0.3_c_double, 'Starting progressive scan...')
      ! Process events
      do while (g_main_context_iteration(context, 0_c_int) /= 0_c_int)
      end do

      ! Register update callback for progressive scanning
      call register_scan_update_callback(on_progressive_scan_update)

      ! Register initial level completion callback
      call register_initial_level_complete_callback(on_initial_level_complete)

      ! Register full completion callback
      call register_scan_complete_callback(on_progressive_scan_complete)

      ! Start progressive scan - this will scan one directory per idle iteration
      call start_progressive_scan(root_node, expanded_path)

      print *, "Progressive scan started - updates will occur in idle callbacks"
      ! Note: The scan will continue asynchronously, calling on_progressive_scan_update
      ! after each directory is scanned. We don't cache during progressive scans.
      ! Progress bar will be updated by the progressive scanner
    end if

    ! Start view at root level (showing only top-level items)
    current_view_node => root_node

    ! Initialize breadcrumb path stack with root path
    path_depth = 1
    path_names(1) = trim(scanned_path)

    ! For cached scans, hide progress bar now since scan is complete
    if (cache_index > 0) then
      if (associated(update_progress_cb)) call update_progress_cb(1.0_c_double, 'Loaded from cache')
      if (associated(hide_progress_cb)) call hide_progress_cb()
      print *, "Scan complete (from cache). Root size: ", root_node%size, " bytes"
      print *, "Children: ", root_node%num_children
    else
      ! For progressive scans, keep progress bar visible - it will be updated during scan
      print *, "Progressive scan in progress. Root level complete with ", root_node%num_children, " children"
    end if

    ! Invalidate layout cache to force recalculation with new data
    call invalidate_layout()
  end subroutine scan_directory

  ! Main rendering function
  subroutine scan_and_render(cr, width, height, path)
    type(c_ptr), intent(in) :: cr
    integer(c_int), intent(in) :: width, height
    character(len=*), intent(in), optional :: path
    type(rect) :: bounds

    ! Scan if needed
    if (.not. has_data) then
      if (present(path)) then
        call scan_directory(path)
      else
        ! Default: scan Downloads folder
        call scan_directory("/Users/matthewwolffe/Downloads")
      end if
    end if

    ! Calculate layout for window size using current view
    bounds%x = 0
    bounds%y = 0
    bounds%width = int(width)
    bounds%height = int(height)

    if (associated(current_view_node) .and. current_view_node%size > 0) then
      call calculate_treemap(current_view_node, bounds)
      ! Initialize cushion parameters for 3D shading
      call init_cushions(current_view_node)
    end if

    ! Render only the current view (top-level items only)
    if (associated(current_view_node)) then
      call render_current_view(cr, current_view_node, bounds)
    end if
  end subroutine scan_and_render

  ! Rendering function with hover highlighting
  subroutine scan_and_render_with_hover(cr, width, height, mouse_x, mouse_y, path)
    type(c_ptr), intent(in) :: cr
    integer(c_int), intent(in) :: width, height
    real(c_double), intent(in) :: mouse_x, mouse_y
    character(len=*), intent(in), optional :: path
    type(rect) :: bounds
    integer :: hovered_index

    ! Scan if needed (only once)
    if (.not. has_data) then
      if (present(path)) then
        call scan_directory(path)
      else
        call scan_directory("/Users/matthewwolffe/Downloads")
      end if
    end if

    ! Only recalculate layout if window size changed
    if (.not. layout_calculated .or. last_width /= width .or. last_height /= height) then
      bounds%x = 0
      bounds%y = 0
      bounds%width = int(width)
      bounds%height = int(height)

      if (associated(current_view_node) .and. current_view_node%size > 0) then
        call calculate_treemap(current_view_node, bounds)
        ! Initialize cushion parameters for 3D shading
        call init_cushions(current_view_node)
      end if

      layout_calculated = .true.
      last_width = width
      last_height = height
    end if

    ! Render the treemap
    if (associated(current_view_node)) then
      call render_current_view(cr, current_view_node, bounds)
    end if

    ! Find which rectangle is under the mouse
    hovered_index = find_node_at_position(mouse_x, mouse_y)

    ! Render hover highlight if a node is hovered
    if (hovered_index > 0 .and. associated(current_view_node)) then
      if (allocated(current_view_node%children)) then
        if (hovered_index <= current_view_node%num_children) then
          call render_hover_highlight(cr, current_view_node%children(hovered_index))
        end if
      end if
    end if
  end subroutine scan_and_render_with_hover

  ! Rendering function with both hover and selection highlighting
  subroutine scan_and_render_with_interaction(cr, width, height, mouse_x, mouse_y, &
                                               selected_index, path)
    type(c_ptr), intent(in) :: cr
    integer(c_int), intent(in) :: width, height
    real(c_double), intent(in) :: mouse_x, mouse_y
    integer, intent(in) :: selected_index
    character(len=*), intent(in), optional :: path
    type(rect) :: bounds
    integer :: hovered_index

    ! Scan if needed (only once)
    if (.not. has_data) then
      if (present(path)) then
        call scan_directory(path)
      else
        call scan_directory("/Users/matthewwolffe/Downloads")
      end if
    end if

    ! Only recalculate layout if window size changed
    if (.not. layout_calculated .or. last_width /= width .or. last_height /= height) then
      bounds%x = 0
      bounds%y = 0
      bounds%width = int(width)
      bounds%height = int(height)

      if (associated(current_view_node) .and. current_view_node%size > 0) then
        call calculate_treemap(current_view_node, bounds)
        ! Initialize cushion parameters for 3D shading
        call init_cushions(current_view_node)
      end if

      layout_calculated = .true.
      last_width = width
      last_height = height
    end if

    ! Render the treemap
    if (associated(current_view_node)) then
      call render_current_view(cr, current_view_node, bounds)
    end if

    ! Render selection highlight first (under hover)
    if (selected_index > 0 .and. associated(current_view_node)) then
      print *, "DEBUG: selected_index =", selected_index
      if (allocated(current_view_node%children)) then
        if (selected_index <= current_view_node%num_children) then
          print *, "DEBUG: Rendering selection highlight for node:", selected_index
          call render_selection_highlight(cr, current_view_node%children(selected_index))
        else
          print *, "DEBUG: selected_index out of bounds:", selected_index, ">", current_view_node%num_children
        end if
      else
        print *, "DEBUG: current_view_node has no children"
      end if
    else
      if (selected_index == 0) then
        print *, "DEBUG: selected_index is 0 (no selection)"
      end if
    end if

    ! Find which rectangle is under the mouse
    hovered_index = find_node_at_position(mouse_x, mouse_y)

    ! Render hover highlight on top (only if not the selected node)
    if (hovered_index > 0 .and. hovered_index /= selected_index) then
      if (associated(current_view_node)) then
        if (allocated(current_view_node%children)) then
          if (hovered_index <= current_view_node%num_children) then
            call render_hover_highlight(cr, current_view_node%children(hovered_index))
          end if
        end if
      end if
    end if
  end subroutine scan_and_render_with_interaction

  ! Find which node is at the given position
  function find_node_at_position(mouse_x, mouse_y) result(index)
    real(c_double), intent(in) :: mouse_x, mouse_y
    integer :: index, i
    real :: x, y, w, h

    index = 0

    ! Check if mouse position is valid
    if (mouse_x < 0 .or. mouse_y < 0) return
    if (.not. associated(current_view_node)) return
    if (.not. allocated(current_view_node%children)) return

    ! Hit test against all visible rectangles (access bounds directly, no copying)
    do i = 1, current_view_node%num_children
      x = real(current_view_node%children(i)%bounds%x)
      y = real(current_view_node%children(i)%bounds%y)
      w = real(current_view_node%children(i)%bounds%width)
      h = real(current_view_node%children(i)%bounds%height)

      ! Check if mouse is inside this rectangle
      if (mouse_x >= x .and. mouse_x <= x + w .and. &
          mouse_y >= y .and. mouse_y <= y + h) then
        index = i
        return
      end if
    end do
  end function find_node_at_position

  ! Navigate into a directory node (zoom in)
  subroutine navigate_into_node(index)
    integer, intent(in) :: index

    ! Block navigation if scan is active
    if (is_scan_active()) then
      print *, "Navigation blocked: Scan in progress"
      return
    end if

    ! Validate inputs
    if (.not. associated(current_view_node)) then
      print *, "ERROR: No current view node!"
      return
    end if

    if (.not. allocated(current_view_node%children)) then
      print *, "ERROR: Current node has no children!"
      return
    end if

    if (index < 1 .or. index > current_view_node%num_children) then
      print *, "ERROR: Invalid child index: ", index
      return
    end if

    ! Get the target node
    if (.not. current_view_node%children(index)%is_directory) then
      print *, "Cannot navigate into file (not a directory)"
      return
    end if

    ! Restore all sizes before navigating (in case they were modified by filtering/deletion)
    print *, "Restoring sizes before navigation..."
    call recalculate_sizes(root_node)

    ! Check if the directory needs to be scanned (progressive scan didn't populate children)
    if (current_view_node%children(index)%num_children == 0 .and. &
        allocated(current_view_node%children(index)%path)) then
      ! This directory was created by progressive scan but never had children populated
      ! We need to scan it now
      print *, "Directory has no children - triggering rescan: ", &
               trim(current_view_node%children(index)%path)

      call scan_directory(trim(current_view_node%children(index)%path))
      return  ! scan_directory will set current_view_node appropriately
    end if

    ! Navigate into the directory
    current_view_node => current_view_node%children(index)

    ! Push onto path stack for breadcrumbs
    if (path_depth < MAX_PATH_DEPTH) then
      path_depth = path_depth + 1
      if (allocated(current_view_node%name)) then
        path_names(path_depth) = current_view_node%name
      else
        path_names(path_depth) = "(unnamed)"
      end if
    else
      print *, "WARNING: Max path depth reached!"
    end if

    ! Reset layout cache to force recalculation
    layout_calculated = .false.

    if (allocated(current_view_node%name)) then
      print *, "Navigated into: ", trim(current_view_node%name)
      print *, "Children: ", current_view_node%num_children
      print *, "Path depth: ", path_depth
    else
      print *, "Navigated into directory (no name)"
    end if
  end subroutine navigate_into_node

  ! Navigate up one level (back button / breadcrumb click)
  subroutine navigate_up(levels)
    use disk_scanner, only: build_tree
    use file_system, only: get_path_separator
    integer, intent(in), optional :: levels
    integer :: levels_to_go
    integer :: i, last_sep, cache_index
    character(len=512) :: parent_path, current_root_path
    character(len=1) :: sep
    type(file_node), pointer :: temp_node

    ! Block navigation if scan is active
    if (is_scan_active()) then
      print *, "Navigation blocked: Scan in progress"
      return
    end if

    if (present(levels)) then
      levels_to_go = levels
    else
      levels_to_go = 1
    end if

    ! If at root depth, re-scan parent directory
    if (path_depth <= 1) then
      ! Get parent directory path
      if (allocated(root_node%path)) then
        current_root_path = trim(root_node%path)
        sep = get_path_separator()

        ! Strip trailing separator if present
        if (len_trim(current_root_path) > 1) then
          if (current_root_path(len_trim(current_root_path):len_trim(current_root_path)) == sep) then
            current_root_path = current_root_path(1:len_trim(current_root_path)-1)
          end if
        end if

        ! Find last path separator (after stripping trailing slash)
        last_sep = 0
        do i = len_trim(current_root_path), 1, -1
          if (current_root_path(i:i) == sep) then
            last_sep = i
            exit
          end if
        end do

        ! Can't go above filesystem root
        if (last_sep <= 1 .and. sep == '/') then
          print *, "Already at filesystem root: /"
          return
        else if (last_sep == 0) then
          print *, "Cannot determine parent directory"
          return
        end if

        ! Get parent path
        if (last_sep > 1) then
          parent_path = current_root_path(1:last_sep-1)
        else
          parent_path = sep  ! Root directory
        end if

        print *, "Re-scanning parent directory: ", trim(parent_path)

        ! Use scan_directory instead of build_tree to ensure colors are applied
        ! and progress is shown
        call scan_directory(trim(parent_path))

        ! Update path names
        path_depth = 1
        if (allocated(root_node%name)) then
          path_names(1) = trim(root_node%path)
        else
          path_names(1) = trim(parent_path)
        end if

        ! Reset layout cache
        layout_calculated = .false.

        print *, "Navigated up to parent: ", trim(parent_path)
        return
      else
        print *, "Cannot navigate up: root path not set"
        return
      end if
    end if

    ! Go up the specified number of levels
    path_depth = max(1, path_depth - levels_to_go)

    ! Restore all sizes before navigating (in case they were modified by filtering/deletion)
    print *, "Restoring sizes before navigation..."
    call recalculate_sizes(root_node)

    ! Navigate back up to the correct node by traversing from root
    current_view_node => root_node

    ! If we're deeper than root, traverse down to the correct node
    if (path_depth > 1) then
      do i = 2, path_depth
        ! Find child matching path_names(i)
        if (.not. allocated(current_view_node%children)) then
          print *, "ERROR: Cannot navigate - current node has no children"
          current_view_node => root_node
          path_depth = 1
          exit
        end if

        ! Search for matching child by name
        temp_node => null()
        do cache_index = 1, current_view_node%num_children
          if (allocated(current_view_node%children(cache_index)%name)) then
            if (trim(current_view_node%children(cache_index)%name) == trim(path_names(i))) then
              temp_node => current_view_node%children(cache_index)
              exit
            end if
          end if
        end do

        if (associated(temp_node)) then
          current_view_node => temp_node
        else
          print *, "WARNING: Could not find child for path: ", trim(path_names(i))
          current_view_node => root_node
          path_depth = 1
          exit
        end if
      end do
    end if

    ! Reset layout cache
    layout_calculated = .false.

    print *, "Navigated up to depth: ", path_depth
    if (allocated(current_view_node%path)) then
      print *, "Current view: ", trim(current_view_node%path)
    end if
  end subroutine navigate_up

  ! Remove selected node from view (after deletion)
  ! This marks the node with size 0 so it won't be rendered
  subroutine remove_selected_node_from_view(selected_index)
    integer, intent(in) :: selected_index

    print *, "Removing node from view: index=", selected_index

    ! Validate inputs
    if (.not. associated(current_view_node)) then
      print *, "ERROR: No current view node"
      return
    end if

    if (.not. allocated(current_view_node%children)) then
      print *, "ERROR: Current node has no children"
      return
    end if

    if (selected_index < 1 .or. selected_index > current_view_node%num_children) then
      print *, "ERROR: Invalid selected index: ", selected_index
      return
    end if

    ! Mark the node as deleted by setting its size to 0
    ! This will cause the layout algorithm to skip it
    current_view_node%children(selected_index)%size = 0_int64

    print *, "Node marked as deleted (size = 0)"

    ! Invalidate layout so it gets recalculated without this node
    layout_calculated = .false.
  end subroutine remove_selected_node_from_view

  ! Get current path depth
  function get_path_depth() result(depth)
    integer :: depth
    depth = path_depth
  end function get_path_depth

  ! Get breadcrumb path (returns array of names)
  subroutine get_breadcrumb_path(names, count)
    character(len=256), dimension(:), intent(out) :: names
    integer, intent(out) :: count
    integer :: i

    count = path_depth
    do i = 1, min(path_depth, size(names))
      names(i) = path_names(i)
    end do
  end subroutine get_breadcrumb_path

  ! Get number of visible nodes in current view
  function get_node_count() result(count)
    integer :: count

    if (associated(current_view_node)) then
      count = current_view_node%num_children
    else
      count = 0
    end if
  end function get_node_count

  ! Get center coordinates of a node by index (for keyboard navigation)
  subroutine get_node_center_by_index(index, center_x, center_y, success)
    integer, intent(in) :: index
    real(c_double), intent(out) :: center_x, center_y
    logical, intent(out) :: success

    success = .false.

    if (.not. associated(current_view_node)) return
    if (index < 1 .or. index > current_view_node%num_children) return

    ! Get the node's bounds and calculate center
    center_x = real(current_view_node%children(index)%bounds%x, c_double) + &
               real(current_view_node%children(index)%bounds%width, c_double) / 2.0d0
    center_y = real(current_view_node%children(index)%bounds%y, c_double) + &
               real(current_view_node%children(index)%bounds%height, c_double) / 2.0d0

    success = .true.
  end subroutine get_node_center_by_index

  ! Find the best node in a given direction from current position
  ! direction: 1=up, 2=down, 3=left, 4=right
  function find_node_in_direction(from_x, from_y, direction) result(best_index)
    use iso_fortran_env, only: real64
    real(c_double), intent(in) :: from_x, from_y
    integer, intent(in) :: direction
    integer :: best_index
    integer :: i
    real(real64) :: cx, cy, dx, dy, score, best_score
    real(real64) :: directional_component, perpendicular_component

    best_index = 0
    best_score = 1.0d20  ! Large number

    if (.not. associated(current_view_node)) return
    if (current_view_node%num_children == 0) return

    ! For each child node, calculate score based on direction
    do i = 1, current_view_node%num_children
      ! Get center of this node
      cx = real(current_view_node%children(i)%bounds%x, real64) + &
           real(current_view_node%children(i)%bounds%width, real64) / 2.0d0
      cy = real(current_view_node%children(i)%bounds%y, real64) + &
           real(current_view_node%children(i)%bounds%height, real64) / 2.0d0

      dx = cx - real(from_x, real64)
      dy = cy - real(from_y, real64)

      ! Check if node is in the correct direction
      select case (direction)
      case (1)  ! Up
        if (dy >= 0.0d0) cycle  ! Skip nodes below or at same level
        directional_component = abs(dy)  ! Distance upward
        perpendicular_component = abs(dx)  ! Horizontal offset
      case (2)  ! Down
        if (dy <= 0.0d0) cycle  ! Skip nodes above or at same level
        directional_component = abs(dy)  ! Distance downward
        perpendicular_component = abs(dx)  ! Horizontal offset
      case (3)  ! Left
        if (dx >= 0.0d0) cycle  ! Skip nodes to right or at same position
        directional_component = abs(dx)  ! Distance leftward
        perpendicular_component = abs(dy)  ! Vertical offset
      case (4)  ! Right
        if (dx <= 0.0d0) cycle  ! Skip nodes to left or at same position
        directional_component = abs(dx)  ! Distance rightward
        perpendicular_component = abs(dy)  ! Vertical offset
      case default
        cycle
      end select

      ! Score: prioritize alignment (low perpendicular) and closeness (low directional)
      ! Weight perpendicular offset more heavily to prefer aligned nodes
      score = directional_component + perpendicular_component * 2.0d0

      if (score < best_score) then
        best_score = score
        best_index = i
      end if
    end do

    ! If no node found in direction, wrap around to opposite edge
    if (best_index == 0 .and. current_view_node%num_children > 0) then
      select case (direction)
      case (1)  ! Up - wrap to bottom (max Y)
        best_index = 1
        best_score = real(current_view_node%children(1)%bounds%y + &
                          current_view_node%children(1)%bounds%height, real64)
        do i = 2, current_view_node%num_children
          score = real(current_view_node%children(i)%bounds%y + &
                      current_view_node%children(i)%bounds%height, real64)
          if (score > best_score) then
            best_score = score
            best_index = i
          end if
        end do

      case (2)  ! Down - wrap to top (min Y)
        best_index = 1
        best_score = real(current_view_node%children(1)%bounds%y, real64)
        do i = 2, current_view_node%num_children
          score = real(current_view_node%children(i)%bounds%y, real64)
          if (score < best_score) then
            best_score = score
            best_index = i
          end if
        end do

      case (3)  ! Left - wrap to right (max X)
        best_index = 1
        best_score = real(current_view_node%children(1)%bounds%x + &
                          current_view_node%children(1)%bounds%width, real64)
        do i = 2, current_view_node%num_children
          score = real(current_view_node%children(i)%bounds%x + &
                      current_view_node%children(i)%bounds%width, real64)
          if (score > best_score) then
            best_score = score
            best_index = i
          end if
        end do

      case (4)  ! Right - wrap to left (min X)
        best_index = 1
        best_score = real(current_view_node%children(1)%bounds%x, real64)
        do i = 2, current_view_node%num_children
          score = real(current_view_node%children(i)%bounds%x, real64)
          if (score < best_score) then
            best_score = score
            best_index = i
          end if
        end do

      case default
        best_index = 1  ! Fallback
      end select
    end if

  end function find_node_in_direction

  ! Render hover highlight overlay
  subroutine render_hover_highlight(cr, node)
    type(c_ptr), intent(in) :: cr
    type(file_node), intent(in) :: node
    real(c_double) :: x, y, w, h

    x = real(node%bounds%x, c_double)
    y = real(node%bounds%y, c_double)
    w = real(node%bounds%width, c_double)
    h = real(node%bounds%height, c_double)

    ! Draw semi-transparent yellow overlay (30% opacity) - closer to selection color
    call cairo_set_source_rgba(cr, 1.0d0, 0.9d0, 0.3d0, 0.3d0)
    call cairo_rectangle(cr, x, y, w, h)
    call cairo_fill(cr)

    ! Draw thicker yellow highlight border
    call cairo_set_source_rgb(cr, 1.0d0, 0.9d0, 0.2d0)
    call cairo_set_line_width(cr, 2.5d0)
    call cairo_rectangle(cr, x, y, w, h)
    call cairo_stroke(cr)
  end subroutine render_hover_highlight

  ! Render selection highlight overlay (different from hover)
  subroutine render_selection_highlight(cr, node)
    type(c_ptr), intent(in) :: cr
    type(file_node), intent(in) :: node
    real(c_double) :: x, y, w, h

    x = real(node%bounds%x, c_double)
    y = real(node%bounds%y, c_double)
    w = real(node%bounds%width, c_double)
    h = real(node%bounds%height, c_double)

    ! Draw thick colored border (yellow/gold for selection)
    call cairo_set_source_rgb(cr, 1.0d0, 0.84d0, 0.0d0)  ! Gold color
    call cairo_set_line_width(cr, 4.0d0)
    call cairo_rectangle(cr, x, y, w, h)
    call cairo_stroke(cr)

    ! Draw inner border for extra emphasis
    call cairo_set_source_rgb(cr, 1.0d0, 1.0d0, 0.0d0)  ! Bright yellow
    call cairo_set_line_width(cr, 2.0d0)
    call cairo_rectangle(cr, x + 2.0d0, y + 2.0d0, w - 4.0d0, h - 4.0d0)
    call cairo_stroke(cr)
  end subroutine render_selection_highlight

  ! Render flash highlight overlay (for actively resizing items during scan)
  subroutine render_flash_highlight(cr, node)
    type(c_ptr), intent(in) :: cr
    type(file_node), intent(in) :: node
    real(c_double) :: x, y, w, h
    real(c_double) :: intensity

    ! Skip if flash intensity is too low
    if (node%flash_intensity < 0.05d0) return

    x = real(node%bounds%x, c_double)
    y = real(node%bounds%y, c_double)
    w = real(node%bounds%width, c_double)
    h = real(node%bounds%height, c_double)
    intensity = real(node%flash_intensity, c_double)

    ! Draw bright cyan/white flash overlay (intensity-based opacity)
    ! Cyan gives that "electric" SpaceSniffer feel
    call cairo_set_source_rgba(cr, 0.3d0, 1.0d0, 1.0d0, intensity * 0.6d0)
    call cairo_rectangle(cr, x, y, w, h)
    call cairo_fill(cr)

    ! Draw bright flash border
    call cairo_set_source_rgba(cr, 0.5d0, 1.0d0, 1.0d0, intensity * 0.9d0)
    call cairo_set_line_width(cr, 2.0d0)
    call cairo_rectangle(cr, x, y, w, h)
    call cairo_stroke(cr)
  end subroutine render_flash_highlight

  ! Get file extension from filename
  function get_file_extension(filename) result(ext)
    character(len=*), intent(in) :: filename
    character(len=:), allocatable :: ext
    integer :: dot_pos, i, ascii_val
    character(len=256) :: temp_ext

    ! Find last dot in filename
    dot_pos = 0
    do i = len_trim(filename), 1, -1
      if (filename(i:i) == '.') then
        dot_pos = i
        exit
      end if
    end do

    if (dot_pos > 0 .and. dot_pos < len_trim(filename)) then
      temp_ext = trim(filename(dot_pos+1:))
      ! Convert to lowercase for comparison
      do i = 1, len_trim(temp_ext)
        ascii_val = iachar(temp_ext(i:i))
        if (ascii_val >= 65 .and. ascii_val <= 90) then  ! A-Z
          temp_ext(i:i) = achar(ascii_val + 32)
        end if
      end do
      ext = trim(temp_ext)
    else
      ext = ""
    end if
  end function get_file_extension

  ! Strip file extension from a filename (modifies in place)
  subroutine strip_extension(filename)
    character(len=*), intent(inout) :: filename
    integer :: dot_pos, i

    ! Find the last dot in the filename
    dot_pos = 0
    do i = len_trim(filename), 1, -1
      if (filename(i:i) == '.') then
        dot_pos = i
        exit
      end if
      ! Stop at path separators (no dot in filename)
      if (filename(i:i) == '/' .or. filename(i:i) == '\') then
        exit
      end if
    end do

    ! If dot found and not at start of filename, strip from dot onward
    if (dot_pos > 1) then
      filename(dot_pos:) = ' '  ! Replace with spaces
    end if
  end subroutine strip_extension

  ! Get color hue based on file type
  function get_file_type_hue(filename) result(hue)
    use iso_fortran_env, only: real64
    character(len=*), intent(in) :: filename
    real(real64) :: hue
    character(len=:), allocatable :: ext

    ext = get_file_extension(filename)

    ! Assign hue based on file type categories
    ! Images: Green (120)
    if (ext == "jpg" .or. ext == "jpeg" .or. ext == "png" .or. ext == "gif" .or. &
        ext == "bmp" .or. ext == "svg" .or. ext == "ico" .or. ext == "webp" .or. &
        ext == "tiff" .or. ext == "tif") then
      hue = 120.0d0
    ! Videos: Magenta (300)
    else if (ext == "mp4" .or. ext == "avi" .or. ext == "mov" .or. ext == "mkv" .or. &
             ext == "flv" .or. ext == "wmv" .or. ext == "webm" .or. ext == "m4v" .or. &
             ext == "mpg" .or. ext == "mpeg") then
      hue = 300.0d0
    ! Audio: Cyan (180)
    else if (ext == "mp3" .or. ext == "wav" .or. ext == "flac" .or. ext == "aac" .or. &
             ext == "ogg" .or. ext == "wma" .or. ext == "m4a" .or. ext == "opus") then
      hue = 180.0d0
    ! Documents: Yellow (60)
    else if (ext == "pdf" .or. ext == "doc" .or. ext == "docx" .or. ext == "txt" .or. &
             ext == "rtf" .or. ext == "odt" .or. ext == "pages" .or. ext == "md") then
      hue = 60.0d0
    ! Archives: Red (0)
    else if (ext == "zip" .or. ext == "tar" .or. ext == "gz" .or. ext == "rar" .or. &
             ext == "7z" .or. ext == "bz2" .or. ext == "xz" .or. ext == "tgz" .or. &
             ext == "dmg" .or. ext == "iso") then
      hue = 0.0d0
    ! Code: Orange (30)
    else if (ext == "py" .or. ext == "js" .or. ext == "java" .or. ext == "c" .or. &
             ext == "cpp" .or. ext == "h" .or. ext == "rs" .or. ext == "go" .or. &
             ext == "rb" .or. ext == "php" .or. ext == "f90" .or. ext == "f95" .or. &
             ext == "f03" .or. ext == "f08" .or. ext == "ts" .or. ext == "jsx" .or. &
             ext == "tsx" .or. ext == "swift" .or. ext == "kt") then
      hue = 30.0d0
    ! Spreadsheets: Lime (90)
    else if (ext == "xls" .or. ext == "xlsx" .or. ext == "csv" .or. ext == "ods" .or. &
             ext == "numbers") then
      hue = 90.0d0
    ! Presentations: Rose (330)
    else if (ext == "ppt" .or. ext == "pptx" .or. ext == "odp" .or. ext == "key") then
      hue = 330.0d0
    ! Executables: Dark Red (15)
    else if (ext == "exe" .or. ext == "app" .or. ext == "bin" .or. ext == "sh" .or. &
             ext == "bat" .or. ext == "com") then
      hue = 15.0d0
    ! Default: Gray tone (0 with low saturation handled by caller)
    else
      hue = 0.0d0
    end if
  end function get_file_type_hue

  ! Assign colors based on file type
  recursive subroutine color_tree(node, depth)
    use iso_fortran_env, only: real64
    type(file_node), intent(inout) :: node
    integer, intent(in) :: depth
    integer :: i
    real(real64) :: hue, hue_offset

    if (node%is_directory) then
      ! Directories: blue-ish tones with depth variation
      hue = mod(depth * 60.0, 360.0)  ! 0, 60, 120, 180, 240, 300
      node%color = hsv_to_rgb(hue, 0.6d0, 0.8d0)
    else
      ! Files: color by file type
      hue = get_file_type_hue(node%name)
      if (abs(hue) < 0.01d0 .and. len_trim(get_file_extension(node%name)) == 0) then
        ! No extension - use gray
        node%color = hsv_to_rgb(0.0d0, 0.1d0, 0.8d0)
      else
        node%color = hsv_to_rgb(hue, 0.7d0, 0.9d0)
      end if
    end if

    ! Recurse to children with varying hues for siblings
    if (allocated(node%children)) then
      do i = 1, node%num_children
        ! For directories, calculate hue offset based on sibling index
        if (node%children(i)%is_directory) then
          hue = mod(depth * 60.0, 360.0)
          hue_offset = real(mod(i * 37, 360), real64)  ! 37 is prime for good distribution
          node%children(i)%color = hsv_to_rgb(hue + hue_offset, 0.6d0, 0.8d0)
        else
          ! For files, use file type color
          hue = get_file_type_hue(node%children(i)%name)
          if (abs(hue) < 0.01d0 .and. len_trim(get_file_extension(node%children(i)%name)) == 0) then
            node%children(i)%color = hsv_to_rgb(0.0d0, 0.1d0, 0.8d0)
          else
            ! Add slight variation based on sibling index
            hue_offset = real(mod(i * 5, 30), real64) - 15.0d0  ! Vary by ±15 degrees
            node%children(i)%color = hsv_to_rgb(hue + hue_offset, 0.7d0, 0.9d0)
          end if
        end if

        ! Recurse with increased depth
        call color_tree(node%children(i), depth + 1)
      end do
    end if
  end subroutine color_tree

  ! Initialize cushion parameters for treemap nodes
  ! Based on Van Wijk & Van de Wetering algorithm
  recursive subroutine init_cushions(node, parent_cushion)
    use iso_fortran_env, only: real64
    type(file_node), intent(inout) :: node
    type(cushion_params), intent(in), optional :: parent_cushion
    real(real64) :: x, y, w, h, cx, cy
    real(real64) :: f  ! Ridge height factor
    integer :: i

    ! Ridge height factor (controls the "bumpiness" of the cushion)
    ! Higher values = more pronounced 3D effect
    ! Need very large values because we divide by w² (pixels²)
    f = 50000.0d0

    ! Get rectangle bounds
    x = real(node%bounds%x, real64)
    y = real(node%bounds%y, real64)
    w = real(node%bounds%width, real64)
    h = real(node%bounds%height, real64)

    ! Calculate center
    cx = x + w / 2.0d0
    cy = y + h / 2.0d0

    ! Initialize or inherit cushion parameters
    if (present(parent_cushion)) then
      ! Inherit parent cushion and add our own
      node%cushion%ax = parent_cushion%ax
      node%cushion%ay = parent_cushion%ay
      node%cushion%bx = parent_cushion%bx
      node%cushion%by = parent_cushion%by
      node%cushion%c = parent_cushion%c
      node%cushion%depth = parent_cushion%depth + 1
    else
      ! Root node - initialize to zero
      node%cushion%ax = 0.0d0
      node%cushion%ay = 0.0d0
      node%cushion%bx = 0.0d0
      node%cushion%by = 0.0d0
      node%cushion%c = 0.0d0
      node%cushion%depth = 0
    end if

    ! Add this node's cushion ridge
    if (w > 0.0d0 .and. h > 0.0d0) then
      ! Add quadratic terms (Van Wijk algorithm)
      node%cushion%ax = node%cushion%ax + f / (w * w)
      node%cushion%ay = node%cushion%ay + f / (h * h)

      ! Add linear terms
      node%cushion%bx = node%cushion%bx - 2.0d0 * (f / (w * w)) * cx
      node%cushion%by = node%cushion%by - 2.0d0 * (f / (h * h)) * cy

      ! Add constant term
      node%cushion%c = node%cushion%c + (f / (w * w)) * cx * cx + (f / (h * h)) * cy * cy
    end if

    ! Recursively init children
    if (allocated(node%children)) then
      do i = 1, node%num_children
        call init_cushions(node%children(i), node%cushion)
      end do
    end if
  end subroutine init_cushions

  ! Simple HSV to RGB conversion
  function hsv_to_rgb(h, s, v) result(color)
    use iso_fortran_env, only: real64
    real(real64), intent(in) :: h, s, v
    type(rgb_color) :: color
    real(real64) :: c, x, m, h_prime
    integer :: sector

    h_prime = h / 60.0d0
    c = v * s
    x = c * (1.0d0 - abs(mod(h_prime, 2.0d0) - 1.0d0))
    m = v - c

    sector = int(h_prime)

    select case (sector)
    case (0)
      color%r = c + m; color%g = x + m; color%b = m
    case (1)
      color%r = x + m; color%g = c + m; color%b = m
    case (2)
      color%r = m; color%g = c + m; color%b = x + m
    case (3)
      color%r = m; color%g = x + m; color%b = c + m
    case (4)
      color%r = x + m; color%g = m; color%b = c + m
    case default
      color%r = c + m; color%g = m; color%b = x + m
    end select
  end function hsv_to_rgb

  ! Render only the current view (direct children only, no recursion)
  subroutine render_current_view(cr, view_node, bounds)
    use cairo, only: cairo_set_source_rgb, cairo_move_to, cairo_show_text, &
                     cairo_set_font_size, cairo_select_font_face
    type(c_ptr), intent(in) :: cr
    type(file_node), intent(in) :: view_node
    type(rect), intent(in) :: bounds
    integer :: i, visible_count
    real(c_double) :: center_x, center_y

    ! Render only the direct children of the current view
    if (allocated(view_node%children) .and. view_node%num_children > 0) then
      print *, "DEBUG: Rendering", view_node%num_children, "children"

      ! Count visible nodes
      visible_count = 0
      do i = 1, view_node%num_children
        ! Skip nodes without names (shouldn't happen but be defensive)
        if (.not. allocated(view_node%children(i)%name)) cycle

        if (view_node%children(i)%size > 0) then
          visible_count = visible_count + 1
          if (visible_count <= 5) then
            print *, "DEBUG: Visible child", i, ":", trim(view_node%children(i)%name), &
                     "size=", view_node%children(i)%size, "original=", view_node%children(i)%original_size
          end if
        end if
      end do
      print *, "DEBUG: Total visible children:", visible_count, "of", view_node%num_children

      do i = 1, view_node%num_children
        ! Skip nodes without names (shouldn't happen but be defensive)
        if (.not. allocated(view_node%children(i)%name)) cycle

        ! Skip nodes with size 0 (deleted)
        if (view_node%children(i)%size == 0) then
          cycle
        end if

        call render_node(cr, view_node%children(i))
      end do
    else
      ! Empty directory - show warning message
      print *, "DEBUG: Empty directory - showing warning"

      ! Draw warning text in center
      center_x = real(bounds%width, c_double) / 2.0_c_double
      center_y = real(bounds%height, c_double) / 2.0_c_double

      ! Set color to yellow/orange for warning
      call cairo_set_source_rgb(cr, 0.9_c_double, 0.6_c_double, 0.0_c_double)
      ! cairo font: family, slant (0=normal), weight (1=bold)
      call cairo_select_font_face(cr, "Sans"//c_null_char, 0_c_int, 1_c_int)
      call cairo_set_font_size(cr, 24.0_c_double)

      ! Center the text (approximate)
      call cairo_move_to(cr, center_x - 100.0_c_double, center_y - 30.0_c_double)
      call cairo_show_text(cr, "Empty Directory"//c_null_char)

      call cairo_set_font_size(cr, 14.0_c_double)
      call cairo_move_to(cr, center_x - 120.0_c_double, center_y + 10.0_c_double)
      call cairo_show_text(cr, "Press Backspace to go up"//c_null_char)
    end if
  end subroutine render_current_view

  ! Render a single node (non-recursive)
  subroutine render_node(cr, node)
    type(c_ptr), intent(in) :: cr
    type(file_node), intent(in) :: node
    real(c_double) :: x, y, w, h
    logical :: can_show_label

    ! Don't render tiny rectangles
    if (node%bounds%width < 2 .or. node%bounds%height < 2) return

    x = real(node%bounds%x, c_double)
    y = real(node%bounds%y, c_double)
    w = real(node%bounds%width, c_double)
    h = real(node%bounds%height, c_double)

    ! Check if we can show a full label
    can_show_label = (w >= 50.0d0 .and. h >= 20.0d0)

    ! Fill rectangle with base color (same for both modes)
    call cairo_set_source_rgb(cr, node%color%r, node%color%g, node%color%b)
    call cairo_rectangle(cr, x, y, w, h)
    call cairo_fill(cr)

    ! DEBUG: Check flag value (print only once per render)
    ! if (w > 100.0d0) print *, "DEBUG render_node: use_cushion_shading=", use_cushion_shading

    if (use_cushion_shading) then
      ! 3D mode: Draw highlight and shadow lines for embossed effect
      ! Only draw if rectangle is large enough
      if (w > 6.0d0 .and. h > 6.0d0) then
        ! Top-left highlight (inset by 1px to be inside border)
        call cairo_set_source_rgba(cr, 1.0d0, 1.0d0, 1.0d0, 0.6d0)
        call cairo_set_line_width(cr, 3.0d0)
        call cairo_move_to(cr, x + 2.0d0, y + h - 2.0d0)
        call cairo_line_to(cr, x + 2.0d0, y + 2.0d0)
        call cairo_line_to(cr, x + w - 2.0d0, y + 2.0d0)
        call cairo_stroke(cr)

        ! Bottom-right shadow (inset by 1px to be inside border)
        call cairo_set_source_rgba(cr, 0.0d0, 0.0d0, 0.0d0, 0.5d0)
        call cairo_set_line_width(cr, 3.0d0)
        call cairo_move_to(cr, x + 2.0d0, y + h - 2.0d0)
        call cairo_line_to(cr, x + w - 2.0d0, y + h - 2.0d0)
        call cairo_line_to(cr, x + w - 2.0d0, y + 2.0d0)
        call cairo_stroke(cr)
      end if
    end if

    ! Always draw border (for both flat and 3D modes)
    call cairo_set_source_rgb(cr, 0.0d0, 0.0d0, 0.0d0)
    call cairo_set_line_width(cr, 1.0d0)
    call cairo_rectangle(cr, x, y, w, h)
    call cairo_stroke(cr)

    ! Render flash highlight if node is actively being updated
    if (node%flash_intensity > 0.05d0) then
      call render_flash_highlight(cr, node)
    end if

    ! Render text label if rectangle is large enough
    if (can_show_label) then
      call render_label(cr, node, x, y, w, h)
    else if (w >= 10.0d0 .and. h >= 10.0d0) then
      ! Show "..." for rectangles too small for full labels
      call render_ellipsis(cr, x, y, w, h)
    else if (w >= 2.0d0 .and. h >= 2.0d0) then
      ! Debug: print info about unlabeled rectangles
      if (allocated(node%name)) then
        print *, "Unlabeled rect: ", trim(node%name), " size=", w, "x", h
      else
        print *, "Unlabeled rect: (no name) size=", w, "x", h
      end if
    end if
  end subroutine render_node

  ! Calculate cushion shading intensity using Van Wijk algorithm
  ! Returns a factor between 0.0 (dark) and 1.0 (bright)
  function calculate_cushion_shading(x, y, w, h, cushion) result(intensity)
    use iso_fortran_env, only: real64
    real(c_double), intent(in) :: x, y, w, h
    type(cushion_params), intent(in) :: cushion
    real(real64) :: intensity
    real(real64) :: cx, cy  ! Center of rectangle
    real(real64) :: nx, ny, nz, norm  ! Normal vector
    real(real64) :: lx, ly, lz  ! Light direction (from top-left)
    real(real64) :: dot_product
    real(real64) :: ambient, diffuse

    ! Light source direction (normalized) - coming from top-left at 45 degrees
    lx = -0.5d0
    ly = -0.5d0
    lz = 0.707d0  ! sqrt(1 - lx^2 - ly^2)

    ! Ambient and diffuse lighting coefficients
    ambient = 0.3d0  ! Base lighting (lowered for more contrast)
    diffuse = 0.7d0  ! Directional lighting strength (increased for more pronounced effect)

    ! Calculate center of rectangle
    cx = x + w / 2.0d0
    cy = y + h / 2.0d0

    ! Calculate surface gradient (partial derivatives)
    ! h(x,y) = ax*x² + bx*x + ay*y² + by*y + c
    ! ∂h/∂x = 2*ax*x + bx
    ! ∂h/∂y = 2*ay*y + by
    nx = -(2.0d0 * cushion%ax * cx + cushion%bx)
    ny = -(2.0d0 * cushion%ay * cy + cushion%by)
    nz = 1.0d0

    ! Debug: Print cushion params for first rectangle
    if (abs(cushion%ax) > 1e-10 .or. abs(cushion%ay) > 1e-10) then
      ! Only print if we have non-zero cushion params (skip spam)
    end if

    ! Normalize the normal vector
    norm = sqrt(nx*nx + ny*ny + nz*nz)
    if (norm > 0.0d0) then
      nx = nx / norm
      ny = ny / norm
      nz = nz / norm
    else
      nx = 0.0d0
      ny = 0.0d0
      nz = 1.0d0
    end if

    ! Calculate Lambertian shading (dot product of normal and light direction)
    dot_product = nx*lx + ny*ly + nz*lz
    dot_product = max(0.0d0, dot_product)  ! Clamp negative values

    ! Combine ambient and diffuse lighting
    intensity = ambient + diffuse * dot_product
    intensity = min(1.0d0, max(0.0d0, intensity))  ! Clamp to [0,1]

    ! Debug output (only print occasionally to avoid spam)
    ! print *, "Shading: cushion%ax=", cushion%ax, " intensity=", intensity
  end function calculate_cushion_shading

  ! Render ellipsis for small rectangles
  subroutine render_ellipsis(cr, x, y, w, h)
    type(c_ptr), intent(in) :: cr
    real(c_double), intent(in) :: x, y, w, h
    real(c_double) :: font_size, text_x, text_y

    ! Small font for ellipsis
    font_size = min(h * 0.5d0, 12.0d0)
    if (font_size < 6.0d0) return

    call cairo_select_font_face(cr, "Sans"//c_null_char, 0_c_int, 0_c_int)
    call cairo_set_font_size(cr, font_size)

    ! Center the ellipsis
    text_x = x + w / 2.0d0 - font_size * 0.5d0
    text_y = y + h / 2.0d0 + font_size * 0.3d0

    ! Draw with contrast
    call cairo_set_source_rgb(cr, 1.0d0, 1.0d0, 1.0d0)
    call cairo_move_to(cr, text_x, text_y)
    call cairo_show_text(cr, "..."//c_null_char)
  end subroutine render_ellipsis

  ! Format file size in human-readable format
  function format_size(size_bytes) result(size_str)
    use iso_fortran_env, only: int64, real64
    integer(int64), intent(in) :: size_bytes
    character(len=20) :: size_str
    real(real64) :: size_val

    if (size_bytes < 1024_int64) then
      write(size_str, '(I0, A)') size_bytes, ' B'
    else if (size_bytes < 1024_int64 * 1024_int64) then
      size_val = real(size_bytes, real64) / 1024.0d0
      write(size_str, '(F0.1, A)') size_val, ' KB'
    else if (size_bytes < 1024_int64 * 1024_int64 * 1024_int64) then
      size_val = real(size_bytes, real64) / (1024.0d0 * 1024.0d0)
      write(size_str, '(F0.1, A)') size_val, ' MB'
    else
      size_val = real(size_bytes, real64) / (1024.0d0 * 1024.0d0 * 1024.0d0)
      write(size_str, '(F0.1, A)') size_val, ' GB'
    end if
  end function format_size

  ! Cache helper functions
  ! Look up cached directory scan by path
  function cache_lookup(path) result(found_index)
    character(len=*), intent(in) :: path
    integer :: found_index, i

    found_index = 0
    do i = 1, cache_count
      if (dir_cache(i)%valid .and. trim(dir_cache(i)%path) == trim(path)) then
        found_index = i
        print *, "Cache hit for: ", trim(path)
        return
      end if
    end do
    print *, "Cache miss for: ", trim(path)
  end function cache_lookup

  ! Store scanned directory in cache
  subroutine cache_store(path, node)
    character(len=*), intent(in) :: path
    type(file_node), intent(in) :: node
    integer :: store_index

    ! Simple strategy: if cache full, overwrite oldest (index 1)
    if (cache_count < MAX_CACHE_SIZE) then
      cache_count = cache_count + 1
      store_index = cache_count
    else
      ! Cache full - simple FIFO: overwrite first entry
      print *, "Cache full - evicting oldest entry"
      store_index = 1
      ! Deallocate old entry before overwriting
      if (allocated(dir_cache(store_index)%node)) then
        call deallocate_tree(dir_cache(store_index)%node)
        deallocate(dir_cache(store_index)%node)
      end if
    end if

    ! Store in cache (deep copy via allocatable assignment)
    dir_cache(store_index)%path = trim(path)
    allocate(dir_cache(store_index)%node)
    dir_cache(store_index)%node = node  ! Deep copy
    dir_cache(store_index)%valid = .true.

    print *, "Cached scan for: ", trim(path), " at index ", store_index
  end subroutine cache_store

  ! Clear all cached directory scans
  subroutine clear_cache()
    integer :: i

    ! Deallocate cache entries (they are deep copies with own memory)
    do i = 1, cache_count
      if (allocated(dir_cache(i)%node)) then
        call deallocate_tree(dir_cache(i)%node)
        deallocate(dir_cache(i)%node)
      end if
      dir_cache(i)%valid = .false.
      dir_cache(i)%path = ""
    end do
    cache_count = 0
    print *, "Directory cache cleared and deallocated"
  end subroutine clear_cache

  ! Decay flash highlights for all visible nodes
  subroutine decay_flash_highlights()
    use iso_fortran_env, only: int64, real64
    integer :: i
    integer(int64) :: current_time, elapsed_ms
    real(real64) :: decay_rate

    if (.not. allocated(root_node%children)) return

    ! Get current time
    current_time = get_current_time_ms()

    ! Decay rate: flash fades out over ~200ms
    decay_rate = 0.15d0  ! Decay by 15% per update

    ! Decay flash intensity for all root children
    do i = 1, root_node%num_children
      if (root_node%children(i)%flash_intensity > 0.01d0) then
        ! Calculate time-based decay
        elapsed_ms = current_time - root_node%children(i)%last_update_time

        ! If it's been more than 50ms since last update, start decaying
        if (elapsed_ms > 50_int64) then
          root_node%children(i)%flash_intensity = &
            root_node%children(i)%flash_intensity * (1.0d0 - decay_rate)

          ! Clamp to zero when very small
          if (root_node%children(i)%flash_intensity < 0.01d0) then
            root_node%children(i)%flash_intensity = 0.0d0
          end if
        end if
      end if
    end do
  end subroutine decay_flash_highlights

  ! Get current time in milliseconds (wrapper for progressive_scanner function)
  function get_current_time_ms() result(time_ms)
    use iso_fortran_env, only: int64
    integer(int64) :: time_ms
    integer :: count, count_rate, count_max

    call system_clock(count, count_rate, count_max)
    time_ms = int(count * 1000_int64 / count_rate, int64)
  end function get_current_time_ms

  ! Recursively deallocate a file tree
  recursive subroutine deallocate_tree(node)
    type(file_node), intent(inout) :: node
    integer :: i

    ! Deallocate children recursively
    if (allocated(node%children)) then
      do i = 1, node%num_children
        call deallocate_tree(node%children(i))
      end do
      deallocate(node%children)
    end if

    ! Deallocate strings
    if (allocated(node%name)) deallocate(node%name)
    if (allocated(node%path)) deallocate(node%path)
  end subroutine deallocate_tree

  ! Toggle file extensions in labels
  subroutine toggle_file_extensions()
    show_file_extensions = .not. show_file_extensions
    if (show_file_extensions) then
      print *, "File extensions enabled"
    else
      print *, "File extensions disabled"
    end if
    ! Invalidate layout to force redraw
    call invalidate_layout()
  end subroutine toggle_file_extensions

  ! Toggle age-based coloring
  subroutine toggle_age_based_coloring()
    use_age_based_coloring = .not. use_age_based_coloring
    if (use_age_based_coloring) then
      print *, "Age-based coloring enabled"
    else
      print *, "File type coloring enabled"
    end if
    ! Need to recolor tree and redraw
    if (has_data) then
      call color_tree(root_node, 0)
      call invalidate_layout()
    end if
  end subroutine toggle_age_based_coloring

  ! Toggle size display mode (actual vs allocated)
  subroutine toggle_size_display_mode()
    show_allocated_size = .not. show_allocated_size
    if (show_allocated_size) then
      print *, "Showing allocated size (disk usage)"
    else
      print *, "Showing actual size"
    end if
    ! For now just a stub - would need to rescan with disk usage info
    ! Just invalidate layout to force redraw
    call invalidate_layout()
  end subroutine toggle_size_display_mode

  ! Toggle hidden files (dotfiles) visibility
  subroutine toggle_hidden_files()
    use disk_scanner, only: disk_scanner_set_show_hidden_files => set_show_hidden_files
    use progressive_scanner, only: progressive_scanner_set_show_hidden_files => set_show_hidden_files

    show_hidden_files = .not. show_hidden_files

    ! Update scanner settings for both scanners
    call disk_scanner_set_show_hidden_files(show_hidden_files)
    call progressive_scanner_set_show_hidden_files(show_hidden_files)

    if (show_hidden_files) then
      print *, "Hidden files (dotfiles) shown - rescan needed"
    else
      print *, "Hidden files (dotfiles) hidden - rescan needed"
    end if

    ! Clear cache to force rescan with new filter
    call clear_cache()
    call invalidate_layout()
  end subroutine toggle_hidden_files

  ! Toggle render mode (flat vs cushioned/3D)
  subroutine toggle_render_mode()
    print *, "=== TOGGLE_RENDER_MODE CALLED ==="
    print *, "use_cushion_shading before:", use_cushion_shading
    use_cushion_shading = .not. use_cushion_shading
    print *, "use_cushion_shading after:", use_cushion_shading
    if (use_cushion_shading) then
      print *, "Cushioned (3D) rendering enabled"
    else
      print *, "Flat rendering enabled"
    end if
    ! Invalidate layout and trigger redraw
    call invalidate_layout()
    if (c_associated(widget_for_redraw)) then
      call gtk_widget_queue_draw(widget_for_redraw)
      print *, "Redraw queued for render mode change"
    else
      print *, "ERROR: widget_for_redraw not associated!"
    end if
  end subroutine toggle_render_mode

  ! Wrap text to fit within a given width, returning lines
  subroutine wrap_text(cr, text, max_width, lines, line_count, max_lines)
    type(c_ptr), intent(in) :: cr
    character(len=*), intent(in) :: text
    real(c_double), intent(in) :: max_width
    character(len=256), dimension(:), intent(out) :: lines
    integer, intent(out) :: line_count
    integer, intent(in) :: max_lines

    ! Cairo text extents structure
    type, bind(c) :: cairo_text_extents_t
      real(c_double) :: x_bearing
      real(c_double) :: y_bearing
      real(c_double) :: width
      real(c_double) :: height
      real(c_double) :: x_advance
      real(c_double) :: y_advance
    end type cairo_text_extents_t

    type(cairo_text_extents_t), target :: extents
    character(len=256) :: current_line, test_line, word
    integer :: text_len, i, word_start, word_len
    logical :: in_word

    line_count = 0
    current_line = ""
    word = ""
    word_start = 1
    in_word = .false.
    text_len = len_trim(text)

    ! If text is empty, return
    if (text_len == 0) return

    ! Check if full text fits
    call cairo_text_extents(cr, trim(text)//c_null_char, c_loc(extents))
    if (extents%width <= max_width) then
      line_count = 1
      lines(1) = trim(text)
      return
    end if

    ! Split text into words and wrap
    i = 1
    do while (i <= text_len .and. line_count < max_lines)
      ! Get current character
      if (text(i:i) == ' ' .or. i == text_len) then
        ! End of word
        if (i == text_len .and. text(i:i) /= ' ') then
          word_len = i - word_start + 1
        else
          word_len = i - word_start
        end if

        if (word_len > 0) then
          word = text(word_start:word_start + word_len - 1)

          ! Try adding word to current line
          if (len_trim(current_line) == 0) then
            test_line = trim(word)
          else
            test_line = trim(current_line) // " " // trim(word)
          end if

          ! Measure the test line
          call cairo_text_extents(cr, trim(test_line)//c_null_char, c_loc(extents))

          if (extents%width <= max_width) then
            ! Word fits, add it to current line
            current_line = trim(test_line)
          else
            ! Word doesn't fit
            if (len_trim(current_line) > 0) then
              ! Save current line and start new one with this word
              line_count = line_count + 1
              lines(line_count) = trim(current_line)
              current_line = trim(word)
            else
              ! Word is too long for a single line, truncate it
              current_line = trim(word)
              ! Truncate word to fit
              do while (extents%width > max_width .and. len_trim(current_line) > 3)
                current_line = current_line(1:len_trim(current_line)-1)
                call cairo_text_extents(cr, trim(current_line)//"..."//c_null_char, c_loc(extents))
              end do
              current_line = trim(current_line) // "..."
              line_count = line_count + 1
              lines(line_count) = trim(current_line)
              current_line = ""
            end if
          end if
        end if

        word_start = i + 1
      end if
      i = i + 1
    end do

    ! Add remaining text as last line
    if (len_trim(current_line) > 0 .and. line_count < max_lines) then
      line_count = line_count + 1
      lines(line_count) = trim(current_line)
    end if

    ! If we hit max_lines, add ellipsis to last line
    if (line_count == max_lines .and. i < text_len) then
      lines(line_count) = trim(lines(line_count)) // "..."
    end if
  end subroutine wrap_text

  ! Render text label for a node
  subroutine render_label(cr, node, x, y, w, h)
    use iso_fortran_env, only: int64
    type(c_ptr), intent(in) :: cr
    type(file_node), intent(in) :: node
    real(c_double), intent(in) :: x, y, w, h
    real(c_double) :: font_size, text_x, text_y, size_font, max_text_width, bg_height
    integer :: min_width, min_height, max_name_lines, i, line_count
    character(len=256) :: name_copy
    character(len=256), dimension(5) :: wrapped_lines
    character(len=20) :: size_text

    ! Minimum rectangle size for text (pixels)
    min_width = 50
    min_height = 20

    ! Don't render text in tiny rectangles
    if (w < min_width .or. h < min_height) return

    ! Calculate font size based on rectangle height
    font_size = min(h / 3.0d0, 14.0d0)
    if (font_size < 8.0d0) return  ! Text too small to be readable

    ! Get the file/directory name
    if (allocated(node%name)) then
      name_copy = node%name

      ! Strip extension if show_file_extensions is false and it's a file
      if (.not. show_file_extensions .and. .not. node%is_directory) then
        call strip_extension(name_copy)
      end if
    else
      return  ! No name to display
    end if

    ! Set up font (0 = normal slant, 0 = normal weight)
    call cairo_select_font_face(cr, "Sans"//c_null_char, 0_c_int, 0_c_int)
    call cairo_set_font_size(cr, font_size)

    ! Calculate maximum text width (box width minus padding)
    max_text_width = w - 8.0d0

    ! Determine how many lines we can fit for the name
    if (h > 60) then
      max_name_lines = 3  ! Tall box: allow 3 lines for name + size line
    else if (h > 40) then
      max_name_lines = 2  ! Medium box: allow 2 lines for name + size line
    else
      max_name_lines = 1  ! Short box: only 1 line for name
    end if

    ! Wrap text to fit width
    call wrap_text(cr, name_copy, max_text_width, wrapped_lines, line_count, max_name_lines)

    ! Position text (top-left with small padding)
    text_x = x + 4.0d0
    text_y = y + font_size + 2.0d0

    ! Calculate background height based on number of lines
    if (h > 40 .and. line_count > 0) then
      ! Account for wrapped name lines + size line
      bg_height = font_size * real(line_count + 1, c_double) + 6.0d0
    else if (line_count > 0) then
      ! Just name lines, no size
      bg_height = font_size * real(line_count, c_double) + 4.0d0
    else
      bg_height = font_size + 6.0d0
    end if

    ! Draw semi-transparent dark background behind text for contrast
    call cairo_set_source_rgba(cr, 0.0d0, 0.0d0, 0.0d0, 0.7d0)  ! Black with 70% opacity
    call cairo_rectangle(cr, x + 2.0d0, y + 2.0d0, w - 4.0d0, bg_height)
    call cairo_fill(cr)

    ! Draw each line of wrapped text
    call cairo_set_source_rgb(cr, 1.0d0, 1.0d0, 1.0d0)
    do i = 1, line_count
      call cairo_move_to(cr, text_x, text_y)
      call cairo_show_text(cr, trim(wrapped_lines(i))//c_null_char)
      text_y = text_y + font_size + 2.0d0
    end do

    ! Draw size label on next line if rectangle is tall enough
    if (h > 40 .and. line_count > 0) then
      size_text = format_size(node%size)
      size_font = max(font_size * 0.8d0, 8.0d0)  ! Slightly smaller font for size

      call cairo_set_font_size(cr, size_font)

      ! Draw size in light gray/white
      call cairo_set_source_rgb(cr, 0.9d0, 0.9d0, 0.9d0)
      call cairo_move_to(cr, text_x, text_y)
      call cairo_show_text(cr, trim(size_text)//c_null_char)
    end if
  end subroutine render_label

  ! Recursively recalculate directory sizes from their children
  ! This restores sizes that may have been set to 0 by filtering
  recursive subroutine recalculate_sizes(node)
    type(file_node), intent(inout) :: node
    integer :: i

    ! If this is a file, restore from original_size backup
    ! (original_size is always set during scanning, even for empty files)
    if (.not. node%is_directory) then
      node%size = node%original_size
      return
    end if

    ! Directories: recalculate from children
    if (allocated(node%children) .and. node%num_children > 0) then
      ! First recalculate all children recursively
      do i = 1, node%num_children
        call recalculate_sizes(node%children(i))
      end do

      ! Then sum up children sizes
      node%size = 0_int64
      do i = 1, node%num_children
        node%size = node%size + node%children(i)%size
      end do
    else
      ! Empty directory
      node%size = 0_int64
    end if
  end subroutine recalculate_sizes

end module treemap_renderer
