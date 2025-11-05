! GTK4 Application Module for Sniffly
! Handles application initialization and main window setup
module gtk_app
  use, intrinsic :: iso_c_binding
  use gtk, only: gtk_init, gtk_application_new, gtk_application_window_new, &
                 gtk_window_set_title, gtk_window_set_default_size, &
                 gtk_window_present, G_APPLICATION_DEFAULT_FLAGS, &
                 gtk_application_get_active_window, gtk_window_destroy, &
                 gtk_window_set_child, g_signal_connect
  use g, only: g_application_run
  use treemap_widget, only: create_treemap_widget
  implicit none
  private

  public :: sniffly_app_run, sniffly_app_quit

  ! Application constants
  character(len=*), parameter :: APP_ID = "org.fortrangoingonforty.sniffly"
  character(len=*), parameter :: APP_TITLE = "Sniffly - Disk Space Analyzer"
  integer, parameter :: DEFAULT_WIDTH = 1024
  integer, parameter :: DEFAULT_HEIGHT = 768

  ! Global application pointer (will be set in activate callback)
  type(c_ptr), save :: app_ptr = c_null_ptr
  type(c_ptr), save :: main_window_ptr = c_null_ptr

contains

  ! Run the Sniffly GTK application
  function sniffly_app_run() result(status)
    integer :: status
    integer(c_int) :: c_status

    ! Initialize GTK
    call gtk_init()

    ! Create application
    app_ptr = gtk_application_new(APP_ID//c_null_char, &
                                   G_APPLICATION_DEFAULT_FLAGS)

    if (.not. c_associated(app_ptr)) then
      print *, "ERROR: Failed to create GTK application"
      status = 1
      return
    end if

    ! Connect activate signal (called when app starts)
    call g_signal_connect(app_ptr, "activate"//c_null_char, &
                           c_funloc(on_activate), c_null_ptr)

    ! Run the application (enters main loop)
    c_status = g_application_run(app_ptr, 0, [c_null_ptr])
    status = int(c_status)
  end function sniffly_app_run

  ! Quit the application
  subroutine sniffly_app_quit()
    if (c_associated(main_window_ptr)) then
      call gtk_window_destroy(main_window_ptr)
      main_window_ptr = c_null_ptr
    end if
  end subroutine sniffly_app_quit

  ! Callback when application activates (startup)
  subroutine on_activate(app, user_data) bind(c)
    type(c_ptr), value :: app, user_data
    type(c_ptr) :: drawing_area

    ! Create main window
    main_window_ptr = gtk_application_window_new(app)

    if (.not. c_associated(main_window_ptr)) then
      print *, "ERROR: Failed to create main window"
      return
    end if

    ! Set up window properties
    call gtk_window_set_title(main_window_ptr, APP_TITLE//c_null_char)
    call gtk_window_set_default_size(main_window_ptr, &
                                      int(DEFAULT_WIDTH, c_int), &
                                      int(DEFAULT_HEIGHT, c_int))

    ! Create treemap drawing area widget
    drawing_area = create_treemap_widget()

    if (.not. c_associated(drawing_area)) then
      print *, "ERROR: Failed to create treemap widget"
      return
    end if

    ! Add drawing area to window
    call gtk_window_set_child(main_window_ptr, drawing_area)

    ! TODO: Add menu bar, toolbar, status bar
    ! For now, just show window with drawing area

    ! Show the window
    call gtk_window_present(main_window_ptr)

    print *, "Sniffly started successfully!"
    print *, "Window size: ", DEFAULT_WIDTH, "x", DEFAULT_HEIGHT
  end subroutine on_activate

end module gtk_app
