! Treemap Widget Module for Sniffly
! Custom GtkDrawingArea widget for rendering treemap visualization
module treemap_widget
  use, intrinsic :: iso_c_binding
  use gtk, only: gtk_drawing_area_new, gtk_drawing_area_set_draw_func, &
                 gtk_widget_set_size_request
  use treemap_renderer, only: scan_and_render, init_renderer
  implicit none
  private

  public :: create_treemap_widget

  ! Widget state (will expand later)
  type(c_ptr), save :: widget_ptr = c_null_ptr

contains

  ! Create and initialize the treemap drawing area widget
  function create_treemap_widget() result(widget)
    type(c_ptr) :: widget

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

    print *, "Treemap widget created successfully"
  end function create_treemap_widget

  ! Draw callback - this is where we render the treemap!
  subroutine on_draw(area, cr, width, height, user_data) bind(c)
    type(c_ptr), value :: area, cr, user_data
    integer(c_int), value :: width, height

    ! Render the actual treemap!
    call scan_and_render(cr, width, height)

    print *, "Rendered treemap: ", width, "x", height
  end subroutine on_draw

end module treemap_widget
