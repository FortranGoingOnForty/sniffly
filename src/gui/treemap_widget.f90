! Treemap Widget Module for Sniffly
! Custom GtkDrawingArea widget for rendering treemap visualization
module treemap_widget
  use, intrinsic :: iso_c_binding
  use gtk, only: gtk_drawing_area_new, gtk_drawing_area_set_draw_func, &
                 gtk_widget_set_size_request
  implicit none
  private

  public :: create_treemap_widget

  ! Widget state (will expand later)
  type(c_ptr), save :: widget_ptr = c_null_ptr

contains

  ! Create and initialize the treemap drawing area widget
  function create_treemap_widget() result(widget)
    type(c_ptr) :: widget

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

    ! For now, just draw a test pattern to verify Cairo works
    ! We'll replace this with actual treemap rendering later
    call draw_test_pattern(cr, width, height)
  end subroutine on_draw

  ! Test pattern to verify Cairo rendering works
  subroutine draw_test_pattern(cr, width, height)
    use cairo, only: cairo_set_source_rgb, cairo_rectangle, cairo_fill, &
                     cairo_stroke, cairo_set_line_width
    type(c_ptr), intent(in) :: cr
    integer(c_int), intent(in) :: width, height
    real(c_double) :: w, h

    w = real(width, c_double)
    h = real(height, c_double)

    ! Background: light gray
    call cairo_set_source_rgb(cr, 0.95d0, 0.95d0, 0.95d0)
    call cairo_rectangle(cr, 0.0d0, 0.0d0, w, h)
    call cairo_fill(cr)

    ! Draw test rectangles (simulating treemap blocks)

    ! Large blue rectangle (simulating a big directory)
    call cairo_set_source_rgb(cr, 0.2d0, 0.4d0, 0.8d0)
    call cairo_rectangle(cr, 50.0d0, 50.0d0, w*0.4d0, h*0.6d0)
    call cairo_fill(cr)

    ! Medium green rectangle
    call cairo_set_source_rgb(cr, 0.2d0, 0.8d0, 0.2d0)
    call cairo_rectangle(cr, 50.0d0 + w*0.4d0 + 10.0d0, 50.0d0, w*0.3d0, h*0.4d0)
    call cairo_fill(cr)

    ! Small red rectangle
    call cairo_set_source_rgb(cr, 0.8d0, 0.2d0, 0.2d0)
    call cairo_rectangle(cr, 50.0d0, 50.0d0 + h*0.6d0 + 10.0d0, w*0.5d0, h*0.25d0)
    call cairo_fill(cr)

    ! Draw borders around rectangles
    call cairo_set_source_rgb(cr, 0.0d0, 0.0d0, 0.0d0)
    call cairo_set_line_width(cr, 2.0d0)

    call cairo_rectangle(cr, 50.0d0, 50.0d0, w*0.4d0, h*0.6d0)
    call cairo_stroke(cr)

    call cairo_rectangle(cr, 50.0d0 + w*0.4d0 + 10.0d0, 50.0d0, w*0.3d0, h*0.4d0)
    call cairo_stroke(cr)

    call cairo_rectangle(cr, 50.0d0, 50.0d0 + h*0.6d0 + 10.0d0, w*0.5d0, h*0.25d0)
    call cairo_stroke(cr)

    print *, "Drew test pattern: ", width, "x", height
  end subroutine draw_test_pattern

end module treemap_widget
