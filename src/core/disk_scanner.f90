module disk_scanner
  use, intrinsic :: iso_c_binding
  use types
  use file_system
  use iso_fortran_env, only: int64
  use g, only: g_main_context_default, g_main_context_iteration
  implicit none
  private

  public :: scan_directory, build_tree, calculate_sizes, dump_tree_debug, set_progress_callback

  ! Directories to skip (reduce scan time and avoid issues)
  character(len=*), parameter, dimension(7) :: SKIP_DIRS = &
    [character(len=20) :: '.git', '.svn', '.hg', 'node_modules', '__pycache__', 'build', '.claude']

  ! Small file grouping thresholds
  real, parameter :: SMALL_FILE_THRESHOLD = 0.005  ! 0.5% of parent size
  integer, parameter :: MIN_SMALL_FILES = 10        ! Minimum count to trigger grouping

  ! UI responsiveness - process GTK events every N directories
  integer, parameter :: DIRS_PER_UI_UPDATE = 10
  integer, save :: dir_scan_counter = 0

  ! Progress callback interface
  abstract interface
    subroutine progress_update_callback(fraction, message)
      use, intrinsic :: iso_c_binding
      real(c_double), intent(in) :: fraction
      character(len=*), intent(in) :: message
    end subroutine progress_update_callback
  end interface

  ! Progress callback pointer
  procedure(progress_update_callback), pointer, save :: progress_cb => null()

contains

  ! Set progress callback
  subroutine set_progress_callback(callback)
    procedure(progress_update_callback) :: callback
    progress_cb => callback
  end subroutine set_progress_callback

  ! Check if directory should be skipped
  function should_skip_dir(dirname) result(skip)
    character(len=*), intent(in) :: dirname
    logical :: skip
    integer :: i

    skip = .false.
    do i = 1, size(SKIP_DIRS)
      if (trim(dirname) == trim(SKIP_DIRS(i))) then
        skip = .true.
        return
      end if
    end do
  end function should_skip_dir

  ! Group small files into a synthetic node
  ! This modifies node%children in-place if grouping occurs
  subroutine group_small_files(node)
    type(file_node), intent(inout) :: node
    integer(int64) :: total_size, threshold_size, small_total
    integer :: i, small_count, large_count
    type(file_node), dimension(:), allocatable :: new_children
    integer :: large_idx, small_idx
    character(len=50) :: count_str

    ! Only group files in directories with children
    if (.not. node%is_directory .or. .not. allocated(node%children)) return
    if (node%num_children < MIN_SMALL_FILES) return

    ! Calculate total size of all children
    total_size = 0_int64
    do i = 1, node%num_children
      total_size = total_size + node%children(i)%size
    end do

    ! Calculate threshold (0.5% of total)
    threshold_size = int(real(total_size) * SMALL_FILE_THRESHOLD, int64)

    ! Count small files
    small_count = 0
    small_total = 0_int64
    do i = 1, node%num_children
      if (node%children(i)%size < threshold_size) then
        small_count = small_count + 1
        small_total = small_total + node%children(i)%size
      end if
    end do

    ! Only group if we have enough small files
    if (small_count < MIN_SMALL_FILES) return

    large_count = node%num_children - small_count
    print *, "Grouping ", small_count, " small files in: ", trim(node%name)

    ! Allocate new children array: large files + 1 synthetic node
    allocate(new_children(large_count + 1))

    ! Copy large files and build small files array
    large_idx = 0
    small_idx = 0

    ! First pass: collect large files
    do i = 1, node%num_children
      if (node%children(i)%size >= threshold_size) then
        large_idx = large_idx + 1
        ! Transfer ownership using move_alloc
        call move_file_node(node%children(i), new_children(large_idx))
      end if
    end do

    ! Create synthetic node for small files
    large_idx = large_idx + 1  ! This is where synthetic node goes
    new_children(large_idx)%is_directory = .true.
    new_children(large_idx)%access_denied = .false.
    new_children(large_idx)%size = small_total
    new_children(large_idx)%original_size = small_total  ! Initialize backup size
    new_children(large_idx)%num_children = small_count

    ! Format name with count
    write(count_str, '(A,I0,A)') "[", small_count, " small files]"
    new_children(large_idx)%name = trim(count_str)
    new_children(large_idx)%path = trim(node%path) // get_path_separator() // trim(count_str)

    ! Allocate children for synthetic node
    allocate(new_children(large_idx)%children(small_count))

    ! Second pass: collect small files into synthetic node
    small_idx = 0
    do i = 1, node%num_children
      if (node%children(i)%size < threshold_size) then
        small_idx = small_idx + 1
        call move_file_node(node%children(i), new_children(large_idx)%children(small_idx))
      end if
    end do

    ! Replace old children array with new one
    if (allocated(node%children)) deallocate(node%children)
    call move_alloc(new_children, node%children)
    node%num_children = large_count + 1

  end subroutine group_small_files

  ! Helper to move a file_node without deep copying
  subroutine move_file_node(from, to)
    type(file_node), intent(inout) :: from, to

    ! Move allocatable components
    if (allocated(from%name)) call move_alloc(from%name, to%name)
    if (allocated(from%path)) call move_alloc(from%path, to%path)
    if (allocated(from%children)) call move_alloc(from%children, to%children)

    ! Copy simple components
    to%size = from%size
    to%original_size = from%original_size
    to%is_directory = from%is_directory
    to%access_denied = from%access_denied
    to%num_children = from%num_children
    to%bounds = from%bounds
    to%color = from%color
    to%cushion = from%cushion
    to%is_selected = from%is_selected
    to%is_hovered = from%is_hovered
  end subroutine move_file_node

  ! Scan a directory and build a file tree (with optional depth limiting)
  recursive subroutine scan_directory(path, node, current_depth)
    character(len=*), intent(in) :: path
    type(file_node), intent(inout) :: node
    integer, intent(in), optional :: current_depth
    character(len=256), dimension(:), allocatable :: entries
    integer :: num_entries, i, valid_children, depth
    character(len=512) :: child_path
    integer, parameter :: MAX_DEPTH = 100
    integer, parameter :: MAX_FILES_PER_DIR = 10000
    type(c_ptr) :: context

    ! Handle depth parameter
    if (present(current_depth)) then
      depth = current_depth
    else
      depth = 0
      ! Reset counter at start of new top-level scan
      dir_scan_counter = 0
    end if

    ! Process GTK events periodically to keep UI responsive
    ! Only at top levels to avoid excessive overhead
    if (depth == 0 .or. (depth <= 3 .and. mod(dir_scan_counter, DIRS_PER_UI_UPDATE) == 0)) then
      context = g_main_context_default()
      do while (g_main_context_iteration(context, 0_c_int) /= 0_c_int)
      end do

      ! Update progress - estimate based on directories scanned
      ! Progress range: 0.3 to 0.80 (before color assignment at 0.85)
      if (associated(progress_cb) .and. dir_scan_counter > 0) then
        ! Logarithmic progress for better perceived speed
        ! log(60000)/11 ≈ 1.0, so this reaches ~80% after 60000 directories
        ! This prevents saturation at 80% for large directories like ~
        call progress_cb(0.3_c_double + 0.50_c_double * min(1.0_c_double, &
                        log(real(dir_scan_counter, c_double)) / 11.0_c_double), &
                        'Scanning directories...')
      end if
    end if

    ! Increment directory counter
    dir_scan_counter = dir_scan_counter + 1

    ! Set node properties
    node%path = path
    node%name = extract_filename(path)
    node%num_children = 0
    node%access_denied = .false.

    ! Check if this is a symbolic link - skip if so
    if (is_symlink(path)) then
      node%is_directory = .false.
      node%size = 0_int64
      node%original_size = 0_int64
      return
    end if

    node%is_directory = is_directory(path)

    if (node%is_directory) then
      ! Check depth limit
      if (depth >= MAX_DEPTH) then
        node%access_denied = .true.
        node%size = 0_int64
        node%original_size = 0_int64
        return
      end if

      ! Allocate entries array on heap instead of stack
      allocate(entries(MAX_FILES_PER_DIR))

      ! List directory contents (returns 0 on error/permission denied)
      num_entries = list_directory(path, entries, MAX_FILES_PER_DIR)
      print *, "DEBUG: list_directory('", trim(path), "') returned ", num_entries, " entries"

      ! If we got entries, scan them
      if (num_entries > 0) then
        ! First pass: count valid children
        valid_children = 0
        do i = 1, num_entries
          if (should_skip_dir(entries(i))) cycle
          child_path = trim(path) // get_path_separator() // trim(entries(i))
          if (is_symlink(child_path)) cycle
          valid_children = valid_children + 1
        end do

        ! Allocate exact size needed
        if (valid_children > 0) then
          allocate(node%children(valid_children))
          node%num_children = 0

          ! Second pass: scan children
          do i = 1, num_entries
            if (should_skip_dir(entries(i))) cycle
            child_path = trim(path) // get_path_separator() // trim(entries(i))
            if (is_symlink(child_path)) cycle

            ! Scan directly into node%children
            node%num_children = node%num_children + 1
            call scan_directory(child_path, node%children(node%num_children), depth + 1)
          end do
        end if
      end if

      ! Calculate directory size as sum of children
      node%size = 0_int64
      if (allocated(node%children)) then
        do i = 1, node%num_children
          node%size = node%size + node%children(i)%size
        end do
      end if

      ! Group small files into synthetic node if applicable
      call group_small_files(node)

      ! Initialize original_size backup (for filter restoration)
      node%original_size = node%size

      ! Deallocate entries array
      if (allocated(entries)) deallocate(entries)
    else
      ! File - get size directly
      node%size = get_file_size(path)
      ! Initialize original_size backup (for filter restoration)
      node%original_size = node%size
    end if
  end subroutine scan_directory

  ! Build tree from a root path
  subroutine build_tree(root_path, root_node)
    character(len=*), intent(in) :: root_path
    type(file_node), intent(out) :: root_node

    call scan_directory(root_path, root_node)
  end subroutine build_tree

  ! Calculate cumulative sizes (stub - already done in scan_directory)
  recursive subroutine calculate_sizes(node)
    type(file_node), intent(inout) :: node
    integer :: i

    if (node%is_directory .and. allocated(node%children)) then
      node%size = 0_int64
      do i = 1, node%num_children
        call calculate_sizes(node%children(i))
        node%size = node%size + node%children(i)%size
      end do
    end if
  end subroutine calculate_sizes

  ! Extract filename from path
  function extract_filename(path) result(filename)
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: filename
    integer :: last_sep, i
    character(len=1) :: sep

    sep = get_path_separator()
    last_sep = 0

    do i = len_trim(path), 1, -1
      if (path(i:i) == sep) then
        last_sep = i
        exit
      end if
    end do

    if (last_sep > 0 .and. last_sep < len_trim(path)) then
      filename = trim(path(last_sep+1:))
    else
      filename = trim(path)
    end if
  end function extract_filename

  ! Debug function to dump tree structure to file
  subroutine dump_tree_debug(node, filename)
    type(file_node), intent(in) :: node
    character(len=*), intent(in) :: filename
    integer :: unit, ios

    open(newunit=unit, file=filename, status='replace', iostat=ios)
    if (ios /= 0) then
      print *, "Warning: Could not open debug file: ", trim(filename)
      return
    end if

    write(unit, '(A)') '=== TREE STRUCTURE DEBUG ==='
    call dump_node_recursive(node, unit, 0)
    close(unit)
  end subroutine dump_tree_debug

  ! Recursive helper for dump_tree_debug
  recursive subroutine dump_node_recursive(node, unit, depth)
    type(file_node), intent(in) :: node
    integer, intent(in) :: unit, depth
    character(len=512) :: indent
    integer :: i
    character(len=20) :: size_str

    ! Build indent string
    indent = ''
    do i = 1, depth * 2
      indent(i:i) = ' '
    end do

    ! Format size
    if (node%size < 1024_int64) then
      write(size_str, '(I0,A)') node%size, 'B'
    else if (node%size < 1024_int64**2) then
      write(size_str, '(F0.2,A)') real(node%size)/1024.0, 'KB'
    else if (node%size < 1024_int64**3) then
      write(size_str, '(F0.2,A)') real(node%size)/(1024.0**2), 'MB'
    else
      write(size_str, '(F0.2,A)') real(node%size)/(1024.0**3), 'GB'
    end if

    ! Write node info
    if (node%is_directory) then
      write(unit, '(A,A,A,A,A,A,I0,A)') trim(indent(1:depth*2)), '[DIR] ', &
        trim(node%name), ' (', trim(size_str), ', ', node%num_children, ' children)'
    else
      write(unit, '(A,A,A,A,A,A)') trim(indent(1:depth*2)), '[FILE] ', &
        trim(node%name), ' (', trim(size_str), ')'
    end if

    ! Recurse into children
    if (allocated(node%children)) then
      do i = 1, node%num_children
        call dump_node_recursive(node%children(i), unit, depth + 1)
      end do
    end if
  end subroutine dump_node_recursive

end module disk_scanner
