! Treemap Widget Module for Sniffly
! Custom GtkDrawingArea widget for rendering treemap visualization
module treemap_widget
  use, intrinsic :: iso_c_binding
  use gtk, only: gtk_drawing_area_new, gtk_drawing_area_set_draw_func, &
                 gtk_widget_set_size_request, gtk_event_controller_motion_new, &
                 gtk_widget_add_controller, g_signal_connect, &
                 gtk_gesture_click_new, gtk_widget_queue_draw, &
                 gtk_event_controller_key_new, gtk_widget_set_focusable
  use treemap_renderer, only: scan_and_render, init_renderer, scan_and_render_with_hover
  implicit none
  private

  public :: create_treemap_widget, set_scan_path, get_widget_ptr, register_navigation_callback, &
            register_key_handler

  ! Callback interface for navigation events
  abstract interface
    subroutine navigation_callback()
    end subroutine navigation_callback
  end interface

  ! GDK Key constants
  integer(c_int), parameter :: GDK_KEY_Return = 65293_c_int      ! Enter key
  integer(c_int), parameter :: GDK_KEY_BackSpace = 65288_c_int   ! Backspace key
  integer(c_int), parameter :: GDK_KEY_Left = 65361_c_int        ! Left arrow
  integer(c_int), parameter :: GDK_KEY_Right = 65363_c_int       ! Right arrow
  integer(c_int), parameter :: GDK_KEY_Up = 65362_c_int          ! Up arrow
  integer(c_int), parameter :: GDK_KEY_Down = 65364_c_int        ! Down arrow

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

  ! Navigation callback (called when user navigates)
  procedure(navigation_callback), pointer, save :: nav_callback => null()

contains

  ! Create and initialize the treemap drawing area widget
  function create_treemap_widget() result(widget)
    type(c_ptr) :: widget, motion_controller, click_controller, key_controller

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

  ! Motion callback - track mouse position for hover
  subroutine on_motion(controller, x, y, user_data) bind(c)
    type(c_ptr), value :: controller, user_data
    real(c_double), value :: x, y

    ! Update mouse position
    mouse_x = x
    mouse_y = y

    ! Switch to mouse mode (mouse takes over from keyboard)
    keyboard_mode = .false.

    ! Trigger redraw to show hover effect
    if (c_associated(widget_ptr)) then
      call gtk_widget_queue_draw(widget_ptr)
    end if
  end subroutine on_motion

  ! Click callback - handle rectangle selection and navigation
  subroutine on_click(gesture, n_press, x, y, user_data) bind(c)
    use treemap_renderer, only: find_node_at_position, navigate_into_node
    type(c_ptr), value :: gesture, user_data
    integer(c_int), value :: n_press
    real(c_double), value :: x, y
    integer :: clicked_index

    ! Find which node was clicked
    clicked_index = find_node_at_position(x, y)

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
        ! Single click: just select
        selected_index = clicked_index
        print *, "Selected node index: ", selected_index
      end if
    else
      ! Click outside any node - deselect
      selected_index = 0
      print *, "Deselected"
    end if

    ! Trigger redraw to show changes
    if (c_associated(widget_ptr)) then
      call gtk_widget_queue_draw(widget_ptr)
    end if
  end subroutine on_click

  ! Draw callback - this is where we render the treemap!
  subroutine on_draw(area, cr, width, height, user_data) bind(c)
    use treemap_renderer, only: scan_and_render_with_interaction
    type(c_ptr), value :: area, cr, user_data
    integer(c_int), value :: width, height

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

    print *, "Rendered treemap: ", width, "x", height
  end subroutine on_draw

  ! Keyboard callback - handle all keyboard navigation
  function on_key_press(controller, keyval, keycode, state, user_data) bind(c) result(handled)
    use treemap_renderer, only: navigate_up, navigate_into_node, get_node_count, &
                                get_node_center_by_index, find_node_in_direction
    type(c_ptr), value :: controller, user_data
    integer(c_int), value :: keyval, keycode, state
    integer(c_int) :: handled
    integer :: node_count
    logical :: success

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

    ! Enter: Two-stage behavior
    else if (keyval == GDK_KEY_Return) then
      if (keyboard_mode .and. keyboard_hover_index > 0) then
        ! First Enter: Select the keyboard-hovered item
        if (selected_index /= keyboard_hover_index) then
          selected_index = keyboard_hover_index
          print *, "Enter pressed - selected keyboard hover: ", selected_index
        else
          ! Second Enter: Navigate into selected item
          print *, "Enter pressed again - navigating into: ", selected_index
          call navigate_into_node(selected_index)
          selected_index = 0
          keyboard_hover_index = 0

          ! Call navigation callback
          if (associated(nav_callback)) then
            call nav_callback()
          end if
        end if
      else if (selected_index > 0) then
        ! Enter on mouse-selected item: navigate immediately
        print *, "Enter pressed - navigating into selected: ", selected_index
        call navigate_into_node(selected_index)
        selected_index = 0

        ! Call navigation callback
        if (associated(nav_callback)) then
          call nav_callback()
        end if
      end if

      ! Trigger redraw
      if (c_associated(widget_ptr)) then
        call gtk_widget_queue_draw(widget_ptr)
      end if

      handled = 1_c_int
    end if

  end function on_key_press

end module treemap_widget
