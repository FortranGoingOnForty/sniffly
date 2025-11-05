! Treemap Renderer Module for Sniffly
! Coordinates scanning, layout calculation, and Cairo rendering
module treemap_renderer
  use, intrinsic :: iso_c_binding
  use types
  use disk_scanner, only: build_tree
  use squarified_layout, only: calculate_treemap
  use cairo, only: cairo_set_source_rgb, cairo_rectangle, cairo_fill, &
                   cairo_stroke, cairo_set_line_width
  use iso_fortran_env, only: int64
  implicit none
  private

  public :: scan_and_render, init_renderer, get_root_node

  ! Global state
  type(file_node), save, target :: root_node
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

    ! Scan the directory tree
    call build_tree(path, root_node)

    ! Assign colors to nodes
    call color_tree(root_node, 0)

    scanned_path = trim(path)
    has_data = .true.

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

    ! Calculate layout for window size
    bounds%x = 0
    bounds%y = 0
    bounds%width = int(width)
    bounds%height = int(height)

    if (root_node%size > 0) then
      call calculate_treemap(root_node, bounds)
    end if

    ! Render the treemap
    call render_treemap(cr, root_node, bounds)
  end subroutine scan_and_render

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

  ! Render the treemap using Cairo
  recursive subroutine render_treemap(cr, node, bounds)
    type(c_ptr), intent(in) :: cr
    type(file_node), intent(in) :: node
    type(rect), intent(in) :: bounds
    integer :: i
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

    ! Render children
    if (allocated(node%children)) then
      do i = 1, node%num_children
        call render_treemap(cr, node%children(i), bounds)
      end do
    end if
  end subroutine render_treemap

end module treemap_renderer
