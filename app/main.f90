! Sniffly - Pure Fortran GUI Disk Space Analyzer
! Main program entry point
!
! Inspired by SpaceSniffer (Windows)
! Built with GTK4 and gtk-fortran
!
! Part of the FortranGoingOnForty project
! Proving Fortran can build beautiful GUI applications!

program sniffly_main
  use gtk_app
  use file_system, only: get_absolute_path, is_directory
  use version
  implicit none

  integer :: exit_status, nargs, iostat_val
  character(len=512) :: arg, scan_dir, home_dir
  character(len=:), allocatable :: abs_path
  logical :: has_terminal

  ! Check if we have a terminal (if not, skip print statements to avoid hanging)
  ! When launched from Finder, print statements can cause the app to hang
  inquire(unit=6, opened=has_terminal, iostat=iostat_val)
  if (iostat_val /= 0) has_terminal = .false.

  ! Print banner (only if terminal is available)
  if (has_terminal) then
    print '(A)', "======================================"
    print '(A)', "    " // SNIFFLY_NAME // " v" // SNIFFLY_VERSION
    print '(A)', "    " // SNIFFLY_DESCRIPTION
    print '(A)', "    Pure Fortran + GTK4"
    print '(A)', "======================================"
    print '(A)', ""
  end if

  ! Parse command-line arguments
  nargs = command_argument_count()

  if (nargs > 0) then
    call get_command_argument(1, arg)

    ! Handle flags
    if (trim(arg) == '--help' .or. trim(arg) == '-h') then
      call print_usage()
      stop 0
    else if (trim(arg) == '--version' .or. trim(arg) == '-v') then
      print '(A)', SNIFFLY_NAME // " version " // SNIFFLY_VERSION
      stop 0
    end if

    ! Validate directory path
    if (index(trim(arg), '--') == 1) then
      if (has_terminal) then
        print '(A)', "ERROR: Unknown option: " // trim(arg)
        print '(A)', "Try 'sniffly --help' for more information"
      end if
      stop 1
    end if

    ! Expand relative paths to absolute paths
    abs_path = get_absolute_path(trim(arg))
    scan_dir = abs_path

    ! Check if directory exists
    if (.not. is_directory(scan_dir)) then
      if (has_terminal) print '(A)', "ERROR: Not a valid directory: " // trim(scan_dir)
      stop 1
    end if

    if (has_terminal) print '(A,A)', "Directory to scan: ", trim(scan_dir)
    call sniffly_set_scan_path(scan_dir)
  else
    ! No directory specified - use home directory
    call get_environment_variable("HOME", home_dir)
    if (len_trim(home_dir) == 0) then
      home_dir = "/Users"  ! Fallback for macOS
    end if
    scan_dir = trim(home_dir)
    if (has_terminal) then
      print '(A)', "No directory specified, starting with home directory"
      print '(A,A)', "Directory to scan: ", trim(scan_dir)
    end if
    call sniffly_set_scan_path(scan_dir)
  end if

  ! Run the GTK application (enters main loop)
  exit_status = sniffly_app_run()

  ! Exit with appropriate status
  if (exit_status /= 0) then
    if (has_terminal) print '(A,I0)', "ERROR: Application exited with status ", exit_status
    stop 1
  end if

  if (has_terminal) then
    print '(A)', ""
    print '(A)', "Sniffly closed successfully. Goodbye!"
  end if

contains

  subroutine print_usage()
    print '(A)', ""
    print '(A)', "Usage: sniffly [OPTIONS] [DIRECTORY]"
    print '(A)', ""
    print '(A)', "A fast, visual disk space analyzer built with Fortran and GTK4"
    print '(A)', ""
    print '(A)', "Options:"
    print '(A)', "  -h, --help       Show this help message and exit"
    print '(A)', "  -v, --version    Show version information and exit"
    print '(A)', ""
    print '(A)', "Arguments:"
    print '(A)', "  DIRECTORY        Directory to analyze (default: home directory)"
    print '(A)', ""
    print '(A)', "Examples:"
    print '(A)', "  sniffly                   # Start with home directory"
    print '(A)', "  sniffly /Users/username   # Analyze specific directory"
    print '(A)', "  sniffly .                 # Analyze current directory"
    print '(A)', ""
  end subroutine print_usage

end program sniffly_main
