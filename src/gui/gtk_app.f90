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
                 GTK_ALIGN_START, gtk_progress_bar_new, gtk_progress_bar_set_fraction, &
                 gtk_progress_bar_set_text, gtk_progress_bar_set_show_text, &
                 gtk_widget_set_visible
  use g, only: g_application_run, g_idle_add
  use treemap_widget, only: create_treemap_widget, set_scan_path, register_navigation_callback, &
                             register_key_handler, register_quit_callback, mark_initial_scan_complete
  use treemap_renderer, only: register_progress_callback, scan_directory
  implicit none
  private

  public :: sniffly_app_run, sniffly_app_quit, sniffly_set_scan_path, &
            sniffly_update_status, sniffly_update_breadcrumbs, breadcrumb_callback, &
            sniffly_update_progress, sniffly_show_progress, sniffly_hide_progress

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
  type(c_ptr), save :: progress_bar_ptr = c_null_ptr

  ! Global scan path (can be set via command line)
  character(len=512), save :: global_scan_path = ""

  ! Scan path for async initial scan
  character(len=512), save :: pending_scan_path = ""

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
    integer(c_int) :: idle_id

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

    ! Create progress bar (always visible but starts at 0%)
    ! Place it in toolbar, expanded to fill remaining space (pushes to right)
    progress_bar_ptr = gtk_progress_bar_new()
    call gtk_progress_bar_set_show_text(progress_bar_ptr, 1_c_int)  ! Show percentage text
    call gtk_widget_set_hexpand(progress_bar_ptr, 1_c_int)  ! Expand horizontally to fill space
    call gtk_progress_bar_set_fraction(progress_bar_ptr, 0.0_c_double)  ! Start at 0%
    call gtk_box_append(toolbar, progress_bar_ptr)

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

    ! Register quit callback
    call register_quit_callback(quit_callback_wrapper)

    ! Register progress callbacks
    call register_progress_callback(sniffly_show_progress, sniffly_hide_progress, &
                                      sniffly_update_progress)

    ! Add drawing area to main box
    call gtk_box_append(main_box, drawing_area)

    ! Create status bar (horizontal box with label only)
    status_bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5_c_int)
    status_label_ptr = gtk_label_new("Preparing to scan..."//c_null_char)
    call gtk_widget_set_halign(status_label_ptr, GTK_ALIGN_START)
    call gtk_box_append(status_bar, status_label_ptr)

    ! Add status bar to main box
    call gtk_box_append(main_box, status_bar)

    ! Add main box to window
    call gtk_window_set_child(main_window_ptr, main_box)

    ! Register keyboard handler on window (not widget) for global keyboard capture
    call register_key_handler(main_window_ptr)

    ! Show the window first with "Scanning..." status
    call gtk_window_present(main_window_ptr)

    ! Store scan path for idle callback
    pending_scan_path = scan_path

    ! Schedule initial scan to run when GTK is idle (after window is shown)
    idle_id = g_idle_add(c_funloc(perform_initial_scan), c_null_ptr)

    print *, "Sniffly started successfully! Scan will begin shortly..."
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
    character(len=512) :: home_dir
    integer :: count, i, home_len, name_len
    logical :: is_home_path

    if (.not. c_associated(breadcrumb_label_ptr)) then
      print *, "WARNING: breadcrumb_label_ptr not associated!"
      return
    end if

    ! Get breadcrumb path from renderer
    call get_breadcrumb_path(names, count)
    print *, "Updating breadcrumbs: count=", count

    ! Get home directory from environment
    call get_environment_variable("HOME", home_dir)
    home_len = len_trim(home_dir)

    ! Build path string with "/" separators
    path_str = ""
    do i = 1, count
      if (i > 1) then
        path_str = trim(path_str) // "/"
      end if

      ! Check if this is the first element and starts with home directory
      if (i == 1 .and. home_len > 0) then
        name_len = len_trim(names(i))
        is_home_path = .false.

        ! Check if path starts with home directory
        if (name_len >= home_len) then
          if (names(i)(1:home_len) == home_dir(1:home_len)) then
            is_home_path = .true.
          end if
        end if

        if (is_home_path) then
          ! Replace home directory with ~
          if (name_len == home_len) then
            ! Exactly the home directory
            path_str = trim(path_str) // "~"
          else if (names(i)(home_len+1:home_len+1) == "/") then
            ! Home directory with subdirectory
            path_str = trim(path_str) // "~" // trim(names(i)(home_len+1:name_len))
          else
            ! Path contains home but isn't a direct child
            path_str = trim(path_str) // trim(names(i))
          end if
        else
          path_str = trim(path_str) // trim(names(i))
        end if
      else
        path_str = trim(path_str) // trim(names(i))
      end if
    end do

    print *, "Breadcrumb path: ", trim(path_str)

    ! Update label
    call gtk_label_set_text(breadcrumb_label_ptr, trim(path_str)//c_null_char)
  end subroutine sniffly_update_breadcrumbs

  ! Callback wrapper for navigation events (no arguments)
  subroutine breadcrumb_callback()
    call sniffly_update_breadcrumbs()
  end subroutine breadcrumb_callback

  ! Show progress bar (now just resets to prepare for updates)
  subroutine sniffly_show_progress()
    if (c_associated(progress_bar_ptr)) then
      call gtk_progress_bar_set_fraction(progress_bar_ptr, 0.0_c_double)
      call gtk_progress_bar_set_text(progress_bar_ptr, "0%"//c_null_char)
    end if
  end subroutine sniffly_show_progress

  ! Hide progress bar (now just resets to 0%)
  subroutine sniffly_hide_progress()
    if (c_associated(progress_bar_ptr)) then
      call gtk_progress_bar_set_fraction(progress_bar_ptr, 0.0_c_double)
      call gtk_progress_bar_set_text(progress_bar_ptr, ""//c_null_char)
    end if
  end subroutine sniffly_hide_progress

  ! Update progress bar and status text
  ! fraction: 0.0 to 1.0
  ! message: status text to show
  subroutine sniffly_update_progress(fraction, message)
    real(c_double), intent(in) :: fraction
    character(len=*), intent(in) :: message
    character(len=32) :: percent_str
    integer :: percent_int

    if (c_associated(progress_bar_ptr)) then
      ! Update progress bar fraction
      call gtk_progress_bar_set_fraction(progress_bar_ptr, fraction)

      ! Set percentage text
      percent_int = int(fraction * 100.0_c_double)
      write(percent_str, '(I0,A)') percent_int, '%'
      call gtk_progress_bar_set_text(progress_bar_ptr, trim(percent_str)//c_null_char)
    end if

    ! Update status label
    if (c_associated(status_label_ptr)) then
      call gtk_label_set_text(status_label_ptr, trim(message)//c_null_char)
    end if

    ! Note: We update widgets but GTK will handle rendering in its own event loop
    ! Frequent calls to this function will keep the UI updated
  end subroutine sniffly_update_progress

  ! Callback wrapper for quit events (no arguments)
  subroutine quit_callback_wrapper()
    call sniffly_app_quit()
  end subroutine quit_callback_wrapper

  ! Idle callback for async initial scan
  function perform_initial_scan(user_data) bind(c) result(continue)
    use gtk, only: gtk_widget_queue_draw
    use treemap_renderer, only: invalidate_layout
    type(c_ptr), value :: user_data
    integer(c_int) :: continue

    print *, "Performing initial scan in idle callback..."
    call scan_directory(pending_scan_path)

    ! Mark initial scan as complete so draw callback can proceed
    call mark_initial_scan_complete()

    ! Invalidate layout to force recalculation
    call invalidate_layout()

    ! Update breadcrumbs after scan
    call sniffly_update_breadcrumbs()

    ! Trigger redraw to show the scanned data
    if (c_associated(main_window_ptr)) then
      call gtk_widget_queue_draw(main_window_ptr)
    end if

    ! Return 0 to indicate this callback should not be called again
    continue = 0_c_int
  end function perform_initial_scan

end module gtk_app
