! Progressive Scanner Module for Sniffly
! Implements breadth-first scanning with idle callbacks for real-time treemap updates
module progressive_scanner
  use, intrinsic :: iso_c_binding
  use iso_fortran_env, only: int64
  use types, only: file_node, rgb_color
  implicit none
  private

  public :: start_progressive_scan, stop_progressive_scan, is_scan_active, &
            get_scan_progress, register_scan_update_callback, register_scan_complete_callback, &
            register_initial_level_complete_callback, set_show_hidden_files

  ! Hidden files visibility setting
  logical, save :: show_hidden_files = .true.

  ! Scan queue entry
  type :: queue_entry
    character(len=512) :: path
    integer :: node_index  ! Index in parent's children array
    integer :: parent_id   ! ID to track parent (for tree building)
    integer :: depth
  end type queue_entry

  ! Scan state
  type :: scan_state_type
    logical :: active
    integer :: total_dirs_found
    integer :: dirs_scanned
    real :: progress  ! 0.0 to 1.0

    ! Queue for breadth-first scanning
    type(queue_entry), dimension(10000) :: queue
    integer :: queue_head
    integer :: queue_tail
    integer :: queue_size

    ! Root node being built
    type(file_node), pointer :: root => null()
    character(len=512) :: root_path
  end type scan_state_type

  type(scan_state_type), save :: scan_state

  ! Callback for scan updates (called after each directory is scanned)
  abstract interface
    subroutine scan_update_callback()
    end subroutine scan_update_callback
  end interface

  ! Callback for scan completion
  abstract interface
    subroutine scan_complete_callback()
    end subroutine scan_complete_callback
  end interface

  ! Callback for initial level (depth 0) completion
  abstract interface
    subroutine initial_level_callback()
    end subroutine initial_level_callback
  end interface

  procedure(scan_update_callback), pointer, save :: update_callback => null()
  procedure(scan_complete_callback), pointer, save :: complete_callback => null()
  procedure(initial_level_callback), pointer, save :: initial_level_cb => null()

contains

  ! Get current time in milliseconds (for flash timing)
  function get_time_ms() result(time_ms)
    integer(int64) :: time_ms
    integer :: count, count_rate, count_max

    call system_clock(count, count_rate, count_max)
    ! Convert to milliseconds
    time_ms = int(count * 1000_int64 / count_rate, int64)
  end function get_time_ms

  ! Register callback to be called after each scan update
  subroutine register_scan_update_callback(callback)
    procedure(scan_update_callback) :: callback
    update_callback => callback
  end subroutine register_scan_update_callback

  ! Register callback to be called when scan completes
  subroutine register_scan_complete_callback(callback)
    procedure(scan_complete_callback) :: callback
    complete_callback => callback
  end subroutine register_scan_complete_callback

  ! Register callback to be called when initial level (depth 0) completes
  subroutine register_initial_level_complete_callback(callback)
    procedure(initial_level_callback) :: callback
    initial_level_cb => callback
  end subroutine register_initial_level_complete_callback

  ! Start progressive scan of a directory
  subroutine start_progressive_scan(root_node, path)
    use g, only: g_idle_add
    type(file_node), target, intent(inout) :: root_node
    character(len=*), intent(in) :: path
    integer(c_int) :: idle_id

    print *, "=== STARTING PROGRESSIVE SCAN ==="
    print *, "Path: ", trim(path)

    ! Initialize scan state
    scan_state%active = .true.
    scan_state%total_dirs_found = 1
    scan_state%dirs_scanned = 0
    scan_state%progress = 0.0
    scan_state%queue_head = 1
    scan_state%queue_tail = 0
    scan_state%queue_size = 0
    scan_state%root => root_node
    scan_state%root_path = trim(path)

    ! Initialize root node
    root_node%path = trim(path)
    root_node%name = extract_filename(path)
    root_node%is_directory = .true.
    root_node%scan_complete = .false.
    root_node%is_scanning = .true.
    root_node%estimated_size = 0_int64
    root_node%size = 0_int64
    root_node%num_children = 0

    ! Enqueue root directory
    call enqueue(path, 0, 0, 0)

    ! Register idle callback to process queue
    print *, "Registering idle callback for progressive scanning"
    idle_id = g_idle_add(c_funloc(scan_one_directory_idle), c_null_ptr)
  end subroutine start_progressive_scan

  ! Stop the current scan
  subroutine stop_progressive_scan()
    print *, "=== STOPPING PROGRESSIVE SCAN ==="
    scan_state%active = .false.
    scan_state%queue_size = 0
    scan_state%root => null()
  end subroutine stop_progressive_scan

  ! Check if a scan is currently active
  function is_scan_active() result(active)
    logical :: active
    active = scan_state%active
  end function is_scan_active

  ! Get current scan progress (0.0 to 1.0)
  function get_scan_progress() result(progress)
    real :: progress
    if (scan_state%total_dirs_found > 0) then
      progress = real(scan_state%dirs_scanned) / real(scan_state%total_dirs_found)
    else
      progress = 0.0
    end if
  end function get_scan_progress

  ! Idle callback - scan one directory per call
  function scan_one_directory_idle(user_data) bind(c) result(continue)
    type(c_ptr), value :: user_data
    integer(c_int) :: continue
    type(queue_entry) :: entry

    ! Check if we should stop
    if (.not. scan_state%active .or. scan_state%queue_size == 0) then
      print *, "Progressive scan complete or stopped"
      scan_state%active = .false.
      if (associated(scan_state%root)) then
        scan_state%root%scan_complete = .true.
        scan_state%root%is_scanning = .false.
      end if
      ! Call completion callback
      if (associated(complete_callback)) then
        call complete_callback()
      end if
      continue = 0_c_int  ! Stop calling
      return
    end if

    ! Dequeue next directory
    entry = dequeue()

    ! Scan the directory (pass the parent_id which tracks the root child index)
    call scan_single_directory(entry%path, entry%depth, entry%parent_id)

    scan_state%dirs_scanned = scan_state%dirs_scanned + 1
    scan_state%progress = get_scan_progress()

    ! Trigger update callback
    if (associated(update_callback)) then
      call update_callback()
    end if

    ! Continue if there are more directories
    if (scan_state%queue_size > 0) then
      continue = 1_c_int  ! Keep calling
    else
      print *, "Progressive scan complete!"
      scan_state%active = .false.
      if (associated(scan_state%root)) then
        scan_state%root%scan_complete = .true.
        scan_state%root%is_scanning = .false.

        ! Now that all sizes have been accumulated, group small files
        print *, "Grouping small files after scan completion..."
        call group_small_files_root()
      end if
      ! Call completion callback
      if (associated(complete_callback)) then
        call complete_callback()
      end if
      continue = 0_c_int  ! Stop calling
    end if
  end function scan_one_directory_idle

  ! Scan a single directory and enqueue its subdirectories
  subroutine scan_single_directory(path, depth, root_child_index)
    use file_system, only: list_directory, is_directory, get_file_size, is_symlink
    character(len=*), intent(in) :: path
    integer, intent(in) :: depth, root_child_index
    character(len=256), dimension(10000) :: entries
    character(len=512) :: child_path
    integer :: num_entries, i, child_count
    integer(int64) :: file_size
    type(file_node), dimension(:), allocatable :: temp_children

    print *, "Scanning: ", trim(path), " (depth=", depth, ")"

    ! List directory contents
    num_entries = list_directory(path, entries, 10000)
    print *, "  Found ", num_entries, " entries"

    if (.not. associated(scan_state%root)) return

    ! For root directory (depth 0), build the children array
    if (depth == 0) then
      ! Count valid entries (non-symlinks, respect hidden file setting)
      child_count = 0
      do i = 1, num_entries
        if (len_trim(entries(i)) == 0) cycle
        ! Skip hidden files if show_hidden_files is false
        if (.not. show_hidden_files .and. is_hidden_file(entries(i))) cycle
        child_path = trim(path) // "/" // trim(entries(i))
        if (.not. is_symlink(child_path)) then
          child_count = child_count + 1
        end if
      end do

      print *, "  Creating ", child_count, " child nodes for root"

      ! Allocate children array for root
      if (child_count > 0) then
        allocate(temp_children(child_count))
        child_count = 0

        ! Create child nodes and track which array index each child gets
        do i = 1, num_entries
          if (len_trim(entries(i)) == 0) cycle
          ! Skip hidden files if show_hidden_files is false
          if (.not. show_hidden_files .and. is_hidden_file(entries(i))) cycle
          child_path = trim(path) // "/" // trim(entries(i))
          if (is_symlink(child_path)) cycle

          child_count = child_count + 1
          temp_children(child_count)%name = trim(entries(i))
          temp_children(child_count)%path = trim(child_path)
          temp_children(child_count)%is_directory = is_directory(child_path)

          if (temp_children(child_count)%is_directory) then
            ! Directory - will be scanned later
            temp_children(child_count)%size = 0_int64
            temp_children(child_count)%num_children = 0
            temp_children(child_count)%scan_complete = .false.
            temp_children(child_count)%is_scanning = .true.
            ! Enqueue subdirectory - pass the ACTUAL array index (child_count) as root_child_index
            print *, "  Enqueueing ", trim(entries(i)), " as root child index ", child_count
            call enqueue(child_path, child_count, child_count, depth + 1)
            scan_state%total_dirs_found = scan_state%total_dirs_found + 1
          else
            ! File - get size immediately
            file_size = get_file_size(child_path)
            temp_children(child_count)%size = file_size
            temp_children(child_count)%num_children = 0
            temp_children(child_count)%scan_complete = .true.
            temp_children(child_count)%is_scanning = .false.
            ! Add to root's total
            scan_state%root%estimated_size = scan_state%root%estimated_size + file_size
            scan_state%root%size = scan_state%root%estimated_size
          end if
        end do

        ! Assign children to root
        if (allocated(scan_state%root%children)) deallocate(scan_state%root%children)
        allocate(scan_state%root%children(child_count))
        scan_state%root%children = temp_children
        scan_state%root%num_children = child_count
        deallocate(temp_children)

        print *, "  Root now has ", scan_state%root%num_children, " children"

        ! DEBUG: Print first 10 directory children to verify indexing
        do i = 1, min(20, scan_state%root%num_children)
          if (scan_state%root%children(i)%is_directory) then
            print *, "    Child ", i, ": ", trim(scan_state%root%children(i)%name), " (directory)"
          end if
        end do

        ! Color the tree before showing it (don't group yet - sizes are still accumulating)
        call color_root_children()

        ! Call initial level callback (so UI can start rendering)
        if (associated(initial_level_cb)) then
          print *, "Initial level scan complete - notifying callback"
          call initial_level_cb()
        end if
      end if
    else
      ! For subdirectories (depth > 0), accumulate sizes by matching path prefixes
      do i = 1, num_entries
        if (len_trim(entries(i)) == 0) cycle
        ! Skip hidden files if show_hidden_files is false
        if (.not. show_hidden_files .and. is_hidden_file(entries(i))) cycle
        child_path = trim(path) // "/" // trim(entries(i))
        if (is_symlink(child_path)) cycle

        if (is_directory(child_path)) then
          ! Enqueue subdirectory for later scanning - propagate root child index
          call enqueue(child_path, 0, root_child_index, depth + 1)
          scan_state%total_dirs_found = scan_state%total_dirs_found + 1
        else
          ! It's a file - find which root child it belongs to by path matching
          file_size = get_file_size(child_path)

          ! Find the root child whose path is a prefix of this file's path
          call find_and_update_root_child(child_path, file_size)

          ! Also update root total
          scan_state%root%estimated_size = scan_state%root%estimated_size + file_size
          scan_state%root%size = scan_state%root%estimated_size
        end if
      end do
    end if
  end subroutine scan_single_directory

  ! Find which root child a file belongs to and update its size
  subroutine find_and_update_root_child(file_path, file_size)
    character(len=*), intent(in) :: file_path
    integer(int64), intent(in) :: file_size
    integer :: root_idx
    integer :: path_len, child_path_len
    logical :: found

    if (.not. associated(scan_state%root)) return
    if (scan_state%root%num_children == 0) return

    found = .false.

    ! Try to find a root child whose path is a prefix of this file's path
    do root_idx = 1, scan_state%root%num_children
      if (.not. scan_state%root%children(root_idx)%is_directory) cycle

      child_path_len = len_trim(scan_state%root%children(root_idx)%path)
      path_len = len_trim(file_path)

      ! Check if child path is a prefix of file path
      ! Also ensure we match directory boundaries (check for '/' after the prefix)
      if (path_len > child_path_len) then
        if (file_path(1:child_path_len) == scan_state%root%children(root_idx)%path(1:child_path_len)) then
          ! Ensure we're matching at a directory boundary
          if (file_path(child_path_len+1:child_path_len+1) == '/') then
            ! Found the matching root child!
            scan_state%root%children(root_idx)%size = &
              scan_state%root%children(root_idx)%size + file_size

            ! Mark node for flash highlighting
            scan_state%root%children(root_idx)%flash_intensity = 1.0d0
            scan_state%root%children(root_idx)%last_update_time = get_time_ms()

            if (scan_state%dirs_scanned < 5) then
              print *, "  Path-matched: ", trim(file_path), " -> root child ", root_idx, &
                       " (", trim(scan_state%root%children(root_idx)%name), ")"
            end if
            found = .true.
            exit
          end if
        end if
      end if
    end do

    if (.not. found .and. scan_state%dirs_scanned < 5) then
      print *, "  WARNING: No root child found for: ", trim(file_path)
    end if
  end subroutine find_and_update_root_child

  ! Enqueue a directory for scanning
  subroutine enqueue(path, node_index, parent_id, depth)
    character(len=*), intent(in) :: path
    integer, intent(in) :: node_index, parent_id, depth

    if (scan_state%queue_size >= 10000) then
      print *, "WARNING: Queue full! Skipping: ", trim(path)
      return
    end if

    scan_state%queue_tail = scan_state%queue_tail + 1
    if (scan_state%queue_tail > 10000) scan_state%queue_tail = 1

    scan_state%queue(scan_state%queue_tail)%path = trim(path)
    scan_state%queue(scan_state%queue_tail)%node_index = node_index
    scan_state%queue(scan_state%queue_tail)%parent_id = parent_id
    scan_state%queue(scan_state%queue_tail)%depth = depth
    scan_state%queue_size = scan_state%queue_size + 1
  end subroutine enqueue

  ! Dequeue next directory
  function dequeue() result(entry)
    type(queue_entry) :: entry

    if (scan_state%queue_size == 0) then
      entry%path = ""
      return
    end if

    entry = scan_state%queue(scan_state%queue_head)
    scan_state%queue_head = scan_state%queue_head + 1
    if (scan_state%queue_head > 10000) scan_state%queue_head = 1
    scan_state%queue_size = scan_state%queue_size - 1
  end function dequeue

  ! Extract filename from path
  pure function extract_filename(path) result(filename)
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: filename
    integer :: i, last_slash

    last_slash = 0
    do i = len_trim(path), 1, -1
      if (path(i:i) == '/' .or. path(i:i) == '\') then
        last_slash = i
        exit
      end if
    end do

    if (last_slash > 0) then
      filename = trim(path(last_slash+1:))
    else
      filename = trim(path)
    end if
  end function extract_filename

  ! Apply colors to root's children based on file type
  subroutine color_root_children()
    use iso_fortran_env, only: real64
    integer :: i, dot_pos
    character(len=256) :: extension
    real(real64) :: hue
    integer :: j

    if (.not. associated(scan_state%root)) return
    if (.not. allocated(scan_state%root%children)) return

    do i = 1, scan_state%root%num_children
      if (scan_state%root%children(i)%is_directory) then
        ! Directory - use blue
        scan_state%root%children(i)%color%r = 0.4d0
        scan_state%root%children(i)%color%g = 0.6d0
        scan_state%root%children(i)%color%b = 0.9d0
      else
        ! File - determine color by extension
        extension = ""
        dot_pos = 0
        do j = len_trim(scan_state%root%children(i)%name), 1, -1
          if (scan_state%root%children(i)%name(j:j) == '.') then
            dot_pos = j
            exit
          end if
        end do

        if (dot_pos > 0) then
          extension = scan_state%root%children(i)%name(dot_pos+1:)
        end if

        ! Color by file type
        select case (trim(extension))
          case ('jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'ico', 'webp')
            hue = 300.0d0  ! Magenta for images
          case ('mp3', 'wav', 'flac', 'ogg', 'aac', 'm4a')
            hue = 180.0d0  ! Cyan for audio
          case ('mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv')
            hue = 270.0d0  ! Purple for video
          case ('pdf', 'doc', 'docx', 'txt', 'odt', 'rtf')
            hue = 30.0d0   ! Orange for documents
          case ('zip', 'tar', 'gz', 'rar', '7z', 'bz2', 'xz')
            hue = 60.0d0   ! Yellow for archives
          case ('exe', 'dll', 'so', 'app', 'dmg', 'pkg')
            hue = 0.0d0    ! Red for executables
          case ('c', 'cpp', 'h', 'hpp', 'f90', 'f95', 'py', 'java', 'js')
            hue = 120.0d0  ! Green for source code
          case ('iso', 'img')
            hue = 330.0d0  ! Pink for disk images
          case default
            hue = 200.0d0  ! Light blue for other files
        end select

        call set_color_from_hsv(scan_state%root%children(i)%color, hue, 0.7d0, 0.9d0)
      end if
    end do
  end subroutine color_root_children

  ! Convert HSV to RGB and set color
  subroutine set_color_from_hsv(color, h, s, v)
    use iso_fortran_env, only: real64
    type(rgb_color), intent(out) :: color
    real(real64), intent(in) :: h, s, v
    real(real64) :: c, x, m, h_prime
    integer :: h_i

    c = v * s
    h_prime = h / 60.0d0
    h_i = int(h_prime)
    x = c * (1.0d0 - abs(mod(h_prime, 2.0d0) - 1.0d0))
    m = v - c

    select case (h_i)
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
  end subroutine set_color_from_hsv

  ! Group small files at root level
  subroutine group_small_files_root()
    use disk_scanner, only: group_small_files

    if (.not. associated(scan_state%root)) return
    call group_small_files(scan_state%root)
  end subroutine group_small_files_root

  ! Set whether to show hidden files (dotfiles)
  subroutine set_show_hidden_files(show)
    logical, intent(in) :: show
    show_hidden_files = show
    print *, "Progressive scanner: show_hidden_files = ", show_hidden_files
  end subroutine set_show_hidden_files

  ! Check if a filename is hidden (starts with '.')
  pure function is_hidden_file(filename) result(is_hidden)
    character(len=*), intent(in) :: filename
    logical :: is_hidden

    is_hidden = .false.
    if (len_trim(filename) > 0) then
      if (filename(1:1) == '.') then
        is_hidden = .true.
      end if
    end if
  end function is_hidden_file

end module progressive_scanner
