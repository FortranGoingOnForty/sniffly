! Core data types for Sniffly
! Adapted from sniffert with enhancements for GUI rendering
module types
  use iso_fortran_env, only: int64, real64
  implicit none
  private

  public :: file_node, rect, rgb_color, cushion_params

  ! Rectangle for treemap layout (screen coordinates)
  type :: rect
    integer :: x, y      ! Top-left corner (absolute coordinates)
    integer :: width, height
  end type rect

  ! RGB color (values 0.0-1.0 for Cairo)
  type :: rgb_color
    real(real64) :: r, g, b
  end type rgb_color

  ! Cushion parameters for cushioned treemap rendering
  ! Based on Van Wijk & Van de Wetering algorithm
  type :: cushion_params
    real(real64) :: ax, ay    ! Quadratic coefficients for x and y
    real(real64) :: bx, by    ! Linear coefficients
    real(real64) :: c         ! Constant term
    integer :: depth          ! Depth in tree (for color variation)
  end type cushion_params

  ! Represents a file or directory in the tree
  type :: file_node
    ! Basic file information
    character(len=:), allocatable :: name
    character(len=:), allocatable :: path
    integer(int64) :: size
    integer(int64) :: original_size  ! Backup of size before filtering (0 = not backed up yet)
    logical :: is_directory
    logical :: access_denied  ! True if permission denied during scan

    ! Layout information (calculated by treemap algorithm)
    type(rect) :: bounds  ! Screen coordinates for rendering

    ! Visual information (for rendering)
    type(rgb_color) :: color  ! Base color (by type, age, etc.)
    type(cushion_params) :: cushion  ! Cushion shading parameters
    logical :: is_selected  ! True if this node is currently selected
    logical :: is_hovered   ! True if mouse is hovering over this node

    ! Progressive scan state (for dynamic rendering)
    logical :: scan_complete  ! True when all children have been scanned
    integer(int64) :: estimated_size  ! Estimated total size (grows as scan progresses)
    logical :: is_scanning  ! True if currently being scanned

    ! Flash highlight state (for visual feedback during size updates)
    real(real64) :: flash_intensity  ! 0.0 to 1.0, decays over time
    integer(int64) :: last_update_time  ! Timestamp of last size update (milliseconds)

    ! Tree structure
    type(file_node), dimension(:), allocatable :: children
    integer :: num_children

    ! Parent reference (optional, for navigation)
    ! Note: Cannot be a pointer to file_node due to circular reference
    ! Instead, we'll track parent in the selection/navigation module
  end type file_node

contains

  ! Utility functions commented out to avoid unused warnings
  ! Uncomment if needed in future development

  ! ! Helper function to create RGB color
  ! pure function make_rgb(r, g, b) result(color)
  !   real(real64), intent(in) :: r, g, b
  !   type(rgb_color) :: color
  !   color%r = r
  !   color%g = g
  !   color%b = b
  ! end function make_rgb

  ! ! Helper function to create rectangle
  ! pure function make_rect(x, y, w, h) result(r)
  !   integer, intent(in) :: x, y, w, h
  !   type(rect) :: r
  !   r%x = x
  !   r%y = y
  !   r%width = w
  !   r%height = h
  ! end function make_rect

  ! ! Check if a point is inside a rectangle
  ! pure function rect_contains(r, px, py) result(inside)
  !   type(rect), intent(in) :: r
  !   integer, intent(in) :: px, py
  !   logical :: inside
  !
  !   inside = (px >= r%x .and. px < r%x + r%width .and. &
  !             py >= r%y .and. py < r%y + r%height)
  ! end function rect_contains

  ! ! Get area of rectangle
  ! pure function rect_area(r) result(area)
  !   type(rect), intent(in) :: r
  !   integer :: area
  !   area = r%width * r%height
  ! end function rect_area

end module types
