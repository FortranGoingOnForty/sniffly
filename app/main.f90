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
  implicit none

  integer :: exit_status, nargs
  character(len=512) :: arg, scan_dir

  ! Print banner
  print '(A)', "======================================"
  print '(A)', "    Sniffly v0.1.0 - Alpha"
  print '(A)', "    Disk Space Analyzer"
  print '(A)', "    Pure Fortran + GTK4"
  print '(A)', "======================================"
  print '(A)', ""

  ! Parse command-line arguments
  nargs = command_argument_count()

  if (nargs > 0) then
    call get_command_argument(1, arg)
    scan_dir = trim(arg)
    print '(A,A)', "Directory to scan: ", trim(scan_dir)
    call sniffly_set_scan_path(scan_dir)
  else
    print '(A)', "Usage: sniffly [directory]"
    print '(A)', "No directory specified, will use default"
    print '(A)', ""
  end if

  ! Run the GTK application (enters main loop)
  exit_status = sniffly_app_run()

  ! Exit with appropriate status
  if (exit_status /= 0) then
    print '(A,I0)', "ERROR: Application exited with status ", exit_status
    stop 1
  end if

  print '(A)', ""
  print '(A)', "Sniffly closed successfully. Goodbye!"

end program sniffly_main
