! Tab Manager Module for Sniffly
! Manages multiple tabs with independent scan states and navigation history
module tab_manager
  use, intrinsic :: iso_c_binding
  use iso_fortran_env, only: int64
  use types, only: file_node
  implicit none
  private

  public :: tab_state, tabs, active_tab_index, num_tabs, MAX_TABS, MAX_HISTORY
  public :: init_tab_manager, create_tab, close_tab, switch_to_tab
  public :: get_active_tab, get_tab, get_path_basename

  ! Constants
  integer, parameter :: MAX_TABS = 5
  integer, parameter :: MAX_HISTORY = 50
  integer, parameter :: MAX_PATH_DEPTH = 100

  ! Scan state (embedded in each tab)
  type :: queue_entry
    character(len=512) :: path
    integer :: node_index
    integer :: parent_id
    integer :: depth
  end type queue_entry

  type :: scan_state_type
    logical :: active
    integer :: total_dirs_found
    integer :: dirs_scanned
    real :: progress
    type(queue_entry), dimension(10000) :: queue
    integer :: queue_head
    integer :: queue_tail
    integer :: queue_size
    type(file_node), pointer :: root => null()
    character(len=512) :: root_path
  end type scan_state_type

  ! Per-tab state encapsulation
  type :: tab_state
    ! Identity
    integer :: tab_id
    character(len=256) :: label  ! Tab display name

    ! Path and navigation
    character(len=512) :: scan_path
    character(len=512), dimension(MAX_HISTORY) :: nav_history
    integer :: nav_history_count
    integer :: nav_history_pos
    logical :: navigating_history

    ! Synthetic navigation (for future use)
    logical :: pending_synthetic_nav
    character(len=512) :: pending_synthetic_child_name
    integer :: synthetic_nav_attempts

    ! Tree view state
    type(file_node), pointer :: root_node => null()
    type(file_node), pointer :: current_view_node => null()
    logical :: has_data
    integer :: selected_index

    ! Layout state
    logical :: layout_calculated
    integer :: last_width
    integer :: last_height

    ! View settings
    logical :: show_file_extensions
    logical :: use_age_based_coloring
    logical :: show_allocated_size
    logical :: show_hidden_files
    logical :: use_cushion_shading

    ! Path navigation breadcrumb
    character(len=256), dimension(MAX_PATH_DEPTH) :: path_names
    integer :: path_depth

    ! Scan state
    type(scan_state_type) :: scan_state
    integer(c_int) :: scan_idle_id
  end type tab_state

  ! Global tab management
  type(tab_state), dimension(MAX_TABS), save, target :: tabs
  integer, save :: active_tab_index = 1
  integer, save :: num_tabs = 0
  integer, save :: next_tab_id = 1

contains

  ! Initialize tab manager (call once at startup)
  subroutine init_tab_manager()
    active_tab_index = 1
    num_tabs = 0
    next_tab_id = 1
    print *, "Tab manager initialized"
  end subroutine init_tab_manager

  ! Create a new tab with given path
  function create_tab(path) result(tab_index)
    character(len=*), intent(in) :: path
    integer :: tab_index

    ! Check if we've reached the limit
    if (num_tabs >= MAX_TABS) then
      print *, "ERROR: Maximum tabs reached (", MAX_TABS, ")"
      tab_index = -1
      return
    end if

    ! Increment tab count
    num_tabs = num_tabs + 1
    tab_index = num_tabs

    ! Initialize tab state
    tabs(tab_index)%tab_id = next_tab_id
    next_tab_id = next_tab_id + 1

    tabs(tab_index)%scan_path = trim(path)
    tabs(tab_index)%label = get_path_basename(path)

    ! Initialize navigation history
    tabs(tab_index)%nav_history_count = 0
    tabs(tab_index)%nav_history_pos = 0
    tabs(tab_index)%navigating_history = .false.

    ! Initialize synthetic nav
    tabs(tab_index)%pending_synthetic_nav = .false.
    tabs(tab_index)%pending_synthetic_child_name = ""
    tabs(tab_index)%synthetic_nav_attempts = 0

    ! Initialize tree pointers
    tabs(tab_index)%root_node => null()
    tabs(tab_index)%current_view_node => null()
    tabs(tab_index)%has_data = .false.
    tabs(tab_index)%selected_index = 0

    ! Initialize layout
    tabs(tab_index)%layout_calculated = .false.
    tabs(tab_index)%last_width = 0
    tabs(tab_index)%last_height = 0

    ! Initialize view settings (defaults)
    tabs(tab_index)%show_file_extensions = .true.
    tabs(tab_index)%use_age_based_coloring = .false.
    tabs(tab_index)%show_allocated_size = .false.
    tabs(tab_index)%show_hidden_files = .true.
    tabs(tab_index)%use_cushion_shading = .true.

    ! Initialize path navigation
    tabs(tab_index)%path_depth = 0

    ! Initialize scan state
    tabs(tab_index)%scan_state%active = .false.
    tabs(tab_index)%scan_state%total_dirs_found = 0
    tabs(tab_index)%scan_state%dirs_scanned = 0
    tabs(tab_index)%scan_state%progress = 0.0
    tabs(tab_index)%scan_state%queue_head = 1
    tabs(tab_index)%scan_state%queue_tail = 1
    tabs(tab_index)%scan_state%queue_size = 0
    tabs(tab_index)%scan_state%root => null()
    tabs(tab_index)%scan_state%root_path = ""
    tabs(tab_index)%scan_idle_id = 0_c_int

    print *, "Created tab ", tab_index, " for path: ", trim(path)
  end function create_tab

  ! Close a tab (with cleanup)
  subroutine close_tab(tab_index)
    integer, intent(in) :: tab_index
    integer :: i

    if (tab_index < 1 .or. tab_index > num_tabs) then
      print *, "ERROR: Invalid tab index: ", tab_index
      return
    end if

    ! Prevent closing last tab
    if (num_tabs == 1) then
      print *, "ERROR: Cannot close last tab"
      return
    end if

    print *, "Closing tab ", tab_index

    ! TODO: Cancel any active scan for this tab
    ! TODO: Deallocate file tree recursively

    ! Shift tabs down to fill gap
    do i = tab_index, num_tabs - 1
      tabs(i) = tabs(i + 1)
    end do

    ! Decrement count
    num_tabs = num_tabs - 1

    ! Adjust active tab index if needed
    if (active_tab_index == tab_index) then
      ! Closed active tab - activate next tab (or previous if was last)
      if (active_tab_index > num_tabs) then
        active_tab_index = num_tabs
      end if
      print *, "Switched to tab ", active_tab_index
    else if (active_tab_index > tab_index) then
      ! Closed tab before active - adjust index
      active_tab_index = active_tab_index - 1
    end if
  end subroutine close_tab

  ! Switch to a different tab
  subroutine switch_to_tab(tab_index)
    integer, intent(in) :: tab_index

    if (tab_index < 1 .or. tab_index > num_tabs) then
      print *, "ERROR: Invalid tab index: ", tab_index
      return
    end if

    if (tab_index == active_tab_index) then
      ! Already on this tab
      return
    end if

    print *, "Switching from tab ", active_tab_index, " to tab ", tab_index

    ! Just update the index - actual UI update happens in caller
    active_tab_index = tab_index
  end subroutine switch_to_tab

  ! Get pointer to active tab
  function get_active_tab() result(tab)
    type(tab_state), pointer :: tab
    if (num_tabs == 0) then
      tab => null()
    else
      tab => tabs(active_tab_index)
    end if
  end function get_active_tab

  ! Get pointer to specific tab
  function get_tab(tab_index) result(tab)
    integer, intent(in) :: tab_index
    type(tab_state), pointer :: tab
    if (tab_index < 1 .or. tab_index > num_tabs) then
      tab => null()
    else
      tab => tabs(tab_index)
    end if
  end function get_tab

  ! Helper: Extract basename from path
  function get_path_basename(path) result(basename)
    character(len=*), intent(in) :: path
    character(len=256) :: basename
    integer :: last_slash

    ! Find last slash
    last_slash = index(trim(path), "/", back=.true.)

    if (last_slash == 0) then
      ! No slash - use whole path
      basename = trim(path)
    else if (last_slash == len_trim(path)) then
      ! Trailing slash - find previous slash
      last_slash = index(trim(path(1:len_trim(path)-1)), "/", back=.true.)
      if (last_slash == 0) then
        basename = trim(path(1:len_trim(path)-1))
      else
        basename = trim(path(last_slash+1:len_trim(path)-1))
      end if
    else
      ! Normal case
      basename = trim(path(last_slash+1:))
    end if

    ! Special case: root
    if (len_trim(basename) == 0) then
      basename = "/"
    end if
  end function get_path_basename

end module tab_manager
