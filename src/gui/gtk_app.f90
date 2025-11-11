! GTK4 Application Module for Sniffly
! Handles application initialization and main window setup
module gtk_app
  use, intrinsic :: iso_c_binding
  use gtk, only: gtk_init, gtk_application_new, gtk_application_window_new, &
                 gtk_window_set_title, gtk_window_set_default_size, &
                 gtk_window_present, G_APPLICATION_DEFAULT_FLAGS, &
                 gtk_application_get_active_window, gtk_window_destroy, &
                 gtk_window_set_child, g_signal_connect, &
                 gtk_box_new, gtk_box_append, gtk_box_remove, GTK_ORIENTATION_VERTICAL, &
                 GTK_ORIENTATION_HORIZONTAL, gtk_button_new_with_label, &
                 gtk_widget_set_hexpand, gtk_widget_set_vexpand, gtk_widget_get_first_child, &
                 gtk_label_new, gtk_label_set_text, gtk_widget_set_halign, &
                 GTK_ALIGN_START, gtk_progress_bar_new, gtk_progress_bar_set_fraction, &
                 gtk_progress_bar_set_text, gtk_progress_bar_set_show_text, &
                 gtk_widget_set_visible, gtk_widget_set_sensitive, &
                 gtk_button_new, gtk_button_set_icon_name, gtk_widget_set_tooltip_text, &
                 gtk_entry_new, gtk_entry_buffer_set_text, gtk_entry_get_buffer, &
                 gtk_editable_set_editable, gtk_editable_get_text, &
                 gtk_entry_set_placeholder_text, gtk_widget_add_css_class, &
                 gtk_widget_remove_css_class
  use gdk, only: gdk_display_get_default, gdk_display_get_clipboard, gdk_clipboard_set_text
  use g, only: g_application_run, g_idle_add
  use treemap_widget, only: create_treemap_widget, set_scan_path, register_navigation_callback, &
                             register_key_handler, register_quit_callback, register_delete_callback, &
                             register_refresh_callback, register_selection_callback, mark_initial_scan_complete, &
                             has_selection, get_selected_node_path
  use breadcrumb_widget, only: create_breadcrumb_widget, update_breadcrumb_cache, &
                                set_navigation_callback, get_previous_breadcrumb_path, &
                                clear_previous_breadcrumb_path
  use treemap_renderer, only: register_progress_callback, scan_directory, set_redraw_widget, &
                               register_scan_completion_callback
  implicit none
  private

  public :: sniffly_app_run, sniffly_app_quit, sniffly_set_scan_path, &
            sniffly_update_status, breadcrumb_callback, &
            sniffly_update_progress, sniffly_show_progress, sniffly_hide_progress, &
            sniffly_update_status_bar_stats, get_forward_path

  ! Application constants
  character(len=*), parameter :: APP_ID = "org.fortrangoingonforty.sniffly"
  character(len=*), parameter :: APP_TITLE = "Sniffly - Disk Space Analyzer"
  integer, parameter :: DEFAULT_WIDTH = 1024
  integer, parameter :: DEFAULT_HEIGHT = 768

  ! Global application pointer (will be set in activate callback)
  type(c_ptr), save :: app_ptr = c_null_ptr
  type(c_ptr), save :: main_window_ptr = c_null_ptr
  type(c_ptr), save :: status_label_ptr = c_null_ptr
  type(c_ptr), save :: progress_bar_ptr = c_null_ptr
  type(c_ptr), save :: path_entry_ptr = c_null_ptr

  ! Shutdown flag - set when app is closing to prevent widget access
  logical, save :: app_is_shutting_down = .false.

  ! Global scan path (can be set via command line)
  character(len=512), save :: global_scan_path = ""

  ! Scan path for async initial scan
  character(len=512), save :: pending_scan_path = ""

  ! Navigation history for Back/Forward buttons
  integer, parameter :: MAX_HISTORY = 50
  character(len=512), dimension(MAX_HISTORY), save :: nav_history
  integer, save :: nav_history_count = 0
  integer, save :: nav_history_pos = 0  ! Current position in history (0 = no history)
  logical, save :: navigating_history = .false.  ! Flag: are we using back/forward?

  ! Button pointers for enabling/disabling
  type(c_ptr), save :: back_btn_ptr = c_null_ptr
  type(c_ptr), save :: forward_btn_ptr = c_null_ptr
  type(c_ptr), save :: cancel_scan_btn_ptr = c_null_ptr

  ! Selection-dependent button pointers
  type(c_ptr), save :: info_btn_ptr = c_null_ptr
  type(c_ptr), save :: copy_path_btn_ptr = c_null_ptr
  type(c_ptr), save :: open_finder_btn_ptr = c_null_ptr
  type(c_ptr), save :: delete_btn_ptr = c_null_ptr

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
    use progressive_scanner, only: stop_progressive_scan
    ! Set shutdown flag first to prevent callbacks from accessing widgets
    app_is_shutting_down = .true.

    ! Stop any active scans before destroying window
    call stop_progressive_scan()

    if (c_associated(main_window_ptr)) then
      call gtk_window_destroy(main_window_ptr)
    end if

    ! Nullify all widget pointers to prevent access after destruction
    main_window_ptr = c_null_ptr
    status_label_ptr = c_null_ptr
    progress_bar_ptr = c_null_ptr
    path_entry_ptr = c_null_ptr
    back_btn_ptr = c_null_ptr
    forward_btn_ptr = c_null_ptr
    cancel_scan_btn_ptr = c_null_ptr
  end subroutine sniffly_app_quit

  ! Set the directory path to scan (call before sniffly_app_run)
  subroutine sniffly_set_scan_path(path)
    character(len=*), intent(in) :: path
    global_scan_path = trim(path)
    print *, "Scan path set to: ", trim(global_scan_path)
  end subroutine sniffly_set_scan_path

  ! Callback when window close button (X) is clicked
  function on_window_close_request(window, user_data) bind(c) result(stop_propagation)
    use progressive_scanner, only: stop_progressive_scan
    type(c_ptr), value :: window, user_data
    integer(c_int) :: stop_propagation

    print *, "Window close button clicked - stopping scan and cleaning up"

    ! Set shutdown flag first to prevent callbacks from accessing widgets
    app_is_shutting_down = .true.

    ! Stop any active scans
    call stop_progressive_scan()

    ! Nullify all widget pointers to prevent access after destruction
    ! (The window will be destroyed by GTK after we return FALSE)
    status_label_ptr = c_null_ptr
    progress_bar_ptr = c_null_ptr
    path_entry_ptr = c_null_ptr
    back_btn_ptr = c_null_ptr
    forward_btn_ptr = c_null_ptr
    main_window_ptr = c_null_ptr

    ! Return FALSE (0) to allow the window to close
    stop_propagation = 0_c_int
  end function on_window_close_request

  ! Callback when application activates (startup)
  subroutine on_activate(app, user_data) bind(c)
    type(c_ptr), value :: app, user_data
    type(c_ptr) :: drawing_area, main_box, toolbar, open_dir_btn, scan_btn, cancel_scan_btn, back_btn, forward_btn, up_btn, open_finder_btn, copy_path_btn, info_btn, toggle_dotfiles_btn, toggle_ext_btn, toggle_render_btn, delete_btn, status_bar, breadcrumb_widget
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

    ! Connect close-request signal to handle window close button (X)
    call g_signal_connect(main_window_ptr, "close-request"//c_null_char, &
                           c_funloc(on_window_close_request), c_null_ptr)

    ! Use global scan path or home directory
    if (len_trim(global_scan_path) > 0) then
      scan_path = global_scan_path
      print *, "Using specified directory: ", trim(scan_path)
    else
      ! No directory specified - use home directory and prompt user
      scan_path = get_home_directory()
      print *, "No directory specified, using home directory: ", trim(scan_path)
      print *, "Click the folder icon to select a different directory"
    end if

    ! Create main vertical box (toolbar + treemap)
    main_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0_c_int)

    ! Create toolbar (horizontal box)
    toolbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5_c_int)

    ! Create Open Directory button with folder icon
    open_dir_btn = gtk_button_new()
    call gtk_button_set_icon_name(open_dir_btn, "folder-open"//c_null_char)
    call gtk_widget_set_tooltip_text(open_dir_btn, "Open Directory (Ctrl+O)"//c_null_char)
    call g_signal_connect(open_dir_btn, "clicked"//c_null_char, &
                           c_funloc(on_open_dir_clicked), c_null_ptr)
    call gtk_box_append(toolbar, open_dir_btn)

    ! Create path display entry (read-only)
    path_entry_ptr = gtk_entry_new()
    call gtk_editable_set_editable(path_entry_ptr, 0_c_int)  ! Make read-only
    call gtk_widget_set_hexpand(path_entry_ptr, 1_c_int)  ! Expand to fill space
    call gtk_widget_set_tooltip_text(path_entry_ptr, "Current scan path"//c_null_char)
    call gtk_box_append(toolbar, path_entry_ptr)

    ! Create Scan button with refresh icon
    scan_btn = gtk_button_new()
    call gtk_button_set_icon_name(scan_btn, "view-refresh"//c_null_char)
    call gtk_widget_set_tooltip_text(scan_btn, "Rescan Current Directory"//c_null_char)
    call g_signal_connect(scan_btn, "clicked"//c_null_char, &
                           c_funloc(on_scan_clicked), c_null_ptr)
    call gtk_box_append(toolbar, scan_btn)

    ! Create Cancel Scan button with X icon
    cancel_scan_btn = gtk_button_new()
    call gtk_button_set_icon_name(cancel_scan_btn, "window-close"//c_null_char)
    call gtk_widget_set_tooltip_text(cancel_scan_btn, "Cancel Scan"//c_null_char)
    call g_signal_connect(cancel_scan_btn, "clicked"//c_null_char, &
                           c_funloc(on_cancel_scan_clicked), c_null_ptr)
    call gtk_box_append(toolbar, cancel_scan_btn)
    cancel_scan_btn_ptr = cancel_scan_btn  ! Store for enabling/disabling

    ! Create Back button (navigate to previous directory in history)
    back_btn = gtk_button_new()
    call gtk_button_set_icon_name(back_btn, "go-previous"//c_null_char)
    call gtk_widget_set_tooltip_text(back_btn, "Navigate Back"//c_null_char)
    call g_signal_connect(back_btn, "clicked"//c_null_char, &
                           c_funloc(on_back_clicked), c_null_ptr)
    call gtk_box_append(toolbar, back_btn)
    back_btn_ptr = back_btn  ! Store for enabling/disabling

    ! Create Forward button (navigate to next directory in history)
    forward_btn = gtk_button_new()
    call gtk_button_set_icon_name(forward_btn, "go-next"//c_null_char)
    call gtk_widget_set_tooltip_text(forward_btn, "Navigate Forward"//c_null_char)
    call g_signal_connect(forward_btn, "clicked"//c_null_char, &
                           c_funloc(on_forward_clicked), c_null_ptr)
    call gtk_box_append(toolbar, forward_btn)
    forward_btn_ptr = forward_btn  ! Store for enabling/disabling

    ! Create Up to Parent button (navigate to parent directory)
    up_btn = gtk_button_new()
    call gtk_button_set_icon_name(up_btn, "go-up"//c_null_char)
    call gtk_widget_set_tooltip_text(up_btn, "Navigate to Parent Directory (Backspace)"//c_null_char)
    call g_signal_connect(up_btn, "clicked"//c_null_char, &
                           c_funloc(on_up_clicked), c_null_ptr)
    call gtk_box_append(toolbar, up_btn)

    ! Initialize Back/Forward button states (disabled until history exists)
    call update_history_buttons()

    ! Initialize Cancel Scan button state (disabled and grey until scan starts)
    call update_cancel_scan_button_state()

    ! Initialize selection-dependent button states (disabled until selection exists)
    call update_selection_buttons()

    ! Create progress bar (always visible but starts at 0%)
    ! Place it in toolbar, expanded to fill remaining space (pushes to right)
    progress_bar_ptr = gtk_progress_bar_new()
    call gtk_progress_bar_set_show_text(progress_bar_ptr, 1_c_int)  ! Show percentage text
    call gtk_widget_set_hexpand(progress_bar_ptr, 1_c_int)  ! Expand horizontally to fill space
    call gtk_progress_bar_set_fraction(progress_bar_ptr, 0.0_c_double)  ! Start at 0%
    call gtk_box_append(toolbar, progress_bar_ptr)

    ! Create Open in Finder button (floated right after progress bar)
    open_finder_btn = gtk_button_new()
    call gtk_button_set_icon_name(open_finder_btn, "document-open"//c_null_char)
    call gtk_widget_set_tooltip_text(open_finder_btn, "Open in Finder/File Manager"//c_null_char)
    call g_signal_connect(open_finder_btn, "clicked"//c_null_char, &
                           c_funloc(on_open_finder_clicked), c_null_ptr)
    call gtk_box_append(toolbar, open_finder_btn)
    open_finder_btn_ptr = open_finder_btn  ! Store for enabling/disabling

    ! Create Copy Path button
    copy_path_btn = gtk_button_new()
    call gtk_button_set_icon_name(copy_path_btn, "edit-copy"//c_null_char)
    call gtk_widget_set_tooltip_text(copy_path_btn, "Copy Path to Clipboard"//c_null_char)
    call g_signal_connect(copy_path_btn, "clicked"//c_null_char, &
                           c_funloc(on_copy_path_clicked), c_null_ptr)
    call gtk_box_append(toolbar, copy_path_btn)
    copy_path_btn_ptr = copy_path_btn  ! Store for enabling/disabling

    ! Create Properties/Info button
    info_btn = gtk_button_new()
    call gtk_button_set_icon_name(info_btn, "document-properties"//c_null_char)
    call gtk_widget_set_tooltip_text(info_btn, "Show Properties/Info"//c_null_char)
    call g_signal_connect(info_btn, "clicked"//c_null_char, &
                           c_funloc(on_info_clicked), c_null_ptr)
    call gtk_box_append(toolbar, info_btn)
    info_btn_ptr = info_btn  ! Store for enabling/disabling

    ! View Toggle Buttons (Phase 3 & 5 features)

    ! Toggle Dotfiles button
    toggle_dotfiles_btn = gtk_button_new()
    call gtk_button_set_icon_name(toggle_dotfiles_btn, "view-reveal-symbolic"//c_null_char)
    call gtk_widget_set_tooltip_text(toggle_dotfiles_btn, "Toggle Hidden Files/Dotfiles"//c_null_char)
    call g_signal_connect(toggle_dotfiles_btn, "clicked"//c_null_char, &
                           c_funloc(on_toggle_dotfiles_clicked), c_null_ptr)
    call gtk_box_append(toolbar, toggle_dotfiles_btn)

    ! Toggle File Extensions button
    toggle_ext_btn = gtk_button_new()
    call gtk_button_set_icon_name(toggle_ext_btn, "text-x-generic-symbolic"//c_null_char)
    call gtk_widget_set_tooltip_text(toggle_ext_btn, "Toggle File Extensions in Labels"//c_null_char)
    call g_signal_connect(toggle_ext_btn, "clicked"//c_null_char, &
                           c_funloc(on_toggle_extensions_clicked), c_null_ptr)
    call gtk_box_append(toolbar, toggle_ext_btn)

    ! Toggle Render Mode button (Flat vs Cushioned)
    toggle_render_btn = gtk_button_new()
    call gtk_button_set_icon_name(toggle_render_btn, "view-grid-symbolic"//c_null_char)
    call gtk_widget_set_tooltip_text(toggle_render_btn, "Toggle Flat/3D Rendering Mode"//c_null_char)
    call g_signal_connect(toggle_render_btn, "clicked"//c_null_char, &
                           c_funloc(on_toggle_render_mode_clicked), c_null_ptr)
    call gtk_box_append(toolbar, toggle_render_btn)

    ! Create Delete button
    delete_btn = gtk_button_new()
    call gtk_button_set_icon_name(delete_btn, "user-trash"//c_null_char)
    call gtk_widget_set_tooltip_text(delete_btn, "Delete to Trash (D key)"//c_null_char)
    call g_signal_connect(delete_btn, "clicked"//c_null_char, &
                           c_funloc(on_delete_clicked), c_null_ptr)
    call gtk_box_append(toolbar, delete_btn)
    delete_btn_ptr = delete_btn  ! Store for enabling/disabling

    ! Add toolbar to main box
    call gtk_box_append(main_box, toolbar)

    ! Create custom Cairo breadcrumb widget
    breadcrumb_widget = create_breadcrumb_widget()
    if (.not. c_associated(breadcrumb_widget)) then
      print *, "ERROR: Failed to create breadcrumb widget"
      return
    end if

    ! Register navigation callback for breadcrumb
    call set_navigation_callback(breadcrumb_callback)

    ! Add breadcrumb widget to main box
    call gtk_box_append(main_box, breadcrumb_widget)

    ! Create treemap drawing area widget
    drawing_area = create_treemap_widget()

    if (.not. c_associated(drawing_area)) then
      print *, "ERROR: Failed to create treemap widget"
      return
    end if

    ! Make drawing area expand to fill space
    call gtk_widget_set_hexpand(drawing_area, 1_c_int)
    call gtk_widget_set_vexpand(drawing_area, 1_c_int)

    ! Register widget with renderer for progressive scan redraws
    call set_redraw_widget(drawing_area)

    ! Set the scan path
    call set_scan_path(scan_path)

    ! Update path entry to show initial scan path
    call update_path_entry(scan_path)

    ! Register navigation callback for breadcrumb updates
    call register_navigation_callback(breadcrumb_callback)

    ! Register quit callback
    call register_quit_callback(quit_callback_wrapper)

    ! Register delete callback
    call register_delete_callback(delete_callback_wrapper)

    ! Register force refresh callback
    call register_refresh_callback(refresh_callback_wrapper)

    ! Register selection change callback for button state updates
    call register_selection_callback(update_selection_buttons)
    print *, "Selection callback registered"

    ! Register progress callbacks
    call register_progress_callback(sniffly_show_progress, sniffly_hide_progress, &
                                      sniffly_update_progress)

    ! Register scan completion callback (wrapped to update button state)
    call register_scan_completion_callback(scan_complete_callback_wrapper)
    print *, "Scan completion callback registered"

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

  ! Callback when Open Directory button is clicked
  ! NOTE: Uses system command for file picking until GTK4 file dialog bindings are available
  subroutine on_open_dir_clicked(button, user_data) bind(c)
    type(c_ptr), value :: button, user_data
    character(len=1024) :: selected_path
    integer :: status

    print *, "Open Directory button clicked!"

    ! Call helper to show native file picker
    call show_native_directory_picker(selected_path, status)

    if (status == 0 .and. len_trim(selected_path) > 0) then
      print *, "Selected directory: ", trim(selected_path)

      ! Update global scan path (but don't scan yet)
      ! Remove trailing slash if present (C code doesn't like it)
      if (len_trim(selected_path) > 1 .and. selected_path(len_trim(selected_path):len_trim(selected_path)) == '/') then
        global_scan_path = trim(selected_path(1:len_trim(selected_path)-1))
        print *, "DEBUG: Removed trailing slash from path"
      else
        global_scan_path = trim(selected_path)
      end if
      print *, "DEBUG: Set global_scan_path to: '", trim(global_scan_path), "'"
      call set_scan_path(trim(global_scan_path))

      ! Update path display entry
      call update_path_entry(trim(global_scan_path))

      print *, "Path updated. Click Scan button to scan: ", trim(global_scan_path)
    else
      print *, "Directory selection cancelled or failed"
    end if
  end subroutine on_open_dir_clicked

  ! Callback when Scan button is clicked
  subroutine on_scan_clicked(button, user_data) bind(c)
    type(c_ptr), value :: button, user_data

    if (len_trim(global_scan_path) == 0) then
      call sniffly_update_status("No directory to scan")
      return
    end if

    ! Trigger a rescan of the current path (uses cache for speed)
    call sniffly_update_status("Rescanning...")
    call trigger_rescan(global_scan_path)
  end subroutine on_scan_clicked

  ! Callback when Cancel Scan button is clicked
  subroutine on_cancel_scan_clicked(button, user_data) bind(c)
    use progressive_scanner, only: stop_progressive_scan, is_scan_active
    type(c_ptr), value :: button, user_data

    print *, "Cancel scan button clicked!"

    if (is_scan_active()) then
      call sniffly_update_status("Cancelling scan...")
      call stop_progressive_scan()
      ! Update button states (cancel button disabled, back/forward re-enabled if history exists)
      call update_cancel_scan_button_state()
      call update_history_buttons()
      call sniffly_update_status("Scan cancelled")
    end if
  end subroutine on_cancel_scan_clicked

  ! Callback when Open in Finder button is clicked
  subroutine on_open_finder_clicked(button, user_data) bind(c)
    type(c_ptr), value :: button, user_data
    character(len=:), allocatable :: selected_path

    print *, "Open in Finder button clicked!"

    ! Check if there's a selection
    if (.not. has_selection()) then
      print *, "No selection - cannot open in Finder"
      return
    end if

    ! Get the selected node path
    selected_path = get_selected_node_path()

    if (len_trim(selected_path) == 0) then
      print *, "Invalid selection path"
      return
    end if

    print *, "Opening in Finder: ", trim(selected_path)
    call open_in_file_manager(selected_path)
  end subroutine on_open_finder_clicked

  ! Callback when Copy Path button is clicked
  subroutine on_copy_path_clicked(button, user_data) bind(c)
    type(c_ptr), value :: button, user_data
    character(len=:), allocatable :: selected_path
    type(c_ptr) :: display, clipboard

    print *, "Copy Path button clicked!"

    ! Check if there's a selection
    if (.not. has_selection()) then
      print *, "No selection - cannot copy path"
      call sniffly_update_status("No selection to copy")
      return
    end if

    ! Get the selected node path
    selected_path = get_selected_node_path()

    if (len_trim(selected_path) == 0) then
      print *, "Invalid selection path"
      call sniffly_update_status("Invalid selection path")
      return
    end if

    print *, "Copying path to clipboard: ", trim(selected_path)

    ! Get the default display
    display = gdk_display_get_default()
    if (.not. c_associated(display)) then
      print *, "ERROR: Failed to get default display"
      call sniffly_update_status("Failed to access clipboard")
      return
    end if

    ! Get the clipboard from the display
    clipboard = gdk_display_get_clipboard(display)
    if (.not. c_associated(clipboard)) then
      print *, "ERROR: Failed to get clipboard"
      call sniffly_update_status("Failed to access clipboard")
      return
    end if

    ! Convert Fortran string to C string and set clipboard
    call gdk_clipboard_set_text(clipboard, trim(selected_path)//c_null_char)

    ! Update status
    call sniffly_update_status("Path copied to clipboard: " // trim(selected_path))
    print *, "Path copied successfully!"
  end subroutine on_copy_path_clicked

  ! Callback when Properties/Info button is clicked
  subroutine on_info_clicked(button, user_data) bind(c)
    use iso_fortran_env, only: int64
    use treemap_renderer, only: get_current_view_node
    use treemap_widget, only: get_selected_index
    use types, only: file_node
    use file_system, only: list_directory
    type(c_ptr), value :: button, user_data
    character(len=:), allocatable :: info_msg
    character(len=1024) :: info_text
    character(len=20) :: size_str
    type(file_node), pointer :: view_node
    integer(int64) :: size_bytes
    integer :: item_count, selected_idx
    character(len=256), dimension(10000) :: entries

    ! Check if there's a selection
    if (.not. has_selection()) then
      call sniffly_update_status("No selection to show properties for")
      return
    end if

    ! Get the selected node
    view_node => get_current_view_node()
    if (.not. associated(view_node)) then
      return
    end if

    ! Get the selected child index (1-based: 1 = first child, 2 = second child, etc.)
    selected_idx = get_selected_index()
    if (selected_idx < 1 .or. selected_idx > view_node%num_children) then
      call sniffly_update_status("Invalid selection")
      return
    end if

    ! Get details from selected child (selected_idx is already 1-based)
    size_bytes = view_node%children(selected_idx)%size

    ! Check if this is a grouped "[N small files]" node
    if (index(view_node%children(selected_idx)%name, '[') == 1 .and. &
        index(view_node%children(selected_idx)%name, 'small files]') > 0) then
      ! This is a grouped small files node - don't count items (name already has the count)
      item_count = -1  ! Special marker for grouped nodes
    else if (view_node%children(selected_idx)%is_directory) then
      ! For regular directories, count entries on-demand to get accurate item count
      item_count = list_directory(view_node%children(selected_idx)%path, entries, 10000)
    else
      item_count = 0  ! Files don't have children
    end if

    ! Format size
    if (size_bytes < 1024_int64) then
      write(size_str, '(I0,A)') size_bytes, ' B'
    else if (size_bytes < 1024_int64**2) then
      write(size_str, '(F0.2,A)') real(size_bytes)/1024.0, ' KB'
    else if (size_bytes < 1024_int64**3) then
      write(size_str, '(F0.2,A)') real(size_bytes)/(1024.0**2), ' MB'
    else
      write(size_str, '(F0.2,A)') real(size_bytes)/(1024.0**3), ' GB'
    end if

    ! Build info text for status bar
    if (item_count == -1) then
      ! Grouped small files - name already contains the count
      write(info_text, '(A,A,A)') &
        trim(view_node%children(selected_idx)%name), ' | ', trim(size_str)
    else if (view_node%children(selected_idx)%is_directory) then
      ! Regular directory
      write(info_text, '(A,A,A,A,I0,A)') &
        trim(view_node%children(selected_idx)%name), ' | ', trim(size_str), ' | ', item_count, ' items'
    else
      ! Regular file
      write(info_text, '(A,A,A,A)') &
        trim(view_node%children(selected_idx)%name), ' | ', trim(size_str), ' | File'
    end if

    ! Show properties in status bar
    info_msg = trim(info_text)
    call sniffly_update_status(info_msg)
  end subroutine on_info_clicked

  ! Helper: Update Back/Forward button states
  subroutine update_history_buttons()
    use gtk, only: gtk_widget_set_sensitive
    use progressive_scanner, only: is_scan_active
    logical :: scan_active

    ! Guard against accessing widgets during shutdown
    if (app_is_shutting_down) return
    if (.not. c_associated(back_btn_ptr) .or. .not. c_associated(forward_btn_ptr)) return

    ! Check if scan is active - disable buttons during scan
    scan_active = is_scan_active()

    print *, "=== UPDATE_HISTORY_BUTTONS ==="
    print *, "  pos=", nav_history_pos, " count=", nav_history_count, " scan_active=", scan_active

    ! Enable Back if we're not at the start of history AND scan is not active
    if (nav_history_pos > 1 .and. .not. scan_active) then
      print *, "  Enabling Back (pos > 1 and scan not active)"
      call gtk_widget_set_sensitive(back_btn_ptr, 1_c_int)
    else
      print *, "  Disabling Back (pos=", nav_history_pos, " or scan active)"
      call gtk_widget_set_sensitive(back_btn_ptr, 0_c_int)
    end if

    ! Enable Forward if we're not at the end of history AND scan is not active
    if (nav_history_pos > 0 .and. nav_history_pos < nav_history_count .and. .not. scan_active) then
      print *, "  Enabling Forward (pos < count and scan not active)"
      call gtk_widget_set_sensitive(forward_btn_ptr, 1_c_int)
    else
      print *, "  Disabling Forward (pos=", nav_history_pos, " count=", nav_history_count, " or scan active)"
      call gtk_widget_set_sensitive(forward_btn_ptr, 0_c_int)
    end if
  end subroutine update_history_buttons

  ! Helper: Update Cancel Scan button state based on scan status
  subroutine update_cancel_scan_button_state()
    use progressive_scanner, only: is_scan_active
    use gtk, only: gtk_widget_set_sensitive

    ! Guard against accessing widgets during shutdown
    if (app_is_shutting_down) return
    if (.not. c_associated(cancel_scan_btn_ptr)) return

    print *, "DEBUG: Updating cancel button state, scan active =", is_scan_active()

    if (is_scan_active()) then
      ! Scan is active - enable button and make it red
      print *, "DEBUG: Enabling cancel button (making it red)"
      call gtk_widget_add_css_class(cancel_scan_btn_ptr, "destructive-action"//c_null_char)
      call gtk_widget_set_sensitive(cancel_scan_btn_ptr, 1_c_int)
    else
      ! No scan active - remove red styling first, then disable button
      print *, "DEBUG: Disabling cancel button (making it grey)"
      call gtk_widget_remove_css_class(cancel_scan_btn_ptr, "destructive-action"//c_null_char)
      call gtk_widget_set_sensitive(cancel_scan_btn_ptr, 0_c_int)
    end if
  end subroutine update_cancel_scan_button_state

  ! Helper: Update selection-dependent button states
  subroutine update_selection_buttons()
    use gtk, only: gtk_widget_set_sensitive
    logical :: has_sel

    ! Guard against accessing widgets during shutdown
    if (app_is_shutting_down) return
    if (.not. c_associated(info_btn_ptr)) return

    ! Check if there's a selection
    has_sel = has_selection()

    print *, "DEBUG: update_selection_buttons() called, has_selection =", has_sel

    ! Enable/disable all selection-dependent buttons
    if (has_sel) then
      print *, "DEBUG:   Enabling selection-dependent buttons"
      call gtk_widget_set_sensitive(info_btn_ptr, 1_c_int)
      call gtk_widget_set_sensitive(copy_path_btn_ptr, 1_c_int)
      call gtk_widget_set_sensitive(open_finder_btn_ptr, 1_c_int)
      call gtk_widget_set_sensitive(delete_btn_ptr, 1_c_int)
    else
      print *, "DEBUG:   Disabling selection-dependent buttons"
      call gtk_widget_set_sensitive(info_btn_ptr, 0_c_int)
      call gtk_widget_set_sensitive(copy_path_btn_ptr, 0_c_int)
      call gtk_widget_set_sensitive(open_finder_btn_ptr, 0_c_int)
      call gtk_widget_set_sensitive(delete_btn_ptr, 0_c_int)
    end if
  end subroutine update_selection_buttons

  ! Helper: Add path to navigation history
  subroutine add_to_history(path)
    character(len=*), intent(in) :: path
    integer :: i

    print *, "=== ADD_TO_HISTORY CALLED ==="
    print *, "  Path: ", trim(path)
    print *, "  Before: pos=", nav_history_pos, " count=", nav_history_count
    if (nav_history_count > 0) then
      print *, "  Current history:"
      do i = 1, nav_history_count
        if (i == nav_history_pos) then
          print *, "    [", i, "] (CURRENT) ", trim(nav_history(i))
        else
          print *, "    [", i, "] ", trim(nav_history(i))
        end if
      end do
    end if

    ! Don't add if it's the same as current position
    if (nav_history_pos > 0 .and. nav_history_pos <= nav_history_count) then
      if (trim(nav_history(nav_history_pos)) == trim(path)) then
        print *, "  Path same as current position - not adding"
        return
      end if
    end if

    ! If we're in the middle of history, discard forward history
    if (nav_history_pos > 0 .and. nav_history_pos < nav_history_count) then
      print *, "  In middle of history - truncating forward history"
      print *, "  Truncating count from", nav_history_count, "to", nav_history_pos
      nav_history_count = nav_history_pos
    end if

    ! Add to history
    if (nav_history_count < MAX_HISTORY) then
      nav_history_count = nav_history_count + 1
      nav_history(nav_history_count) = trim(path)
      print *, "  Added to history at position", nav_history_count
    else
      ! Shift history left and add at end
      print *, "  History full - shifting left"
      do i = 1, MAX_HISTORY - 1
        nav_history(i) = nav_history(i + 1)
      end do
      nav_history(MAX_HISTORY) = trim(path)
    end if

    nav_history_pos = nav_history_count
    print *, "  After: pos=", nav_history_pos, " count=", nav_history_count
    print *, "=== END ADD_TO_HISTORY ==="
    call update_history_buttons()
  end subroutine add_to_history

  ! Callback when Back button is clicked
  subroutine on_back_clicked(button, user_data) bind(c)
    use progressive_scanner, only: is_scan_active
    type(c_ptr), value :: button, user_data

    print *, "=== BACK BUTTON CLICKED ==="
    print *, "  Before: pos=", nav_history_pos, " count=", nav_history_count

    ! Block navigation if scan is active
    if (is_scan_active()) then
      call sniffly_update_status("Cannot navigate: Scan in progress")
      return
    end if

    if (nav_history_pos > 1) then
      nav_history_pos = nav_history_pos - 1
      global_scan_path = trim(nav_history(nav_history_pos))
      print *, "  Moving back to pos=", nav_history_pos
      print *, "  Path: ", trim(global_scan_path)
      navigating_history = .true.  ! Set flag before triggering rescan
      call set_scan_path(trim(global_scan_path))
      call update_path_entry(trim(global_scan_path))
      call trigger_rescan(global_scan_path)
      call update_history_buttons()
      call sniffly_update_status("Navigated back to: " // trim(global_scan_path))
    end if
  end subroutine on_back_clicked

  ! Callback when Forward button is clicked
  subroutine on_forward_clicked(button, user_data) bind(c)
    use progressive_scanner, only: is_scan_active
    type(c_ptr), value :: button, user_data

    print *, "=== FORWARD BUTTON CLICKED ==="
    print *, "  Before: pos=", nav_history_pos, " count=", nav_history_count

    ! Block navigation if scan is active
    if (is_scan_active()) then
      call sniffly_update_status("Cannot navigate: Scan in progress")
      return
    end if

    if (nav_history_pos > 0 .and. nav_history_pos < nav_history_count) then
      nav_history_pos = nav_history_pos + 1
      global_scan_path = trim(nav_history(nav_history_pos))
      print *, "  Moving forward to pos=", nav_history_pos
      print *, "  Path: ", trim(global_scan_path)
      navigating_history = .true.  ! Set flag before triggering rescan
      call set_scan_path(trim(global_scan_path))
      call update_path_entry(trim(global_scan_path))
      call trigger_rescan(global_scan_path)
      call update_history_buttons()
      call sniffly_update_status("Navigated forward to: " // trim(global_scan_path))
    end if
  end subroutine on_forward_clicked

  ! Callback when Up to Parent button is clicked
  subroutine on_up_clicked(button, user_data) bind(c)
    use treemap_renderer, only: navigate_up
    use gtk, only: gtk_widget_queue_draw
    type(c_ptr), value :: button, user_data

    ! Use the existing navigate_up functionality from treemap_renderer
    call navigate_up()

    ! Update breadcrumbs and history
    call breadcrumb_callback()

    ! Trigger redraw
    if (c_associated(main_window_ptr)) then
      call gtk_widget_queue_draw(main_window_ptr)
    end if

    call sniffly_update_status("Navigated to parent directory")
  end subroutine on_up_clicked

  ! Callback when Delete button is clicked
  subroutine on_delete_clicked(button, user_data) bind(c)
    use treemap_widget, only: get_selected_index
    type(c_ptr), value :: button, user_data
    character(len=:), allocatable :: selected_path
    integer :: confirm_result, selected_idx

    print *, "Delete button clicked!"

    ! Check if there's a selection
    if (.not. has_selection()) then
      print *, "No selection - cannot delete"
      return
    end if

    ! Get the selected node path and index
    selected_path = get_selected_node_path()
    selected_idx = get_selected_index()

    if (len_trim(selected_path) == 0) then
      print *, "Invalid selection path"
      return
    end if

    print *, "Preparing to delete: ", trim(selected_path)

    ! Show confirmation dialog
    call show_delete_confirmation(selected_path, confirm_result)

    if (confirm_result == 1) then
      print *, "Delete confirmed - proceeding"
      call delete_to_trash(selected_path, selected_idx)
    else
      print *, "Delete cancelled by user"
    end if
  end subroutine on_delete_clicked

  ! Callback when Toggle Dotfiles button is clicked
  subroutine on_toggle_dotfiles_clicked(button, user_data) bind(c)
    use treemap_renderer, only: toggle_hidden_files
    type(c_ptr), value :: button, user_data

    call toggle_hidden_files()
    call sniffly_update_status("Toggled hidden files visibility - rescanning...")

    ! Trigger rescan to apply the filter
    if (len_trim(global_scan_path) > 0) then
      call trigger_rescan(global_scan_path)
    end if
  end subroutine on_toggle_dotfiles_clicked

  ! Callback when Toggle File Extensions button is clicked
  subroutine on_toggle_extensions_clicked(button, user_data) bind(c)
    use treemap_renderer, only: toggle_file_extensions
    type(c_ptr), value :: button, user_data

    call toggle_file_extensions()
    call sniffly_update_status("Toggled file extensions visibility")
  end subroutine on_toggle_extensions_clicked

  ! Callback when Toggle Render Mode button is clicked
  subroutine on_toggle_render_mode_clicked(button, user_data) bind(c)
    use treemap_renderer, only: toggle_render_mode
    type(c_ptr), value :: button, user_data

    call toggle_render_mode()
    call sniffly_update_status("Toggled render mode (flat vs cushioned)")
  end subroutine on_toggle_render_mode_clicked

  ! Commented out unused helper function - was used by removed search/filter feature
  ! Uncomment if needed in future

  ! ! Helper to convert C string to Fortran string
  ! subroutine c_f_string(c_str_ptr, f_str)
  !   type(c_ptr), intent(in) :: c_str_ptr
  !   character(len=*), intent(out) :: f_str
  !   character(len=1, kind=c_char), pointer :: c_chars(:)
  !   integer :: i, str_len
  !
  !   f_str = ""
  !   if (.not. c_associated(c_str_ptr)) return
  !
  !   ! Get string length
  !   str_len = 0
  !   do i = 1, len(f_str)
  !     call c_f_pointer(c_str_ptr, c_chars, [i])
  !     if (c_chars(i) == c_null_char) exit
  !     str_len = i
  !   end do
  !
  !   ! Copy characters
  !   if (str_len > 0) then
  !     call c_f_pointer(c_str_ptr, c_chars, [str_len])
  !     do i = 1, str_len
  !       f_str(i:i) = c_chars(i)
  !     end do
  !   end if
  ! end subroutine c_f_string

  ! Detect if we're running on macOS
  function is_macos() result(is_mac)
    logical :: is_mac
    logical :: file_exists

    ! Check for macOS-specific directory
    inquire(file='/Applications', exist=file_exists)
    is_mac = file_exists
  end function is_macos

  ! Show native OS directory picker using system commands
  ! This is a workaround until GTK4 file dialog bindings are available
  subroutine show_native_directory_picker(path, status)
    character(len=*), intent(out) :: path
    integer, intent(out) :: status
    character(len=2048) :: command, temp_file
    integer :: unit, ios
    logical :: file_exists

    path = ""
    status = -1

    ! Create temp file for output
    temp_file = "/tmp/sniffly_picker.txt"

    ! Platform-specific command - detect at runtime
    if (is_macos()) then
      ! macOS: Use osascript to show native folder picker
      command = 'osascript -e ''POSIX path of (choose folder with prompt "Select directory to scan:")'' > ' &
                // trim(temp_file) // ' 2>&1'
    else
      ! Linux: Try zenity, fallback to kdialog
      command = 'zenity --file-selection --directory > ' // trim(temp_file) // &
                ' 2>&1 || kdialog --getexistingdirectory . > ' // trim(temp_file) // ' 2>&1'
    end if

    print *, "Executing: ", trim(command)

    ! Execute command
    call execute_command_line(trim(command), exitstat=status)

    ! Read result from temp file
    inquire(file=trim(temp_file), exist=file_exists)
    if (file_exists) then
      open(newunit=unit, file=trim(temp_file), status='old', action='read', iostat=ios)
      if (ios == 0) then
        read(unit, '(A)', iostat=ios) path
        close(unit)

        ! Remove temp file
        call execute_command_line('rm -f ' // trim(temp_file))

        ! Trim whitespace and check if valid
        path = trim(adjustl(path))
        if (len_trim(path) > 0) then
          status = 0
          print *, "Got path: ", trim(path)
        else
          status = 1
        end if
      else
        close(unit)
        status = 1
      end if
    else
      status = 1
    end if
  end subroutine show_native_directory_picker

  ! Update the path display entry with a new path
  subroutine update_path_entry(path)
    character(len=*), intent(in) :: path
    type(c_ptr) :: buffer

    ! Guard against accessing widgets during shutdown
    if (app_is_shutting_down) return
    if (.not. c_associated(path_entry_ptr)) return

    ! Get the entry buffer and set the text
    buffer = gtk_entry_get_buffer(path_entry_ptr)
    call gtk_entry_buffer_set_text(buffer, trim(path)//c_null_char, &
                                    int(len_trim(path), c_int))
  end subroutine update_path_entry

  ! Open a file or folder in the OS file manager (Finder on macOS, file browser on Linux)
  subroutine open_in_file_manager(path)
    character(len=*), intent(in) :: path
    character(len=2048) :: command
    integer :: status

    if (is_macos()) then
      ! macOS: Use 'open -R' to reveal in Finder
      command = 'open -R "' // trim(path) // '"'
    else
      ! Linux: Use xdg-open to open in default file manager
      command = 'xdg-open "' // trim(path) // '"'
    end if

    print *, "Executing: ", trim(command)
    call execute_command_line(trim(command), exitstat=status)

    if (status /= 0) then
      print *, "Warning: Failed to open file manager (exit status: ", status, ")"
    else
      print *, "Successfully opened in file manager"
    end if
  end subroutine open_in_file_manager

  ! Show native delete confirmation dialog using system commands
  subroutine show_delete_confirmation(path, result)
    character(len=*), intent(in) :: path
    integer, intent(out) :: result
    character(len=2048) :: command
    integer :: status

    result = 0  ! Default to cancel

    if (is_macos()) then
      ! macOS: Use osascript to show native dialog
      command = 'osascript -e ''display dialog "Are you sure you want to delete:\n' &
                // trim(path) // '\n\nThis will move the item to Trash." ' &
                // 'buttons {"Cancel", "Delete"} default button "Cancel" ' &
                // 'with icon caution'' > /dev/null 2>&1'
    else
      ! Linux: Use zenity for confirmation dialog
      command = 'zenity --question --title="Confirm Delete" --text="Are you sure you want to delete:\n' &
                // trim(path) // '\n\nThis will move the item to Trash." 2>&1'
    end if

    print *, "Showing confirmation dialog for: ", trim(path)
    call execute_command_line(trim(command), exitstat=status)

    ! Both macOS and Linux: exit status 0 means confirmed
    if (status == 0) then
      result = 1  ! Confirmed
    end if

    print *, "Confirmation result: ", result
  end subroutine show_delete_confirmation

  ! Delete file or folder to system trash (macOS/Linux)
  subroutine delete_to_trash(path, selected_idx)
    use gtk, only: gtk_widget_queue_draw
    use treemap_renderer, only: remove_selected_node_from_view, invalidate_layout
    use treemap_widget, only: clear_selection
    character(len=*), intent(in) :: path
    integer, intent(in) :: selected_idx
    character(len=2048) :: command
    integer :: status

    if (is_macos()) then
      ! macOS: Use osascript to move to Trash via Finder
      command = 'osascript -e ''tell application "Finder" to delete POSIX file "' &
                // trim(path) // '"'' > /dev/null 2>&1'
    else
      ! Linux: Use gio trash (GNOME), fallback to trash-cli
      command = 'gio trash "' // trim(path) // '" 2>&1 || trash "' // trim(path) // '" 2>&1'
    end if

    print *, "Deleting to trash: ", trim(path)
    call execute_command_line(trim(command), exitstat=status)

    if (status == 0) then
      print *, "Successfully moved to trash: ", trim(path)

      ! Clear the selection first (before modifying tree)
      call clear_selection()

      ! Remove the node from the current view by marking it as deleted
      call remove_selected_node_from_view(selected_idx)

      ! Force layout recalculation
      call invalidate_layout()

      ! Trigger redraw to show the updated view
      if (c_associated(main_window_ptr)) then
        call gtk_widget_queue_draw(main_window_ptr)
      end if

      print *, "View updated - deleted node removed"
    else
      print *, "ERROR: Failed to move to trash (exit status: ", status, ")"
      print *, "You may need to delete manually or check permissions"
    end if
  end subroutine delete_to_trash

  ! Update status bar with scan information
  subroutine sniffly_update_status(message)
    character(len=*), intent(in) :: message
    ! Guard against accessing widgets during shutdown
    if (app_is_shutting_down) return
    if (c_associated(status_label_ptr)) then
      call gtk_label_set_text(status_label_ptr, trim(message)//c_null_char)
    end if
  end subroutine sniffly_update_status

  ! Update status bar with file count and size statistics
  subroutine sniffly_update_status_bar_stats()
    use types, only: file_node
    use treemap_renderer, only: get_current_view_node, get_node_count
    use iso_fortran_env, only: int64
    type(file_node), pointer :: current_view
    integer :: item_count, total_files
    integer(int64) :: total_size
    character(len=256) :: status_text
    character(len=64) :: size_str
    real :: size_kb, size_mb, size_gb

    ! Guard against accessing widgets during shutdown
    if (app_is_shutting_down) return
    if (.not. c_associated(status_label_ptr)) return

    ! Get current view node
    current_view => get_current_view_node()
    if (.not. associated(current_view)) then
      call gtk_label_set_text(status_label_ptr, "No data"//c_null_char)
      return
    end if

    ! Get statistics from current view
    item_count = get_node_count()
    total_size = current_view%size

    ! Count total files recursively
    total_files = count_files_recursive(current_view)

    ! Format size nicely
    if (total_size < 1024_int64) then
      write(size_str, '(I0,A)') total_size, ' B'
    else if (total_size < 1024_int64**2) then
      size_kb = real(total_size) / 1024.0
      write(size_str, '(F0.2,A)') size_kb, ' KB'
    else if (total_size < 1024_int64**3) then
      size_mb = real(total_size) / (1024.0**2)
      write(size_str, '(F0.2,A)') size_mb, ' MB'
    else
      size_gb = real(total_size) / (1024.0**3)
      write(size_str, '(F0.2,A)') size_gb, ' GB'
    end if

    ! Build status text
    write(status_text, '(I0,A,I0,A,A)') item_count, ' items (', total_files, ' files) - ', trim(size_str)

    ! Update status label
    call gtk_label_set_text(status_label_ptr, trim(status_text)//c_null_char)
  end subroutine sniffly_update_status_bar_stats

  ! Helper function to recursively count all files in a tree
  recursive function count_files_recursive(node) result(count)
    use types, only: file_node
    type(file_node), intent(in) :: node
    integer :: count, i

    count = 0

    if (node%is_directory) then
      ! For directories, count all children recursively
      if (allocated(node%children)) then
        do i = 1, node%num_children
          count = count + count_files_recursive(node%children(i))
        end do
      end if
    else
      ! For files, count this file
      count = 1
    end if
  end function count_files_recursive

  ! Get forward path (if we navigated backwards and there's a forward history)
  function get_forward_path() result(fwd_path)
    character(len=512) :: fwd_path
    fwd_path = ""
    if (nav_history_pos > 0 .and. nav_history_pos < nav_history_count) then
      fwd_path = trim(nav_history(nav_history_pos + 1))
      print *, "Forward path available: ", trim(fwd_path)
    end if
  end function get_forward_path

  ! Callback wrapper for navigation events (no arguments)
  subroutine breadcrumb_callback()
    use treemap_renderer, only: get_current_view_node
    use types, only: file_node
    type(file_node), pointer :: current_view
    character(len=512) :: fwd_path, prev_breadcrumb_path
    integer :: i, matched_pos, current_len
    logical :: was_navigating_history

    print *, "=== BREADCRUMB_CALLBACK ==="
    print *, "  navigating_history flag at entry: ", navigating_history

    ! Initialize variables
    fwd_path = ""

    ! Save flag state
    was_navigating_history = navigating_history

    ! Sync global_scan_path with the current view node's path
    current_view => get_current_view_node()
    if (associated(current_view) .and. allocated(current_view%path)) then
      global_scan_path = trim(current_view%path)
      print *, "  Synced global_scan_path to: ", trim(global_scan_path)
      print *, "  Current nav_history_pos: ", nav_history_pos, " nav_history_count: ", nav_history_count

      ! Check for breadcrumb-based lookahead first (when clicking up in breadcrumb)
      prev_breadcrumb_path = get_previous_breadcrumb_path()
      if (len_trim(prev_breadcrumb_path) > 0) then
        print *, "  Previous breadcrumb path: ", trim(prev_breadcrumb_path)
        ! Check if current path is a prefix of previous path (navigating up)
        current_len = len_trim(global_scan_path)
        if (len_trim(prev_breadcrumb_path) > current_len) then
          if (prev_breadcrumb_path(1:current_len) == global_scan_path(1:current_len)) then
            ! We navigated to a parent directory via breadcrumb
            fwd_path = trim(prev_breadcrumb_path)
            print *, "  Breadcrumb-based lookahead detected: ", trim(fwd_path)
            ! Clear the saved path
            call clear_previous_breadcrumb_path()
          end if
        else
          ! Not a parent navigation, clear the saved path
          call clear_previous_breadcrumb_path()
        end if
      end if

      ! Check if this path matches any entry in history (for breadcrumb clicks)
      ! This syncs nav_history_pos with breadcrumb navigation
      ! Only do this if we're NOT already in a history navigation (back/forward button)
      if (.not. was_navigating_history .and. nav_history_count > 0) then
        matched_pos = 0
        do i = 1, nav_history_count
          if (trim(nav_history(i)) == trim(global_scan_path)) then
            matched_pos = i
            print *, "  Found path in history at position ", i
            exit
          end if
        end do

        if (matched_pos > 0 .and. matched_pos /= nav_history_pos) then
          print *, "  Breadcrumb navigation: syncing history pos from ", nav_history_pos, " to ", matched_pos
          nav_history_pos = matched_pos
          navigating_history = .true.  ! Mark as history navigation to skip add_to_history
        else if (matched_pos > 0) then
          print *, "  Path matches current history position - no sync needed"
        else
          print *, "  Path not found in history - will add as new entry"
        end if
      end if

      ! Get history-based forward path (if available and no breadcrumb lookahead)
      if (len_trim(fwd_path) == 0) then
        fwd_path = get_forward_path()
        if (len_trim(fwd_path) > 0) then
          print *, "  History-based forward path available: ", trim(fwd_path)
        else
          print *, "  No forward path available"
        end if
      end if

      ! Update breadcrumb widget with new path and forward lookahead
      if (len_trim(fwd_path) > 0) then
        call update_breadcrumb_cache(trim(current_view%path), trim(fwd_path))
      else
        call update_breadcrumb_cache(trim(current_view%path))
      end if
    end if

    call sniffly_update_status_bar_stats()

    ! Add to history ONLY if this is a new navigation (not back/forward/breadcrumb)
    ! Check if we have a forward path - if so, we're in history navigation mode
    if (.not. navigating_history .and. len_trim(fwd_path) == 0) then
      ! No forward path AND not navigating history = truly new navigation
      if (len_trim(global_scan_path) > 0) then
        print *, "  Calling add_to_history (new navigation)..."
        call add_to_history(global_scan_path)
      end if
    else
      if (navigating_history) then
        print *, "  Skipping add_to_history (history navigation mode)"
      else
        print *, "  Skipping add_to_history (forward context exists)"
      end if
    end if

    ! ALWAYS reset the flag at the end (ensure it doesn't stick)
    print *, "  Resetting navigating_history flag to false"
    navigating_history = .false.

    ! Update button states now that history may have changed
    call update_history_buttons()
  end subroutine breadcrumb_callback

  ! Show progress bar (now just resets to prepare for updates)
  subroutine sniffly_show_progress()
    ! Guard against accessing widgets during shutdown
    if (app_is_shutting_down) return
    if (c_associated(progress_bar_ptr)) then
      call gtk_progress_bar_set_fraction(progress_bar_ptr, 0.0_c_double)
      call gtk_progress_bar_set_text(progress_bar_ptr, "0%"//c_null_char)
    end if
    ! Update cancel button when progress bar is shown (scan starting)
    call update_cancel_scan_button_state()
  end subroutine sniffly_show_progress

  ! Hide progress bar (now just resets to 0%)
  subroutine sniffly_hide_progress()
    ! Guard against accessing widgets during shutdown
    if (app_is_shutting_down) return
    if (c_associated(progress_bar_ptr)) then
      call gtk_progress_bar_set_fraction(progress_bar_ptr, 0.0_c_double)
      call gtk_progress_bar_set_text(progress_bar_ptr, ""//c_null_char)
    end if
    ! Update cancel button when progress bar is hidden (scan likely stopped)
    call update_cancel_scan_button_state()
  end subroutine sniffly_hide_progress

  ! Update progress bar and status text
  ! fraction: 0.0 to 1.0
  ! message: status text to show
  subroutine sniffly_update_progress(fraction, message)
    real(c_double), intent(in) :: fraction
    character(len=*), intent(in) :: message
    character(len=32) :: percent_str
    integer :: percent_int

    ! Guard against accessing widgets during shutdown
    if (app_is_shutting_down) return

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
    use progressive_scanner, only: stop_progressive_scan
    ! Stop any active scans before quitting
    call stop_progressive_scan()
    call sniffly_app_quit()
  end subroutine quit_callback_wrapper

  ! Callback wrapper for delete events (no arguments)
  subroutine delete_callback_wrapper()
    use treemap_widget, only: get_selected_index
    character(len=:), allocatable :: selected_path
    integer :: confirm_result, selected_idx

    print *, "Delete callback triggered from keyboard"

    ! Check if there's a selection
    if (.not. has_selection()) then
      print *, "No selection - cannot delete"
      return
    end if

    ! Get the selected node path and index
    selected_path = get_selected_node_path()
    selected_idx = get_selected_index()

    if (len_trim(selected_path) == 0) then
      print *, "Invalid selection path"
      return
    end if

    print *, "Preparing to delete: ", trim(selected_path)

    ! Show confirmation dialog
    call show_delete_confirmation(selected_path, confirm_result)

    if (confirm_result == 1) then
      print *, "Delete confirmed - proceeding"
      call delete_to_trash(selected_path, selected_idx)
    else
      print *, "Delete cancelled by user"
    end if
  end subroutine delete_callback_wrapper

  ! Callback wrapper for force refresh events (clear cache and rescan)
  subroutine refresh_callback_wrapper()
    use treemap_renderer, only: clear_cache, invalidate_layout

    print *, "Force refresh triggered from keyboard shortcut"

    ! Clear the directory cache
    call clear_cache()
    call invalidate_layout()

    ! Update status
    call sniffly_update_status("Clearing cache and rescanning...")

    ! Trigger rescan if we have a path
    if (len_trim(global_scan_path) > 0) then
      call trigger_rescan(global_scan_path)
    else
      call sniffly_update_status("No directory to scan")
    end if
  end subroutine refresh_callback_wrapper

  ! Callback wrapper for scan completion
  subroutine scan_complete_callback_wrapper()
    use treemap_widget, only: mark_initial_scan_complete

    print *, "=== SCAN COMPLETE CALLBACK FIRED ==="

    ! Call the original completion callback
    call mark_initial_scan_complete()

    ! Update cancel button (scan is done, should be disabled and grey)
    print *, "=== UPDATING CANCEL BUTTON FROM COMPLETION CALLBACK ==="
    call update_cancel_scan_button_state()

    ! Re-enable back/forward buttons if there's history
    print *, "=== RE-ENABLING NAVIGATION BUTTONS ==="
    call update_history_buttons()
  end subroutine scan_complete_callback_wrapper

  ! Trigger a rescan of the given directory (for UI buttons)
  subroutine trigger_rescan(path)
    use gtk, only: gtk_widget_queue_draw
    use g, only: g_main_context_default, g_main_context_iteration
    use treemap_renderer, only: invalidate_layout
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: normalized_path
    type(c_ptr) :: context
    integer :: i
    integer :: path_len

    print *, "=== TRIGGER_RESCAN ENTERED ==="
    print *, "Triggering rescan of: '", trim(path), "'"
    print *, "Path length: ", len_trim(path)

    ! Remove trailing slash if present (C code doesn't like it)
    path_len = len_trim(path)
    if (path_len > 1 .and. path(path_len:path_len) == '/') then
      normalized_path = trim(path(1:path_len-1))
      print *, "DEBUG: Removed trailing slash. New path: '", normalized_path, "'"
    else
      normalized_path = trim(path)
    end if

    ! Process pending GTK events before starting scan
    context = g_main_context_default()
    do i = 1, 10
      do while (g_main_context_iteration(context, 0_c_int) /= 0_c_int)
      end do
    end do

    print *, "=== ABOUT TO CALL scan_directory ==="
    ! Scan the directory (this will show progress via callbacks)
    call scan_directory(normalized_path)
    print *, "=== RETURNED FROM scan_directory ==="

    ! Update button states (cancel button enabled, navigation disabled during scan)
    call update_cancel_scan_button_state()
    call update_history_buttons()

    ! Process events after scan to update UI
    do i = 1, 10
      do while (g_main_context_iteration(context, 0_c_int) /= 0_c_int)
      end do
    end do

    ! Invalidate layout to force recalculation
    call invalidate_layout()

    ! Update breadcrumbs and status via callback (handles forward path lookahead)
    call breadcrumb_callback()

    ! Trigger redraw to show the scanned data
    if (c_associated(main_window_ptr)) then
      call gtk_widget_queue_draw(main_window_ptr)
    end if

    print *, "=== RESCAN COMPLETE ==="
  end subroutine trigger_rescan

  ! Idle callback for async initial scan
  function perform_initial_scan(user_data) bind(c) result(continue)
    use gtk, only: gtk_widget_queue_draw
    use treemap_renderer, only: invalidate_layout
    type(c_ptr), value :: user_data
    integer(c_int) :: continue

    print *, "Performing initial scan in idle callback..."
    call scan_directory(pending_scan_path)

    ! Note: mark_initial_scan_complete() is now called by the progressive scanner
    ! when the scan actually completes (not immediately when it starts)

    ! Invalidate layout to force recalculation
    call invalidate_layout()

    ! Update breadcrumbs after scan (use pending_scan_path)
    if (len_trim(pending_scan_path) > 0) then
      call update_breadcrumb_cache(trim(pending_scan_path))
    end if

    ! Update status bar with file statistics
    call sniffly_update_status_bar_stats()

    ! Trigger redraw to show the scanned data
    if (c_associated(main_window_ptr)) then
      call gtk_widget_queue_draw(main_window_ptr)
    end if

    ! Return 0 to indicate this callback should not be called again
    continue = 0_c_int
  end function perform_initial_scan

  ! Get user's home directory
  function get_home_directory() result(home_path)
    character(len=512) :: home_path
    character(len=512) :: env_value
    integer :: status

    ! Try to get HOME environment variable
    call get_environment_variable("HOME", env_value, status=status)
    if (status == 0) then
      home_path = trim(env_value)
    else
      ! Fallback to /Users/username on macOS or /home/username on Linux
      home_path = "/Users"
    end if
  end function get_home_directory

end module gtk_app
