! GTK4 Application Module for Sniffly
! Handles application initialization and main window setup
module gtk_app
  use, intrinsic :: iso_c_binding
  use gtk, only: gtk_init, gtk_application_new, gtk_application_window_new, &
                 gtk_window_set_title, gtk_window_set_default_size, &
                 gtk_window_present, G_APPLICATION_DEFAULT_FLAGS, &
                 gtk_application_get_active_window, gtk_window_destroy, &
                 gtk_window_set_child, g_signal_connect, &
                 gtk_box_new, gtk_box_append, GTK_ORIENTATION_VERTICAL, &
                 GTK_ORIENTATION_HORIZONTAL, gtk_button_new_with_label, &
                 gtk_widget_set_hexpand, gtk_widget_set_vexpand, &
                 gtk_label_new, gtk_label_set_text, gtk_widget_set_halign, &
                 GTK_ALIGN_START
  use g, only: g_application_run
  use treemap_widget, only: create_treemap_widget, set_scan_path, register_navigation_callback
  implicit none
  private

  public :: sniffly_app_run, sniffly_app_quit, sniffly_set_scan_path, &
            sniffly_update_status, sniffly_update_breadcrumbs, breadcrumb_callback

  ! Application constants
  character(len=*), parameter :: APP_ID = "org.fortrangoingonforty.sniffly"
  character(len=*), parameter :: APP_TITLE = "Sniffly - Disk Space Analyzer"
  integer, parameter :: DEFAULT_WIDTH = 1024
  integer, parameter :: DEFAULT_HEIGHT = 768

  ! Global application pointer (will be set in activate callback)
  type(c_ptr), save :: app_ptr = c_null_ptr
  type(c_ptr), save :: main_window_ptr = c_null_ptr
  type(c_ptr), save :: status_label_ptr = c_null_ptr
  type(c_ptr), save :: breadcrumb_label_ptr = c_null_ptr

  ! Global scan path (can be set via command line)
  character(len=512), save :: global_scan_path = ""

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

  ! Set the directory path to scan (call before sniffly_app_run)
  subroutine sniffly_set_scan_path(path)
    character(len=*), intent(in) :: path
    global_scan_path = trim(path)
    print *, "Scan path set to: ", trim(global_scan_path)
  end subroutine sniffly_set_scan_path

  ! Callback when application activates (startup)
  subroutine on_activate(app, user_data) bind(c)
    type(c_ptr), value :: app, user_data
    type(c_ptr) :: drawing_area, main_box, toolbar, scan_btn, quit_btn, status_bar, breadcrumb_bar
    character(len=512) :: scan_path

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

    ! Use global scan path or default
    if (len_trim(global_scan_path) > 0) then
      scan_path = global_scan_path
      print *, "Using specified directory: ", trim(scan_path)
    else
      scan_path = "/Users/matthewwolffe/Downloads"
      print *, "Using default directory: ", trim(scan_path)
    end if

    ! Create main vertical box (toolbar + treemap)
    main_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0_c_int)

    ! Create toolbar (horizontal box)
    toolbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5_c_int)

    ! Create Scan button
    scan_btn = gtk_button_new_with_label("Scan"//c_null_char)
    call g_signal_connect(scan_btn, "clicked"//c_null_char, &
                           c_funloc(on_scan_clicked), c_null_ptr)
    call gtk_box_append(toolbar, scan_btn)

    ! Create Quit button
    quit_btn = gtk_button_new_with_label("Quit"//c_null_char)
    call g_signal_connect(quit_btn, "clicked"//c_null_char, &
                           c_funloc(on_quit_clicked), c_null_ptr)
    call gtk_box_append(toolbar, quit_btn)

    ! Add toolbar to main box
    call gtk_box_append(main_box, toolbar)

    ! Create breadcrumb bar (horizontal box with path label)
    breadcrumb_bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5_c_int)
    breadcrumb_label_ptr = gtk_label_new(""//c_null_char)  ! Will be set by first render
    call gtk_widget_set_halign(breadcrumb_label_ptr, GTK_ALIGN_START)
    call gtk_box_append(breadcrumb_bar, breadcrumb_label_ptr)

    ! Add breadcrumb bar to main box
    call gtk_box_append(main_box, breadcrumb_bar)

    ! Create treemap drawing area widget
    drawing_area = create_treemap_widget()

    if (.not. c_associated(drawing_area)) then
      print *, "ERROR: Failed to create treemap widget"
      return
    end if

    ! Make drawing area expand to fill space
    call gtk_widget_set_hexpand(drawing_area, 1_c_int)
    call gtk_widget_set_vexpand(drawing_area, 1_c_int)

    ! Set the scan path
    call set_scan_path(scan_path)

    ! Register navigation callback for breadcrumb updates
    call register_navigation_callback(breadcrumb_callback)

    ! Initialize breadcrumb display (will update after first render)
    call sniffly_update_breadcrumbs()

    ! Add drawing area to main box
    call gtk_box_append(main_box, drawing_area)

    ! Create status bar (horizontal box with label)
    status_bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5_c_int)
    status_label_ptr = gtk_label_new("Ready to scan..."//c_null_char)
    call gtk_widget_set_halign(status_label_ptr, GTK_ALIGN_START)
    call gtk_box_append(status_bar, status_label_ptr)

    ! Add status bar to main box
    call gtk_box_append(main_box, status_bar)

    ! Add main box to window
    call gtk_window_set_child(main_window_ptr, main_box)

    ! Show the window
    call gtk_window_present(main_window_ptr)

    print *, "Sniffly started successfully!"
    print *, "Window size: ", DEFAULT_WIDTH, "x", DEFAULT_HEIGHT
  end subroutine on_activate

  ! Callback when Scan button is clicked
  subroutine on_scan_clicked(button, user_data) bind(c)
    type(c_ptr), value :: button, user_data
    print *, "Scan button clicked! (Directory chooser coming soon...)"
  end subroutine on_scan_clicked

  ! Callback when Quit button is clicked
  subroutine on_quit_clicked(button, user_data) bind(c)
    type(c_ptr), value :: button, user_data
    print *, "Quit button clicked"
    call sniffly_app_quit()
  end subroutine on_quit_clicked

  ! Update status bar with scan information
  subroutine sniffly_update_status(message)
    character(len=*), intent(in) :: message
    if (c_associated(status_label_ptr)) then
      call gtk_label_set_text(status_label_ptr, trim(message)//c_null_char)
    end if
  end subroutine sniffly_update_status

  ! Update breadcrumb bar with current path
  subroutine sniffly_update_breadcrumbs()
    use treemap_renderer, only: get_breadcrumb_path, get_path_depth
    character(len=256), dimension(100) :: names
    character(len=2048) :: path_str
    integer :: count, i

    if (.not. c_associated(breadcrumb_label_ptr)) return

    ! Get breadcrumb path from renderer
    call get_breadcrumb_path(names, count)

    ! Build path string with " > " separators
    path_str = ""
    do i = 1, count
      if (i > 1) then
        path_str = trim(path_str) // " > "
      end if
      path_str = trim(path_str) // trim(names(i))
    end do

    ! Update label
    call gtk_label_set_text(breadcrumb_label_ptr, trim(path_str)//c_null_char)
  end subroutine sniffly_update_breadcrumbs

  ! Callback wrapper for navigation events (no arguments)
  subroutine breadcrumb_callback()
    call sniffly_update_breadcrumbs()
  end subroutine breadcrumb_callback

end module gtk_app
