! Treemap Renderer Module for Sniffly
! Coordinates scanning, layout calculation, and Cairo rendering
module treemap_renderer
  use, intrinsic :: iso_c_binding
  use types
  use disk_scanner, only: build_tree
  use squarified_layout, only: calculate_treemap
  use cairo, only: cairo_set_source_rgb, cairo_rectangle, cairo_fill, &
                   cairo_stroke, cairo_set_line_width, cairo_select_font_face, &
                   cairo_set_font_size, cairo_move_to, cairo_show_text, &
                   cairo_set_source_rgba
  use g, only: g_main_context_default, g_main_context_iteration
  use iso_fortran_env, only: int64
  implicit none
  private

  public :: scan_and_render, init_renderer, get_root_node, scan_and_render_with_hover, &
            scan_and_render_with_interaction, find_node_at_position, navigate_into_node, &
            navigate_up, get_breadcrumb_path, get_path_depth, get_node_count, &
            get_node_center_by_index, find_node_in_direction, register_progress_callback, &
            scan_directory, invalidate_layout

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

  ! Navigation path stack (for breadcrumbs)
  ! Simple approach: track path as array of names
  integer, parameter :: MAX_PATH_DEPTH = 100
  character(len=256), save :: path_names(MAX_PATH_DEPTH)
  integer, save :: path_depth = 0

  ! Progress callback pointers
  procedure(show_progress_callback), pointer, save :: show_progress_cb => null()
  procedure(hide_progress_callback), pointer, save :: hide_progress_cb => null()
  procedure(update_progress_callback), pointer, save :: update_progress_cb => null()

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

  ! Get root node (for external access)
  function get_root_node() result(node_ptr)
    type(file_node), pointer :: node_ptr
    node_ptr => root_node
  end function get_root_node

  ! Scan directory and prepare for rendering
  subroutine scan_directory(path)
    use, intrinsic :: iso_c_binding
    use disk_scanner, only: set_progress_callback
    character(len=*), intent(in) :: path
    integer :: cache_index, i
    character(len=512) :: status_msg
    type(c_ptr) :: context
    integer(c_int) :: events_processed

    print *, "Scanning: ", trim(path)

    ! Mark as having data IMMEDIATELY to prevent recursive scans
    has_data = .true.
    scanned_path = trim(path)

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
    write(status_msg, '(A,A)') 'Scanning: ', trim(path)
    if (associated(update_progress_cb)) call update_progress_cb(0.1_c_double, status_msg)

    ! Process events again to show the update
    do i = 1, 5
      do while (g_main_context_iteration(context, 0_c_int) /= 0_c_int)
      end do
    end do

    ! Check cache first
    cache_index = cache_lookup(path)
    if (cache_index > 0) then
      ! Use cached scan (already colored)
      if (associated(update_progress_cb)) call update_progress_cb(0.5_c_double, 'Loading from cache...')
      ! Process events
      do while (g_main_context_iteration(context, 0_c_int) /= 0_c_int)
      end do
      root_node = dir_cache(cache_index)%node
    else
      ! Scan the directory tree (recursively gets all files)
      if (associated(update_progress_cb)) call update_progress_cb(0.3_c_double, 'Scanning directories...')
      ! Process events
      do while (g_main_context_iteration(context, 0_c_int) /= 0_c_int)
      end do

      call build_tree(path, root_node)

      ! Assign colors to nodes BEFORE caching
      if (associated(update_progress_cb)) call update_progress_cb(0.85_c_double, 'Assigning colors...')
      ! Process events
      do while (g_main_context_iteration(context, 0_c_int) /= 0_c_int)
      end do

      call color_tree(root_node, 0)

      ! Store in cache (now with colors)
      call cache_store(path, root_node)
    end if

    ! Start view at root level (showing only top-level items)
    current_view_node => root_node

    ! Initialize breadcrumb path stack with root path
    path_depth = 1
    path_names(1) = trim(scanned_path)

    ! Update progress and hide progress bar
    if (associated(update_progress_cb)) call update_progress_cb(1.0_c_double, 'Scan complete')
    ! Process events one more time
    do while (g_main_context_iteration(context, 0_c_int) /= 0_c_int)
    end do

    if (associated(hide_progress_cb)) call hide_progress_cb()

    print *, "Scan complete. Root size: ", root_node%size, " bytes"
    print *, "Children: ", root_node%num_children

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

    ! Navigate back up to the correct node
    temp_node => root_node
    do i = 2, path_depth
      ! Find child matching path_names(i)
      ! For now, just go to root if depth = 1
      if (path_depth == 1) then
        temp_node => root_node
        exit
      end if
    end do
    current_view_node => temp_node

    ! Reset layout cache
    layout_calculated = .false.

    print *, "Navigated up to depth: ", path_depth
  end subroutine navigate_up

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
    real(real64) :: cx, cy, dx, dy, dist, score, best_score
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

    ! Draw semi-transparent white overlay (40% opacity)
    call cairo_set_source_rgba(cr, 1.0d0, 1.0d0, 1.0d0, 0.4d0)
    call cairo_rectangle(cr, x, y, w, h)
    call cairo_fill(cr)

    ! Draw thicker highlight border
    call cairo_set_source_rgb(cr, 1.0d0, 1.0d0, 1.0d0)
    call cairo_set_line_width(cr, 3.0d0)
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

  ! Assign colors based on depth, file type, and sibling index for variation
  recursive subroutine color_tree(node, depth)
    use iso_fortran_env, only: real64
    type(file_node), intent(inout) :: node
    integer, intent(in) :: depth
    integer :: i
    real(real64) :: hue, hue_offset

    ! Color based on depth (alternating hues)
    hue = mod(depth * 60.0, 360.0)  ! 0, 60, 120, 180, 240, 300

    if (node%is_directory) then
      ! Directories: blue-ish tones
      node%color = hsv_to_rgb(hue, 0.6d0, 0.8d0)
    else
      ! Files: warmer tones
      node%color = hsv_to_rgb(hue + 30.0, 0.5d0, 0.9d0)
    end if

    ! Recurse to children with varying hues for siblings
    if (allocated(node%children)) then
      do i = 1, node%num_children
        ! Calculate hue offset based on sibling index (spread across 360 degrees)
        hue_offset = real(mod(i * 37, 360), real64)  ! 37 is prime for good distribution

        ! Apply variation to child
        if (node%children(i)%is_directory) then
          node%children(i)%color = hsv_to_rgb(hue + hue_offset, 0.6d0, 0.8d0)
        else
          node%children(i)%color = hsv_to_rgb(hue + hue_offset + 30.0, 0.5d0, 0.9d0)
        end if

        ! Recurse with increased depth
        call color_tree(node%children(i), depth + 1)
      end do
    end if
  end subroutine color_tree

  ! Simple HSV to RGB conversion
  function hsv_to_rgb(h, s, v) result(color)
    use iso_fortran_env, only: real64
    real(real64), intent(in) :: h, s, v
    type(rgb_color) :: color
    real(real64) :: c, x, m, h_prime
    integer :: sector

    h_prime = h / 60.0
    c = v * s
    x = c * (1.0 - abs(mod(h_prime, 2.0) - 1.0))
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
    type(c_ptr), intent(in) :: cr
    type(file_node), intent(in) :: view_node
    type(rect), intent(in) :: bounds
    integer :: i

    ! Render only the direct children of the current view
    if (allocated(view_node%children)) then
      print *, "DEBUG: Rendering", view_node%num_children, "children"
      do i = 1, view_node%num_children
        print *, "DEBUG: Rendering child", i, "bounds:", &
                 view_node%children(i)%bounds%x, view_node%children(i)%bounds%y, &
                 view_node%children(i)%bounds%width, view_node%children(i)%bounds%height
        call render_node(cr, view_node%children(i))
      end do
    else
      print *, "DEBUG: view_node has NO children allocated!"
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

    ! Fill rectangle with color
    call cairo_set_source_rgb(cr, node%color%r, node%color%g, node%color%b)
    call cairo_rectangle(cr, x, y, w, h)
    call cairo_fill(cr)

    ! Draw border
    call cairo_set_source_rgb(cr, 0.0d0, 0.0d0, 0.0d0)
    call cairo_set_line_width(cr, 1.0d0)
    call cairo_rectangle(cr, x, y, w, h)
    call cairo_stroke(cr)

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
    end if

    ! Store in cache
    dir_cache(store_index)%path = trim(path)
    dir_cache(store_index)%node = node
    dir_cache(store_index)%valid = .true.

    print *, "Cached scan for: ", trim(path), " at index ", store_index
  end subroutine cache_store

  ! Render text label for a node
  subroutine render_label(cr, node, x, y, w, h)
    use iso_fortran_env, only: int64
    type(c_ptr), intent(in) :: cr
    type(file_node), intent(in) :: node
    real(c_double), intent(in) :: x, y, w, h
    real(c_double) :: font_size, text_x, text_y, size_font
    integer :: min_width, min_height
    character(len=:), allocatable :: display_name
    character(len=256) :: name_copy
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
    else
      return  ! No name to display
    end if

    ! Set up font (0 = normal slant, 0 = normal weight)
    call cairo_select_font_face(cr, "Sans"//c_null_char, 0_c_int, 0_c_int)
    call cairo_set_font_size(cr, font_size)

    ! Position text (top-left with small padding)
    text_x = x + 4.0d0
    text_y = y + font_size + 2.0d0

    ! Draw semi-transparent dark background behind text for contrast
    call cairo_set_source_rgba(cr, 0.0d0, 0.0d0, 0.0d0, 0.7d0)  ! Black with 70% opacity
    if (h > 40) then
      ! Taller background for two lines
      call cairo_rectangle(cr, x + 2.0d0, y + 2.0d0, w - 4.0d0, font_size * 2.5d0 + 6.0d0)
    else
      ! Single line background
      call cairo_rectangle(cr, x + 2.0d0, y + 2.0d0, w - 4.0d0, font_size + 6.0d0)
    end if
    call cairo_fill(cr)

    ! Draw name with white color for visibility
    call cairo_set_source_rgb(cr, 1.0d0, 1.0d0, 1.0d0)
    call cairo_move_to(cr, text_x, text_y)
    call cairo_show_text(cr, trim(name_copy)//c_null_char)

    ! Draw size label on second line if rectangle is tall enough
    if (h > 40) then
      size_text = format_size(node%size)
      size_font = max(font_size * 0.8d0, 8.0d0)  ! Slightly smaller font for size

      call cairo_set_font_size(cr, size_font)
      text_y = text_y + size_font + 2.0d0  ! Move down for second line

      ! Draw size in light gray/white
      call cairo_set_source_rgb(cr, 0.9d0, 0.9d0, 0.9d0)
      call cairo_move_to(cr, text_x, text_y)
      call cairo_show_text(cr, trim(size_text)//c_null_char)
    end if
  end subroutine render_label

end module treemap_renderer
