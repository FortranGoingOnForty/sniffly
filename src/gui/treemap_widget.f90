! Treemap Widget Module for Sniffly
! Custom GtkDrawingArea widget for rendering treemap visualization
module treemap_widget
  use, intrinsic :: iso_c_binding
  use gtk, only: gtk_drawing_area_new, gtk_drawing_area_set_draw_func, &
                 gtk_widget_set_size_request, gtk_event_controller_motion_new, &
                 gtk_widget_add_controller, g_signal_connect, &
                 gtk_gesture_click_new, gtk_widget_queue_draw
  use treemap_renderer, only: scan_and_render, init_renderer, scan_and_render_with_hover
  implicit none
  private

  public :: create_treemap_widget, set_scan_path, get_widget_ptr

  ! Widget state (will expand later)
  type(c_ptr), save :: widget_ptr = c_null_ptr
  character(len=512), save :: scan_path = ""

  ! Mouse interaction state
  real(c_double), save :: mouse_x = -1.0_c_double
  real(c_double), save :: mouse_y = -1.0_c_double

  ! Selection state
  integer, save :: selected_index = 0  ! 0 = no selection

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

  ! Motion callback - track mouse position for hover
  subroutine on_motion(controller, x, y, user_data) bind(c)
    type(c_ptr), value :: controller, user_data
    real(c_double), value :: x, y

    ! Update mouse position
    mouse_x = x
    mouse_y = y

    ! Trigger redraw to show hover effect
    if (c_associated(widget_ptr)) then
      call gtk_widget_queue_draw(widget_ptr)
    end if
  end subroutine on_motion

  ! Click callback - handle rectangle selection
  subroutine on_click(gesture, n_press, x, y, user_data) bind(c)
    use treemap_renderer, only: find_node_at_position
    type(c_ptr), value :: gesture, user_data
    integer(c_int), value :: n_press
    real(c_double), value :: x, y
    integer :: clicked_index

    ! Find which node was clicked
    clicked_index = find_node_at_position(x, y)

    ! Update selection
    if (clicked_index > 0) then
      selected_index = clicked_index
      print *, "Selected node index: ", selected_index
    else
      ! Click outside any node - deselect
      selected_index = 0
      print *, "Deselected"
    end if

    ! Trigger redraw to show selection
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

end module treemap_widget
