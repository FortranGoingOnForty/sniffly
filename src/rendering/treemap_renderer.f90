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
  use iso_fortran_env, only: int64
  implicit none
  private

  public :: scan_and_render, init_renderer, get_root_node, scan_and_render_with_hover, &
            scan_and_render_with_interaction, find_node_at_position

  ! Global state
  type(file_node), save, target :: root_node
  type(file_node), pointer, save :: current_view_node => null()
  logical, save :: has_data = .false.
  character(len=512), save :: scanned_path = ""

contains

  ! Initialize renderer
  subroutine init_renderer()
    has_data = .false.
    scanned_path = ""
  end subroutine init_renderer

  ! Get root node (for external access)
  function get_root_node() result(node_ptr)
    type(file_node), pointer :: node_ptr
    node_ptr => root_node
  end function get_root_node

  ! Scan directory and prepare for rendering
  subroutine scan_directory(path)
    character(len=*), intent(in) :: path

    print *, "Scanning: ", trim(path)

    ! Scan the directory tree (recursively gets all files)
    call build_tree(path, root_node)

    ! Assign colors to nodes
    call color_tree(root_node, 0)

    scanned_path = trim(path)
    has_data = .true.

    ! Start view at root level (showing only top-level items)
    current_view_node => root_node

    print *, "Scan complete. Root size: ", root_node%size, " bytes"
    print *, "Children: ", root_node%num_children
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
    logical, save :: layout_calculated = .false.
    integer, save :: last_width = 0, last_height = 0

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
    logical, save :: layout_calculated = .false.
    integer, save :: last_width = 0, last_height = 0

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
      if (allocated(current_view_node%children)) then
        if (selected_index <= current_view_node%num_children) then
          call render_selection_highlight(cr, current_view_node%children(selected_index))
        end if
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

  ! Assign colors based on depth and file type
  recursive subroutine color_tree(node, depth)
    use iso_fortran_env, only: real64
    type(file_node), intent(inout) :: node
    integer, intent(in) :: depth
    integer :: i
    real(real64) :: hue

    ! Color based on depth (alternating hues)
    hue = mod(depth * 60.0, 360.0)  ! 0, 60, 120, 180, 240, 300

    if (node%is_directory) then
      ! Directories: blue-ish tones
      node%color = hsv_to_rgb(hue, 0.6d0, 0.8d0)
    else
      ! Files: warmer tones
      node%color = hsv_to_rgb(hue + 30.0, 0.5d0, 0.9d0)
    end if

    ! Recurse to children
    if (allocated(node%children)) then
      do i = 1, node%num_children
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
      do i = 1, view_node%num_children
        call render_node(cr, view_node%children(i))
      end do
    end if
  end subroutine render_current_view

  ! Render a single node (non-recursive)
  subroutine render_node(cr, node)
    type(c_ptr), intent(in) :: cr
    type(file_node), intent(in) :: node
    real(c_double) :: x, y, w, h

    ! Don't render tiny rectangles
    if (node%bounds%width < 2 .or. node%bounds%height < 2) return

    x = real(node%bounds%x, c_double)
    y = real(node%bounds%y, c_double)
    w = real(node%bounds%width, c_double)
    h = real(node%bounds%height, c_double)

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
    call render_label(cr, node, x, y, w, h)
  end subroutine render_node

  ! Render text label for a node
  subroutine render_label(cr, node, x, y, w, h)
    type(c_ptr), intent(in) :: cr
    type(file_node), intent(in) :: node
    real(c_double), intent(in) :: x, y, w, h
    real(c_double) :: font_size, text_x, text_y
    integer :: min_width, min_height
    character(len=:), allocatable :: display_name
    character(len=256) :: name_copy

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

    ! Draw text with white color for visibility
    call cairo_set_source_rgb(cr, 1.0d0, 1.0d0, 1.0d0)
    call cairo_move_to(cr, text_x, text_y)
    call cairo_show_text(cr, trim(name_copy)//c_null_char)
  end subroutine render_label

end module treemap_renderer
