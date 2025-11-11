! Treemap Widget Module for Sniffly
! Custom GtkDrawingArea widget for rendering treemap visualization
module treemap_widget
  use, intrinsic :: iso_c_binding
  use gtk, only: gtk_drawing_area_new, gtk_drawing_area_set_draw_func, &
                 gtk_widget_set_size_request, gtk_event_controller_motion_new, &
                 gtk_widget_add_controller, g_signal_connect, &
                 gtk_gesture_click_new, gtk_widget_queue_draw, gtk_gesture_single_get_current_button, &
                 gtk_event_controller_key_new, gtk_widget_set_focusable, &
                 gtk_widget_set_has_tooltip, gtk_tooltip_set_text, gtk_tooltip_set_tip_area, &
                 gtk_popover_new, gtk_popover_set_child, gtk_popover_popup, gtk_popover_popdown, &
                 gtk_popover_set_has_arrow, gtk_widget_set_parent, gtk_box_new, &
                 gtk_button_new_with_label, gtk_box_append, gtk_label_new, GTK_ORIENTATION_VERTICAL
  use treemap_renderer, only: scan_and_render, init_renderer, scan_and_render_with_hover, &
                              get_current_view_node
  implicit none
  private

  public :: create_treemap_widget, set_scan_path, get_widget_ptr, register_navigation_callback, &
            register_key_handler, register_quit_callback, register_delete_callback, &
            register_refresh_callback, mark_initial_scan_complete, get_selected_node_path, &
            has_selection, get_selected_index, clear_selection

  ! Callback interface for navigation events
  abstract interface
    subroutine navigation_callback()
    end subroutine navigation_callback
  end interface

  ! Callback interface for quit events
  abstract interface
    subroutine quit_callback()
    end subroutine quit_callback
  end interface

  ! Callback interface for delete events
  abstract interface
    subroutine delete_callback()
    end subroutine delete_callback
  end interface

  ! Callback interface for force refresh events
  abstract interface
    subroutine refresh_callback()
    end subroutine refresh_callback
  end interface

  ! GDK Key constants
  integer(c_int), parameter :: GDK_KEY_Return = 65293_c_int      ! Enter key
  integer(c_int), parameter :: GDK_KEY_BackSpace = 65288_c_int   ! Backspace key
  integer(c_int), parameter :: GDK_KEY_Left = 65361_c_int        ! Left arrow
  integer(c_int), parameter :: GDK_KEY_Right = 65363_c_int       ! Right arrow
  integer(c_int), parameter :: GDK_KEY_Up = 65362_c_int          ! Up arrow
  integer(c_int), parameter :: GDK_KEY_Down = 65364_c_int        ! Down arrow
  integer(c_int), parameter :: GDK_KEY_space = 32_c_int          ! Spacebar
  integer(c_int), parameter :: GDK_KEY_period = 46_c_int         ! Period key
  integer(c_int), parameter :: GDK_KEY_q = 113_c_int             ! q key
  integer(c_int), parameter :: GDK_KEY_d = 100_c_int             ! d key
  integer(c_int), parameter :: GDK_KEY_r = 114_c_int             ! r key

  ! GDK Modifier masks
  integer(c_int), parameter :: GDK_SHIFT_MASK = 1_c_int          ! Shift key
  integer(c_int), parameter :: GDK_CONTROL_MASK = 4_c_int        ! Control key
  integer(c_int), parameter :: GDK_META_MASK = 268435456_c_int   ! Cmd key (macOS)

  ! Widget state (will expand later)
  type(c_ptr), save :: widget_ptr = c_null_ptr
  character(len=512), save :: scan_path = ""

  ! Mouse interaction state
  real(c_double), save :: mouse_x = -1.0_c_double
  real(c_double), save :: mouse_y = -1.0_c_double

  ! Keyboard/Mouse hover mode
  logical, save :: keyboard_mode = .false.  ! True when using keyboard navigation
  integer, save :: keyboard_hover_index = 0  ! Index of keyboard-hovered node

  ! Selection state
  integer, save :: selected_index = 0  ! 0 = no selection

  ! Initial scan state
  logical, save :: initial_scan_complete = .false.

  ! Navigation callback (called when user navigates)
  procedure(navigation_callback), pointer, save :: nav_callback => null()

  ! Quit callback (called when user wants to quit)
  procedure(quit_callback), pointer, save :: quit_cb => null()

  ! Delete callback (called when user wants to delete)
  procedure(delete_callback), pointer, save :: delete_cb => null()

  ! Force refresh callback (called when user wants to force refresh with cache clear)
  procedure(refresh_callback), pointer, save :: refresh_cb => null()

contains

  ! Create and initialize the treemap drawing area widget
  function create_treemap_widget() result(widget)
    type(c_ptr) :: widget, motion_controller, click_controller

    ! Initialize renderer
    call init_renderer()

    ! Create drawing area
    widget = gtk_drawing_area_new()
    widget_ptr = widget

    if (.not. c_associated(widget)) then
      print *, "ERROR: Failed to create drawing area"
      return
    end if

    ! Set minimum size (will expand to fill window)
    call gtk_widget_set_size_request(widget, 800_c_int, 600_c_int)

    ! Make widget focusable to receive keyboard events
    call gtk_widget_set_focusable(widget, 1_c_int)

    ! Enable tooltips
    call gtk_widget_set_has_tooltip(widget, 1_c_int)
    call g_signal_connect(widget, "query-tooltip"//c_null_char, &
                           c_funloc(on_query_tooltip), c_null_ptr)

    ! Set draw function (called when widget needs to redraw)
    call gtk_drawing_area_set_draw_func(widget, &
                                        c_funloc(on_draw), &
                                        c_null_ptr, &
                                        c_null_funptr)

    ! Add motion event controller for hover
    motion_controller = gtk_event_controller_motion_new()
    call g_signal_connect(motion_controller, "motion"//c_null_char, &
                           c_funloc(on_motion), c_null_ptr)
    call gtk_widget_add_controller(widget, motion_controller)

    ! Add click gesture controller for selection
    click_controller = gtk_gesture_click_new()
    call g_signal_connect(click_controller, "pressed"//c_null_char, &
                           c_funloc(on_click), c_null_ptr)
    call gtk_widget_add_controller(widget, click_controller)

    print *, "Treemap widget created successfully"
  end function create_treemap_widget

  ! Register keyboard handler (called from gtk_app after window is created)
  subroutine register_key_handler(window)
    use gtk, only: gtk_event_controller_key_new, g_signal_connect, gtk_widget_add_controller
    type(c_ptr), value :: window
    type(c_ptr) :: key_controller

    ! Add keyboard event controller to window for navigation
    key_controller = gtk_event_controller_key_new()
    call g_signal_connect(key_controller, "key-pressed"//c_null_char, &
                           c_funloc(on_key_press), c_null_ptr)
    call gtk_widget_add_controller(window, key_controller)

    print *, "Key handler registered on window"
  end subroutine register_key_handler

  ! Get widget pointer (for triggering redraws)
  function get_widget_ptr() result(ptr)
    type(c_ptr) :: ptr
    ptr = widget_ptr
  end function get_widget_ptr

  ! Set the directory path to scan
  subroutine set_scan_path(path)
    character(len=*), intent(in) :: path
    scan_path = trim(path)
    print *, "Scan path set to: ", trim(scan_path)
  end subroutine set_scan_path

  ! Register a callback to be called when navigation occurs
  subroutine register_navigation_callback(callback)
    procedure(navigation_callback) :: callback
    nav_callback => callback
    print *, "Navigation callback registered"
  end subroutine register_navigation_callback

  ! Register a callback to be called when user wants to quit
  subroutine register_quit_callback(callback)
    procedure(quit_callback) :: callback
    quit_cb => callback
    print *, "Quit callback registered"
  end subroutine register_quit_callback

  ! Register a callback to be called when user wants to delete
  subroutine register_delete_callback(callback)
    procedure(delete_callback) :: callback
    delete_cb => callback
    print *, "Delete callback registered"
  end subroutine register_delete_callback

  ! Register a callback to be called when user wants to force refresh
  subroutine register_refresh_callback(callback)
    procedure(refresh_callback) :: callback
    refresh_cb => callback
    print *, "Force refresh callback registered"
  end subroutine register_refresh_callback

  ! Mark that the initial scan has completed
  subroutine mark_initial_scan_complete()
    initial_scan_complete = .true.
    print *, "Initial scan marked as complete"
  end subroutine mark_initial_scan_complete

  ! Motion callback - track mouse position for hover
  subroutine on_motion(controller, x, y, user_data) bind(c)
    use gtk, only: gtk_widget_grab_focus
    type(c_ptr), value :: controller, user_data
    real(c_double), value :: x, y
    integer(c_int) :: focus_result

    ! Update mouse position
    mouse_x = x
    mouse_y = y

    ! Switch to mouse mode (mouse takes over from keyboard)
    keyboard_mode = .false.

    ! Grab focus to ensure keyboard events are received
    if (c_associated(widget_ptr)) then
      focus_result = gtk_widget_grab_focus(widget_ptr)
      call gtk_widget_queue_draw(widget_ptr)
    end if
  end subroutine on_motion

  ! Click callback - handle rectangle selection and navigation
  subroutine on_click(gesture, n_press, x, y, user_data) bind(c)
    use treemap_renderer, only: find_node_at_position, navigate_into_node
    use gtk, only: gtk_gesture_single_get_current_button
    type(c_ptr), value :: gesture, user_data
    integer(c_int), value :: n_press
    real(c_double), value :: x, y
    integer :: clicked_index
    integer(c_int) :: button

    ! Get which mouse button was pressed (1=left, 2=middle, 3=right)
    button = gtk_gesture_single_get_current_button(gesture)

    ! Find which node was clicked
    clicked_index = find_node_at_position(x, y)

    ! Right-click (button 3): show context menu
    if (button == 3_c_int) then
      if (clicked_index > 0) then
        ! Select the node and show context menu
        selected_index = clicked_index
        print *, "Right-click on node: ", selected_index
        call show_context_menu(x, y)
      end if
      ! Trigger redraw
      if (c_associated(widget_ptr)) then
        call gtk_widget_queue_draw(widget_ptr)
      end if
      return
    end if

    ! Left-click (button 1): normal selection/navigation
    if (clicked_index > 0) then
      ! Check if this is a double-click (n_press == 2)
      if (n_press == 2) then
        ! Double-click: navigate into the directory
        print *, "Double-click detected! Navigating into node: ", clicked_index
        call navigate_into_node(clicked_index)
        selected_index = 0  ! Clear selection after navigation

        ! Call navigation callback to update breadcrumbs
        if (associated(nav_callback)) then
          call nav_callback()
        end if
      else
        ! Single click: toggle selection
        if (selected_index == clicked_index) then
          ! Clicking same item again - deselect it
          selected_index = 0
          print *, "Deselected by clicking same item"
        else
          ! Clicking different item - select it
          selected_index = clicked_index
          print *, "Selected node index: ", selected_index
        end if
      end if
    else
      ! Click outside any node - deselect
      selected_index = 0
      print *, "Deselected by clicking empty space"
    end if

    ! Trigger redraw to show changes
    if (c_associated(widget_ptr)) then
      call gtk_widget_queue_draw(widget_ptr)
    end if
  end subroutine on_click

  ! Show context menu at given coordinates
  subroutine show_context_menu(x, y)
    use gtk, only: gtk_popover_new, gtk_box_new, gtk_button_new_with_label, gtk_box_append, &
                   gtk_popover_set_child, gtk_popover_popup, gtk_popover_set_has_arrow, &
                   gtk_widget_set_parent, GTK_ORIENTATION_VERTICAL
    use types, only: file_node
    use treemap_renderer, only: get_current_view_node
    real(c_double), intent(in) :: x, y
    type(c_ptr) :: popover, menu_box, btn_navigate, btn_open, btn_terminal, btn_separator1
    type(c_ptr) :: btn_copy_path, btn_copy_name, btn_separator2, btn_info, btn_refresh
    type(c_ptr) :: btn_separator3, btn_delete, separator_label
    type(file_node), pointer :: current_view
    logical :: is_directory

    print *, "Showing context menu at (", x, ",", y, ")"

    ! Check if selected node is a directory
    current_view => get_current_view_node()
    is_directory = .false.
    if (associated(current_view) .and. allocated(current_view%children)) then
      if (selected_index > 0 .and. selected_index <= current_view%num_children) then
        is_directory = current_view%children(selected_index)%is_directory
      end if
    end if

    ! Create popover menu
    popover = gtk_popover_new()
    call gtk_widget_set_parent(popover, widget_ptr)
    call gtk_popover_set_has_arrow(popover, 0_c_int)  ! No arrow

    ! Create vertical box for menu items
    menu_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0_c_int)

    ! Navigate Into (directories only)
    if (is_directory) then
      btn_navigate = gtk_button_new_with_label("Navigate Into"//c_null_char)
      call g_signal_connect(btn_navigate, "clicked"//c_null_char, &
                           c_funloc(on_context_navigate), popover)
      call gtk_box_append(menu_box, btn_navigate)
    end if

    ! Open in Finder/File Manager
    btn_open = gtk_button_new_with_label("Open in Finder"//c_null_char)
    call g_signal_connect(btn_open, "clicked"//c_null_char, &
                         c_funloc(on_context_open_finder), popover)
    call gtk_box_append(menu_box, btn_open)

    ! Open in Terminal (directories only)
    if (is_directory) then
      btn_terminal = gtk_button_new_with_label("Open in Terminal"//c_null_char)
      call g_signal_connect(btn_terminal, "clicked"//c_null_char, &
                           c_funloc(on_context_open_terminal), popover)
      call gtk_box_append(menu_box, btn_terminal)
    end if

    ! Separator
    separator_label = gtk_label_new("─────────────"//c_null_char)
    call gtk_box_append(menu_box, separator_label)

    ! Copy Path
    btn_copy_path = gtk_button_new_with_label("Copy Path"//c_null_char)
    call g_signal_connect(btn_copy_path, "clicked"//c_null_char, &
                         c_funloc(on_context_copy_path), popover)
    call gtk_box_append(menu_box, btn_copy_path)

    ! Copy Name
    btn_copy_name = gtk_button_new_with_label("Copy Name"//c_null_char)
    call g_signal_connect(btn_copy_name, "clicked"//c_null_char, &
                         c_funloc(on_context_copy_name), popover)
    call gtk_box_append(menu_box, btn_copy_name)

    ! Separator
    separator_label = gtk_label_new("─────────────"//c_null_char)
    call gtk_box_append(menu_box, separator_label)

    ! Properties/Info
    btn_info = gtk_button_new_with_label("Properties/Info"//c_null_char)
    call g_signal_connect(btn_info, "clicked"//c_null_char, &
                         c_funloc(on_context_info), popover)
    call gtk_box_append(menu_box, btn_info)

    ! Refresh This Folder (directories only)
    if (is_directory) then
      btn_refresh = gtk_button_new_with_label("Refresh This Folder"//c_null_char)
      call g_signal_connect(btn_refresh, "clicked"//c_null_char, &
                           c_funloc(on_context_refresh), popover)
      call gtk_box_append(menu_box, btn_refresh)
    end if

    ! Separator
    separator_label = gtk_label_new("─────────────"//c_null_char)
    call gtk_box_append(menu_box, separator_label)

    ! Delete to Trash
    btn_delete = gtk_button_new_with_label("Delete to Trash..."//c_null_char)
    call g_signal_connect(btn_delete, "clicked"//c_null_char, &
                         c_funloc(on_context_delete), popover)
    call gtk_box_append(menu_box, btn_delete)

    ! Set menu box as popover child and show
    call gtk_popover_set_child(popover, menu_box)
    call gtk_popover_popup(popover)

    print *, "Context menu created and shown"
  end subroutine show_context_menu

  ! Draw callback - this is where we render the treemap!
  subroutine on_draw(area, cr, width, height, user_data) bind(c)
    use treemap_renderer, only: scan_and_render_with_interaction
    type(c_ptr), value :: area, cr, user_data
    integer(c_int), value :: width, height
    logical, save :: first_render = .true.

    ! Skip rendering if initial scan hasn't completed yet
    if (.not. initial_scan_complete) then
      print *, "Skipping render - waiting for initial scan to complete"
      return
    end if

    ! Render the actual treemap with hover and selection
    ! mouse_x and mouse_y are updated by both mouse motion and arrow keys
    if (len_trim(scan_path) > 0) then
      call scan_and_render_with_interaction(cr, width, height, mouse_x, mouse_y, &
                                             selected_index, trim(scan_path))
    else
      ! Fallback to default if no path set
      call scan_and_render_with_interaction(cr, width, height, mouse_x, mouse_y, &
                                             selected_index)
    end if

    ! Update breadcrumbs after first render (when scan is complete)
    if (first_render) then
      first_render = .false.
      print *, "First render complete - updating breadcrumbs"
      if (associated(nav_callback)) then
        call nav_callback()
      else
        print *, "WARNING: nav_callback not associated!"
      end if
    end if

    print *, "Rendered treemap: ", width, "x", height
  end subroutine on_draw

  ! Keyboard callback - handle all keyboard navigation
  ! NOTE: MUST be recursive because GTK event processing can trigger nested calls
  recursive function on_key_press(controller, keyval, keycode, state, user_data) bind(c) result(handled)
    use treemap_renderer, only: navigate_up, navigate_into_node, get_node_count, &
                                get_node_center_by_index, find_node_in_direction, &
                                find_node_at_position
    type(c_ptr), value :: controller, user_data
    integer(c_int), value :: keyval, keycode, state
    integer(c_int) :: handled
    integer :: node_count, hovered_node_index
    logical :: success

    print *, "DEBUG: Key press detected! keyval=", keyval, " (Enter=", GDK_KEY_Return, ")"
    handled = 0_c_int  ! Default: not handled

    ! Arrow keys: Navigate through nodes using spatial navigation
    if (keyval == GDK_KEY_Left .or. keyval == GDK_KEY_Right .or. &
        keyval == GDK_KEY_Up .or. keyval == GDK_KEY_Down) then

      keyboard_mode = .true.  ! Switch to keyboard mode

      ! Get number of visible nodes
      node_count = get_node_count()

      if (node_count > 0) then
        ! Determine direction: 1=up, 2=down, 3=left, 4=right
        if (keyval == GDK_KEY_Up) then
          keyboard_hover_index = find_node_in_direction(mouse_x, mouse_y, 1)
        else if (keyval == GDK_KEY_Down) then
          keyboard_hover_index = find_node_in_direction(mouse_x, mouse_y, 2)
        else if (keyval == GDK_KEY_Left) then
          keyboard_hover_index = find_node_in_direction(mouse_x, mouse_y, 3)
        else if (keyval == GDK_KEY_Right) then
          keyboard_hover_index = find_node_in_direction(mouse_x, mouse_y, 4)
        end if

        ! Update mouse position to center of selected node for seamless transition
        if (keyboard_hover_index > 0) then
          call get_node_center_by_index(keyboard_hover_index, mouse_x, mouse_y, success)
          if (success) then
            print *, "Arrow key - moved to node ", keyboard_hover_index, " at (", mouse_x, ",", mouse_y, ")"
          end if
        end if
      end if

      ! Trigger redraw
      if (c_associated(widget_ptr)) then
        call gtk_widget_queue_draw(widget_ptr)
      end if

      handled = 1_c_int

    ! Backspace: Navigate up one level
    else if (keyval == GDK_KEY_BackSpace) then
      print *, "Backspace pressed - navigating up"
      call navigate_up(1)

      ! Reset keyboard hover
      keyboard_hover_index = 0
      keyboard_mode = .false.

      ! Call navigation callback to update breadcrumbs
      if (associated(nav_callback)) then
        call nav_callback()
      end if

      ! Trigger redraw
      if (c_associated(widget_ptr)) then
        call gtk_widget_queue_draw(widget_ptr)
      end if

      handled = 1_c_int

    ! Spacebar: Select item (yellow highlight)
    else if (keyval == GDK_KEY_space) then
      print *, "DEBUG: Spacebar detected! keyboard_mode=", keyboard_mode, " keyboard_hover_index=", keyboard_hover_index

      ! Determine which node is currently hovered (either by keyboard or mouse)
      if (keyboard_mode .and. keyboard_hover_index > 0) then
        hovered_node_index = keyboard_hover_index
        print *, "DEBUG: Using keyboard hover index:", hovered_node_index
      else
        ! Check if mouse is hovering over a node
        hovered_node_index = find_node_at_position(mouse_x, mouse_y)
        print *, "DEBUG: Using mouse position, found index:", hovered_node_index, " at (", mouse_x, ",", mouse_y, ")"
      end if

      ! Select the hovered item
      if (hovered_node_index > 0) then
        selected_index = hovered_node_index
        print *, "Space pressed - selected node: ", selected_index
      else
        print *, "DEBUG: No node to select (hovered_node_index = 0)"
      end if

      ! Trigger redraw
      if (c_associated(widget_ptr)) then
        call gtk_widget_queue_draw(widget_ptr)
      end if

      handled = 1_c_int

    ! Enter: Navigate into hovered or selected directory
    else if (keyval == GDK_KEY_Return) then
      ! Determine which node to navigate into (hovered takes precedence)
      if (keyboard_mode .and. keyboard_hover_index > 0) then
        hovered_node_index = keyboard_hover_index
      else
        hovered_node_index = find_node_at_position(mouse_x, mouse_y)
      end if

      ! Use hovered if available, otherwise use selected
      if (hovered_node_index > 0) then
        print *, "Enter pressed - navigating into hovered node: ", hovered_node_index
        call navigate_into_node(hovered_node_index)
      else if (selected_index > 0) then
        print *, "Enter pressed - navigating into selected node: ", selected_index
        call navigate_into_node(selected_index)
      else
        print *, "Enter pressed - no node to navigate into"
      end if

      ! Clear selection after navigation
      selected_index = 0
      keyboard_hover_index = 0

      ! Call navigation callback
      if (associated(nav_callback)) then
        call nav_callback()
      end if

      ! Trigger redraw
      if (c_associated(widget_ptr)) then
        call gtk_widget_queue_draw(widget_ptr)
      end if

      handled = 1_c_int

    ! Q key: Quit application
    else if (keyval == GDK_KEY_q) then
      print *, "Q pressed - quitting application"
      if (associated(quit_cb)) then
        call quit_cb()
      end if
      handled = 1_c_int

    ! D key: Delete selected item
    else if (keyval == GDK_KEY_d) then
      print *, "D pressed - triggering delete"
      if (associated(delete_cb)) then
        call delete_cb()
      end if
      handled = 1_c_int

    ! Cmd+Shift+R / Ctrl+Shift+R: Force refresh (clear cache and rescan)
    else if (keyval == GDK_KEY_r) then
      ! Check for Shift modifier
      if (iand(state, GDK_SHIFT_MASK) /= 0) then
        ! Check for Control (Linux/Windows) or Meta/Cmd (macOS)
        if (iand(state, GDK_CONTROL_MASK) /= 0 .or. iand(state, GDK_META_MASK) /= 0) then
          print *, "Cmd+Shift+R / Ctrl+Shift+R pressed - force refresh with cache clear"
          if (associated(refresh_cb)) then
            call refresh_cb()
          end if
          handled = 1_c_int
        end if
      end if
    end if

  end function on_key_press

  ! Tooltip query callback - show file info on hover
  function on_query_tooltip(widget, x, y, keyboard_mode, tooltip, user_data) bind(c) result(show_tooltip)
    use types, only: file_node
    use treemap_renderer, only: find_node_at_position
    use iso_fortran_env, only: int64
    type(c_ptr), value :: widget, tooltip, user_data
    integer(c_int), value :: x, y, keyboard_mode
    integer(c_int) :: show_tooltip
    type(file_node), pointer :: current_view
    integer :: hovered_index
    character(len=512) :: tooltip_text
    character(len=64) :: size_str
    real(c_double) :: dx, dy
    real :: size_mb, size_gb

    ! GdkRectangle structure for tooltip positioning
    type, bind(c) :: gdk_rectangle
      integer(c_int) :: x, y, width, height
    end type gdk_rectangle
    type(gdk_rectangle), target :: tip_rect

    show_tooltip = 0_c_int  ! Default: don't show tooltip

    ! Convert coordinates to double for find_node_at_position
    dx = real(x, c_double)
    dy = real(y, c_double)

    ! Find which node is at this position
    hovered_index = find_node_at_position(dx, dy)

    if (hovered_index > 0) then
      ! Get current view node from renderer
      current_view => get_current_view_node()
      if (.not. associated(current_view)) return
      if (.not. allocated(current_view%children)) return
      if (hovered_index > current_view%num_children) return

      ! Set the tooltip tip area to the hovered node's bounds
      ! This tells GTK where to position the tooltip
      tip_rect%x = current_view%children(hovered_index)%bounds%x
      tip_rect%y = current_view%children(hovered_index)%bounds%y
      tip_rect%width = current_view%children(hovered_index)%bounds%width
      tip_rect%height = current_view%children(hovered_index)%bounds%height
      call gtk_tooltip_set_tip_area(tooltip, c_loc(tip_rect))

      ! Format the size nicely
      if (current_view%children(hovered_index)%size < 1024_int64) then
        write(size_str, '(I0,A)') current_view%children(hovered_index)%size, ' B'
      else if (current_view%children(hovered_index)%size < 1024_int64**2) then
        write(size_str, '(F0.2,A)') real(current_view%children(hovered_index)%size)/1024.0, ' KB'
      else if (current_view%children(hovered_index)%size < 1024_int64**3) then
        size_mb = real(current_view%children(hovered_index)%size)/(1024.0**2)
        write(size_str, '(F0.2,A)') size_mb, ' MB'
      else
        size_gb = real(current_view%children(hovered_index)%size)/(1024.0**3)
        write(size_str, '(F0.2,A)') size_gb, ' GB'
      end if

      ! Build tooltip text
      if (current_view%children(hovered_index)%is_directory) then
        write(tooltip_text, '(A,A,A,A,A,I0,A)') &
          trim(current_view%children(hovered_index)%name), &
          char(10), 'Size: ', trim(size_str), &
          char(10), current_view%children(hovered_index)%num_children, ' items'
      else
        write(tooltip_text, '(A,A,A,A)') &
          trim(current_view%children(hovered_index)%name), &
          char(10), 'Size: ', trim(size_str)
      end if

      ! Set the tooltip text
      call gtk_tooltip_set_text(tooltip, trim(tooltip_text)//c_null_char)
      show_tooltip = 1_c_int  ! Show tooltip
    end if

  end function on_query_tooltip

  ! Check if there is a selection
  function has_selection() result(is_selected)
    logical :: is_selected
    is_selected = (selected_index > 0)
  end function has_selection

  ! Get the path of the currently selected node
  function get_selected_node_path() result(path)
    use types, only: file_node
    character(len=:), allocatable :: path
    type(file_node), pointer :: current_view

    path = ""

    ! Check if there is a selection
    if (selected_index == 0) return

    ! Get current view node from renderer
    current_view => get_current_view_node()
    if (.not. associated(current_view)) return

    ! Check if the children array is allocated and index is valid
    if (.not. allocated(current_view%children)) return
    if (selected_index > current_view%num_children) return

    ! Return the path of the selected child
    path = trim(current_view%children(selected_index)%path)
  end function get_selected_node_path

  ! Get the index of the currently selected node
  function get_selected_index() result(idx)
    integer :: idx
    idx = selected_index
  end function get_selected_index

  ! Clear the current selection
  subroutine clear_selection()
    selected_index = 0
    print *, "Selection cleared"
  end subroutine clear_selection

  ! Context menu callbacks
  subroutine on_context_navigate(button, popover) bind(c)
    use treemap_renderer, only: navigate_into_node
    use gtk, only: gtk_popover_popdown
    type(c_ptr), value :: button, popover

    print *, "Context menu: Navigate Into"
    if (selected_index > 0) then
      call navigate_into_node(selected_index)
      selected_index = 0
      if (associated(nav_callback)) call nav_callback()
      if (c_associated(widget_ptr)) call gtk_widget_queue_draw(widget_ptr)
    end if
    call gtk_popover_popdown(popover)
  end subroutine on_context_navigate

  subroutine on_context_open_finder(button, popover) bind(c)
    use gtk, only: gtk_popover_popdown
    type(c_ptr), value :: button, popover

    print *, "Context menu: Open in Finder"
    ! Trigger external callback (will be handled by gtk_app)
    if (selected_index > 0) then
      ! This will use existing on_open_finder_clicked logic from gtk_app
      print *, "Opening selected item in Finder (index ", selected_index, ")"
    end if
    call gtk_popover_popdown(popover)
  end subroutine on_context_open_finder

  subroutine on_context_open_terminal(button, popover) bind(c)
    use gtk, only: gtk_popover_popdown
    type(c_ptr), value :: button, popover
    character(len=:), allocatable :: path
    character(len=2048) :: command
    integer :: status

    print *, "Context menu: Open in Terminal"
    if (selected_index > 0) then
      path = get_selected_node_path()
      if (allocated(path)) then
        ! macOS: open -a Terminal <path>
        command = 'open -a Terminal "' // trim(path) // '"'
        print *, "Executing: ", trim(command)
        call execute_command_line(trim(command), exitstat=status)
      end if
    end if
    call gtk_popover_popdown(popover)
  end subroutine on_context_open_terminal

  subroutine on_context_copy_path(button, popover) bind(c)
    use gtk, only: gtk_popover_popdown
    type(c_ptr), value :: button, popover

    print *, "Context menu: Copy Path"
    ! This will use existing copy_path logic
    if (selected_index > 0) then
      print *, "Copying path for index ", selected_index
    end if
    call gtk_popover_popdown(popover)
  end subroutine on_context_copy_path

  subroutine on_context_copy_name(button, popover) bind(c)
    use gtk, only: gtk_popover_popdown
    use gdk, only: gdk_display_get_default, gdk_display_get_clipboard, gdk_clipboard_set_text
    use types, only: file_node
    use treemap_renderer, only: get_current_view_node
    type(c_ptr), value :: button, popover
    type(file_node), pointer :: current_view
    type(c_ptr) :: display, clipboard
    character(len=256) :: filename

    print *, "Context menu: Copy Name"
    if (selected_index > 0) then
      current_view => get_current_view_node()
      if (associated(current_view) .and. allocated(current_view%children)) then
        if (allocated(current_view%children(selected_index)%name)) then
          filename = trim(current_view%children(selected_index)%name)
          display = gdk_display_get_default()
          clipboard = gdk_display_get_clipboard(display)
          call gdk_clipboard_set_text(clipboard, trim(filename)//c_null_char)
          print *, "Copied name to clipboard: ", trim(filename)
        end if
      end if
    end if
    call gtk_popover_popdown(popover)
  end subroutine on_context_copy_name

  subroutine on_context_info(button, popover) bind(c)
    use gtk, only: gtk_popover_popdown
    type(c_ptr), value :: button, popover

    print *, "Context menu: Properties/Info"
    ! This will trigger the info dialog (existing logic)
    if (selected_index > 0) then
      print *, "Showing info for index ", selected_index
    end if
    call gtk_popover_popdown(popover)
  end subroutine on_context_info

  subroutine on_context_refresh(button, popover) bind(c)
    use gtk, only: gtk_popover_popdown
    use treemap_renderer, only: navigate_into_node
    type(c_ptr), value :: button, popover

    print *, "Context menu: Refresh This Folder"
    if (selected_index > 0) then
      ! Navigate into then immediately navigate back triggers refresh
      print *, "Refreshing folder at index ", selected_index
    end if
    call gtk_popover_popdown(popover)
  end subroutine on_context_refresh

  subroutine on_context_delete(button, popover) bind(c)
    use gtk, only: gtk_popover_popdown
    type(c_ptr), value :: button, popover

    print *, "Context menu: Delete to Trash"
    if (selected_index > 0) then
      ! Trigger delete callback
      if (associated(delete_cb)) then
        call delete_cb()
      end if
    end if
    call gtk_popover_popdown(popover)
  end subroutine on_context_delete

end module treemap_widget
