! Cairo-rendered Filing Cabinet Tab Bar for Sniffly
! Custom tab bar with squarrounded tabs that resemble filing cabinet tabs
module cairo_tab_bar
  use, intrinsic :: iso_c_binding
  use gtk, only: gtk_drawing_area_new, gtk_drawing_area_set_draw_func, &
                 gtk_widget_set_size_request, gtk_event_controller_motion_new, &
                 gtk_widget_add_controller, gtk_gesture_click_new, &
                 gtk_widget_queue_draw, gtk_widget_set_hexpand, g_signal_connect
  use cairo, only: cairo_set_source_rgb, cairo_set_source_rgba, cairo_move_to, &
                   cairo_line_to, cairo_curve_to, cairo_fill, cairo_stroke, &
                   cairo_set_line_width, cairo_arc
  use pango, only: pango_cairo_create_layout, pango_layout_set_text, &
                   pango_font_description_from_string, pango_layout_set_font_description, &
                   pango_cairo_show_layout, pango_layout_get_pixel_size, &
                   pango_font_description_free
  implicit none
  private

  public :: create_cairo_tab_bar, refresh_cairo_tab_bar, get_cairo_tab_bar_widget, &
            register_cairo_tab_switch_callback, register_cairo_tab_close_callback, &
            register_cairo_new_tab_callback

  ! Tab dimensions
  integer, parameter :: TAB_HEIGHT = 32
  integer, parameter :: TAB_MIN_WIDTH = 120
  integer, parameter :: TAB_MAX_WIDTH = 200
  integer, parameter :: TAB_CORNER_RADIUS = 8
  integer, parameter :: TAB_OVERLAP = 10
  integer, parameter :: PLUS_BUTTON_WIDTH = 32
  integer, parameter :: CLOSE_BUTTON_SIZE = 16
  integer, parameter :: CLOSE_BUTTON_MARGIN = 8

  ! Tab bar state
  type(c_ptr), save :: tab_bar_widget = c_null_ptr
  integer, save :: hovered_tab = 0  ! 0 = none, -1 = plus button, 1+ = tab index
  integer, save :: hovered_close_button = 0  ! Which tab's close button is hovered

  ! Tab bounds for hit testing
  type :: tab_bounds
    integer :: x, y, width, height
    integer :: close_x, close_y  ! Close button position
  end type tab_bounds

  type(tab_bounds), dimension(5), save :: tab_rects  ! Max 5 tabs
  integer :: plus_button_x, plus_button_y

  ! Callback interfaces
  abstract interface
    subroutine tab_switch_callback(tab_index)
      integer, intent(in) :: tab_index
    end subroutine tab_switch_callback

    subroutine tab_close_callback(tab_index)
      integer, intent(in) :: tab_index
    end subroutine tab_close_callback

    subroutine new_tab_callback()
    end subroutine new_tab_callback
  end interface

  ! Registered callbacks
  procedure(tab_switch_callback), pointer, save :: switch_cb => null()
  procedure(tab_close_callback), pointer, save :: close_cb => null()
  procedure(new_tab_callback), pointer, save :: new_tab_cb => null()

contains

  ! Create the Cairo-rendered tab bar
  function create_cairo_tab_bar() result(widget)
    type(c_ptr) :: widget, motion_controller, click_controller

    ! Create drawing area
    widget = gtk_drawing_area_new()
    tab_bar_widget = widget

    if (.not. c_associated(widget)) then
      print *, "ERROR: Failed to create cairo tab bar drawing area"
      return
    end if

    ! Set fixed height, expand horizontally
    call gtk_widget_set_size_request(widget, -1_c_int, TAB_HEIGHT)
    call gtk_widget_set_hexpand(widget, 1_c_int)

    ! Set draw function
    call gtk_drawing_area_set_draw_func(widget, c_funloc(on_draw_tabs), &
                                        c_null_ptr, c_null_ptr)

    ! Add motion controller for hover effects
    motion_controller = gtk_event_controller_motion_new()
    call g_signal_connect(motion_controller, "motion"//c_null_char, &
                          c_funloc(on_tab_motion), c_null_ptr)
    call g_signal_connect(motion_controller, "leave"//c_null_char, &
                          c_funloc(on_tab_leave), c_null_ptr)
    call gtk_widget_add_controller(widget, motion_controller)

    ! Add click controller
    click_controller = gtk_gesture_click_new()
    call g_signal_connect(click_controller, "pressed"//c_null_char, &
                          c_funloc(on_tab_click), c_null_ptr)
    call gtk_widget_add_controller(widget, click_controller)

    print *, "Cairo tab bar created"
  end function create_cairo_tab_bar

  ! Draw the tab bar
  subroutine on_draw_tabs(area, cr, width, height, user_data) bind(c)
    use tab_manager, only: num_tabs, active_tab_index, get_tab, tab_state
    type(c_ptr), value :: area, cr, user_data
    integer(c_int), value :: width, height
    type(tab_state), pointer :: tab
    integer :: i, tab_x, tab_width, total_tabs_width
    real(c_double) :: r, g, b, alpha

    ! Clear background
    call cairo_set_source_rgb(cr, 0.95_c_double, 0.95_c_double, 0.95_c_double)
    call cairo_move_to(cr, 0.0_c_double, 0.0_c_double)
    call cairo_line_to(cr, real(width, c_double), 0.0_c_double)
    call cairo_line_to(cr, real(width, c_double), real(height, c_double))
    call cairo_line_to(cr, 0.0_c_double, real(height, c_double))
    call cairo_fill(cr)

    ! Calculate starting position (flush to right edge, no overlap between tabs)
    total_tabs_width = num_tabs * TAB_MIN_WIDTH + PLUS_BUTTON_WIDTH
    tab_x = width - total_tabs_width

    ! Draw plus button first (leftmost)
    call draw_plus_button(cr, tab_x, 0)
    plus_button_x = tab_x
    plus_button_y = 0
    tab_x = tab_x + PLUS_BUTTON_WIDTH

    ! First pass: calculate positions and store in tab_rects
    do i = 1, num_tabs
      tab => get_tab(i)
      if (.not. associated(tab)) cycle

      tab_width = TAB_MIN_WIDTH

      ! Store bounds for hit testing
      tab_rects(i)%x = tab_x
      tab_rects(i)%y = 0
      tab_rects(i)%width = tab_width
      tab_rects(i)%height = TAB_HEIGHT

      ! No overlap - tabs sit flush next to each other
      tab_x = tab_x + tab_width
    end do

    ! Second pass: draw inactive tabs first (so they appear behind)
    do i = 1, num_tabs
      if (i == active_tab_index) cycle  ! Skip active tab
      tab => get_tab(i)
      if (.not. associated(tab)) cycle

      call draw_inactive_tab(cr, tab_rects(i)%x, TAB_MIN_WIDTH, trim(tab%label), i == hovered_tab, i)
    end do

    ! Third pass: draw active tab last (so it appears on top)
    if (active_tab_index >= 1 .and. active_tab_index <= num_tabs) then
      tab => get_tab(active_tab_index)
      if (associated(tab)) then
        call draw_active_tab(cr, tab_rects(active_tab_index)%x, TAB_MIN_WIDTH, &
                           trim(tab%label), active_tab_index == hovered_tab, active_tab_index)
      end if
    end if
  end subroutine on_draw_tabs

  ! Draw an active tab (full brightness, merges into canvas)
  subroutine draw_active_tab(cr, x, width, label, is_hovered, tab_index)
    type(c_ptr), intent(in) :: cr
    integer, intent(in) :: x, width, tab_index
    character(len=*), intent(in) :: label
    logical, intent(in) :: is_hovered
    real(c_double) :: x_d, y_d, w_d, h_d, radius

    x_d = real(x, c_double)
    y_d = 0.0_c_double
    w_d = real(width, c_double)
    h_d = real(TAB_HEIGHT, c_double)
    radius = real(TAB_CORNER_RADIUS, c_double)

    ! Draw squarrounded shape (rounded top, flat bottom)
    call cairo_move_to(cr, x_d, h_d)  ! Bottom left
    call cairo_line_to(cr, x_d, y_d + radius)  ! Left edge
    call cairo_arc(cr, x_d + radius, y_d + radius, radius, 3.14159_c_double, -1.57080_c_double)  ! Top left corner
    call cairo_line_to(cr, x_d + w_d - radius, y_d)  ! Top edge
    call cairo_arc(cr, x_d + w_d - radius, y_d + radius, radius, -1.57080_c_double, 0.0_c_double)  ! Top right corner
    call cairo_line_to(cr, x_d + w_d, h_d)  ! Right edge to bottom

    ! Fill with white/light gray (active color)
    if (is_hovered) then
      call cairo_set_source_rgb(cr, 1.0_c_double, 1.0_c_double, 1.0_c_double)
    else
      call cairo_set_source_rgb(cr, 0.98_c_double, 0.98_c_double, 0.98_c_double)
    end if
    call cairo_fill(cr)

    ! Draw border (but not bottom for "seeping" effect)
    call draw_tab_border_no_bottom(cr, x_d, y_d, w_d, h_d, radius)

    ! Draw label
    call draw_tab_label(cr, x, 0, width, TAB_HEIGHT, label, .false.)

    ! Draw close button
    call draw_close_button(cr, x, width, .false., tab_index)
  end subroutine draw_active_tab

  ! Draw an inactive tab (dimmed, with bottom border)
  subroutine draw_inactive_tab(cr, x, width, label, is_hovered, tab_index)
    type(c_ptr), intent(in) :: cr
    integer, intent(in) :: x, width, tab_index
    character(len=*), intent(in) :: label
    logical, intent(in) :: is_hovered
    real(c_double) :: x_d, y_d, w_d, h_d, radius

    x_d = real(x, c_double)
    y_d = 2.0_c_double  ! Slightly lower than active
    w_d = real(width, c_double)
    h_d = real(TAB_HEIGHT - 2, c_double)
    radius = real(TAB_CORNER_RADIUS, c_double)

    ! Draw squarrounded shape
    call cairo_move_to(cr, x_d, y_d + h_d)  ! Bottom left
    call cairo_line_to(cr, x_d, y_d + radius)  ! Left edge
    call cairo_arc(cr, x_d + radius, y_d + radius, radius, 3.14159_c_double, -1.57080_c_double)
    call cairo_line_to(cr, x_d + w_d - radius, y_d)
    call cairo_arc(cr, x_d + w_d - radius, y_d + radius, radius, -1.57080_c_double, 0.0_c_double)
    call cairo_line_to(cr, x_d + w_d, y_d + h_d)

    ! Fill with darker gray (inactive)
    if (is_hovered) then
      call cairo_set_source_rgb(cr, 0.88_c_double, 0.88_c_double, 0.88_c_double)
    else
      call cairo_set_source_rgb(cr, 0.82_c_double, 0.82_c_double, 0.82_c_double)
    end if
    call cairo_fill(cr)

    ! Draw full border including bottom
    call draw_tab_border_full(cr, x_d, y_d, w_d, h_d, radius)

    ! Draw label (dimmed)
    call draw_tab_label(cr, x, 2, width, TAB_HEIGHT - 2, label, .true.)

    ! Draw close button
    call draw_close_button(cr, x, width, .true., tab_index)
  end subroutine draw_inactive_tab

  ! Draw tab border without bottom (for active tab)
  subroutine draw_tab_border_no_bottom(cr, x, y, width, height, radius)
    type(c_ptr), intent(in) :: cr
    real(c_double), intent(in) :: x, y, width, height, radius

    call cairo_set_source_rgb(cr, 0.7_c_double, 0.7_c_double, 0.7_c_double)
    call cairo_set_line_width(cr, 1.0_c_double)

    call cairo_move_to(cr, x, y + height)
    call cairo_line_to(cr, x, y + radius)
    call cairo_arc(cr, x + radius, y + radius, radius, 3.14159_c_double, -1.57080_c_double)
    call cairo_line_to(cr, x + width - radius, y)
    call cairo_arc(cr, x + width - radius, y + radius, radius, -1.57080_c_double, 0.0_c_double)
    call cairo_line_to(cr, x + width, y + height)
    call cairo_stroke(cr)
  end subroutine draw_tab_border_no_bottom

  ! Draw full tab border (for inactive tabs)
  subroutine draw_tab_border_full(cr, x, y, width, height, radius)
    type(c_ptr), intent(in) :: cr
    real(c_double), intent(in) :: x, y, width, height, radius

    call cairo_set_source_rgb(cr, 0.6_c_double, 0.6_c_double, 0.6_c_double)
    call cairo_set_line_width(cr, 1.0_c_double)

    call cairo_move_to(cr, x, y + height)
    call cairo_line_to(cr, x, y + radius)
    call cairo_arc(cr, x + radius, y + radius, radius, 3.14159_c_double, -1.57080_c_double)
    call cairo_line_to(cr, x + width - radius, y)
    call cairo_arc(cr, x + width - radius, y + radius, radius, -1.57080_c_double, 0.0_c_double)
    call cairo_line_to(cr, x + width, y + height)
    call cairo_line_to(cr, x, y + height)
    call cairo_stroke(cr)
  end subroutine draw_tab_border_full

  ! Draw tab label text
  subroutine draw_tab_label(cr, x, y, width, height, text, is_dimmed)
    use pango, only: pango_layout_set_width, pango_layout_set_ellipsize
    type(c_ptr), intent(in) :: cr
    integer, intent(in) :: x, y, width, height
    character(len=*), intent(in) :: text
    logical, intent(in) :: is_dimmed
    type(c_ptr) :: layout, font_desc
    integer(c_int), target :: text_width, text_height
    integer(c_int) :: max_text_width
    real(c_double) :: text_x, text_y

    ! Pango constants (not available in gtk-fortran bindings)
    integer(c_int), parameter :: PANGO_SCALE = 1024
    integer(c_int), parameter :: PANGO_ELLIPSIZE_END = 3

    ! Create pango layout
    layout = pango_cairo_create_layout(cr)
    call pango_layout_set_text(layout, trim(text)//c_null_char, -1_c_int)

    ! Set font
    font_desc = pango_font_description_from_string("Sans 10"//c_null_char)
    call pango_layout_set_font_description(layout, font_desc)

    ! Calculate maximum width for text (leave room for close button and some padding)
    max_text_width = width - CLOSE_BUTTON_SIZE - CLOSE_BUTTON_MARGIN - 10

    ! Enable ellipsization to truncate long text
    call pango_layout_set_width(layout, max_text_width * PANGO_SCALE)
    call pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END)

    ! Get text size (after ellipsization)
    call pango_layout_get_pixel_size(layout, c_loc(text_width), c_loc(text_height))

    ! Center text in tab (leaving room for close button)
    text_x = real(x, c_double) + real(width - CLOSE_BUTTON_SIZE - CLOSE_BUTTON_MARGIN - text_width, c_double) / 2.0_c_double
    text_y = real(y, c_double) + real(height - text_height, c_double) / 2.0_c_double

    ! Set text color
    if (is_dimmed) then
      call cairo_set_source_rgb(cr, 0.4_c_double, 0.4_c_double, 0.4_c_double)
    else
      call cairo_set_source_rgb(cr, 0.2_c_double, 0.2_c_double, 0.2_c_double)
    end if

    call cairo_move_to(cr, text_x, text_y)
    call pango_cairo_show_layout(cr, layout)

    call pango_font_description_free(font_desc)
  end subroutine draw_tab_label

  ! Draw close button (×)
  subroutine draw_close_button(cr, tab_x, tab_width, is_dimmed, tab_index)
    type(c_ptr), intent(in) :: cr
    integer, intent(in) :: tab_x, tab_width, tab_index
    logical, intent(in) :: is_dimmed
    real(c_double) :: btn_x, btn_y, btn_size, center_x, center_y
    logical :: is_hovered

    btn_x = real(tab_x + tab_width - CLOSE_BUTTON_SIZE - CLOSE_BUTTON_MARGIN, c_double)
    btn_y = real((TAB_HEIGHT - CLOSE_BUTTON_SIZE) / 2, c_double)
    btn_size = real(CLOSE_BUTTON_SIZE, c_double)
    center_x = btn_x + btn_size / 2.0_c_double
    center_y = btn_y + btn_size / 2.0_c_double

    ! Check if this close button is hovered
    is_hovered = (hovered_close_button == tab_index)

    ! Draw circular background when hovered
    if (is_hovered) then
      call cairo_set_source_rgb(cr, 0.6_c_double, 0.6_c_double, 0.6_c_double)
      call cairo_arc(cr, center_x, center_y, btn_size / 2.0_c_double, 0.0_c_double, 6.28319_c_double)
      call cairo_fill(cr)
    end if

    ! Draw × symbol
    call cairo_set_line_width(cr, 1.5_c_double)
    if (is_hovered) then
      ! White × when hovered
      call cairo_set_source_rgb(cr, 1.0_c_double, 1.0_c_double, 1.0_c_double)
    else if (is_dimmed) then
      call cairo_set_source_rgb(cr, 0.5_c_double, 0.5_c_double, 0.5_c_double)
    else
      call cairo_set_source_rgb(cr, 0.3_c_double, 0.3_c_double, 0.3_c_double)
    end if

    ! Draw X
    call cairo_move_to(cr, btn_x + 4.0_c_double, btn_y + 4.0_c_double)
    call cairo_line_to(cr, btn_x + btn_size - 4.0_c_double, btn_y + btn_size - 4.0_c_double)
    call cairo_stroke(cr)

    call cairo_move_to(cr, btn_x + btn_size - 4.0_c_double, btn_y + 4.0_c_double)
    call cairo_line_to(cr, btn_x + 4.0_c_double, btn_y + btn_size - 4.0_c_double)
    call cairo_stroke(cr)
  end subroutine draw_close_button

  ! Draw plus button
  subroutine draw_plus_button(cr, x, y)
    type(c_ptr), intent(in) :: cr
    integer, intent(in) :: x, y
    real(c_double) :: btn_x, btn_y, btn_size
    logical :: is_hovered

    is_hovered = (hovered_tab == -1)

    btn_x = real(x, c_double) + 4.0_c_double
    btn_y = real(y, c_double) + 4.0_c_double
    btn_size = real(PLUS_BUTTON_WIDTH - 8, c_double)

    ! Draw circle background
    if (is_hovered) then
      call cairo_set_source_rgb(cr, 0.9_c_double, 0.9_c_double, 0.9_c_double)
    else
      call cairo_set_source_rgb(cr, 0.85_c_double, 0.85_c_double, 0.85_c_double)
    end if
    call cairo_arc(cr, btn_x + btn_size / 2.0_c_double, btn_y + btn_size / 2.0_c_double, &
                   btn_size / 2.0_c_double, 0.0_c_double, 6.28319_c_double)
    call cairo_fill(cr)

    ! Draw + symbol
    call cairo_set_line_width(cr, 2.0_c_double)
    call cairo_set_source_rgb(cr, 0.3_c_double, 0.3_c_double, 0.3_c_double)

    ! Horizontal line
    call cairo_move_to(cr, btn_x + 6.0_c_double, btn_y + btn_size / 2.0_c_double)
    call cairo_line_to(cr, btn_x + btn_size - 6.0_c_double, btn_y + btn_size / 2.0_c_double)
    call cairo_stroke(cr)

    ! Vertical line
    call cairo_move_to(cr, btn_x + btn_size / 2.0_c_double, btn_y + 6.0_c_double)
    call cairo_line_to(cr, btn_x + btn_size / 2.0_c_double, btn_y + btn_size - 6.0_c_double)
    call cairo_stroke(cr)
  end subroutine draw_plus_button

  ! Handle mouse motion for hover effects
  subroutine on_tab_motion(controller, x, y, user_data) bind(c)
    use tab_manager, only: num_tabs
    type(c_ptr), value :: controller, user_data
    real(c_double), value :: x, y
    integer :: i, old_hovered, old_hovered_close
    integer :: close_btn_x, close_btn_y, close_btn_right, close_btn_bottom

    old_hovered = hovered_tab
    old_hovered_close = hovered_close_button
    hovered_tab = 0
    hovered_close_button = 0

    ! Check plus button
    if (x >= plus_button_x .and. x < plus_button_x + PLUS_BUTTON_WIDTH .and. &
        y >= plus_button_y .and. y < plus_button_y + TAB_HEIGHT) then
      hovered_tab = -1
    else
      ! Check tabs
      do i = 1, num_tabs
        if (x >= tab_rects(i)%x .and. x < tab_rects(i)%x + tab_rects(i)%width .and. &
            y >= tab_rects(i)%y .and. y < tab_rects(i)%y + tab_rects(i)%height) then
          hovered_tab = i

          ! Check if mouse is over close button for this tab
          close_btn_x = tab_rects(i)%x + tab_rects(i)%width - CLOSE_BUTTON_SIZE - CLOSE_BUTTON_MARGIN
          close_btn_y = (TAB_HEIGHT - CLOSE_BUTTON_SIZE) / 2
          close_btn_right = close_btn_x + CLOSE_BUTTON_SIZE
          close_btn_bottom = close_btn_y + CLOSE_BUTTON_SIZE

          if (x >= close_btn_x .and. x < close_btn_right .and. &
              y >= close_btn_y .and. y < close_btn_bottom) then
            hovered_close_button = i
          end if

          exit
        end if
      end do
    end if

    ! Redraw if hover state changed
    if ((hovered_tab /= old_hovered .or. hovered_close_button /= old_hovered_close) .and. &
        c_associated(tab_bar_widget)) then
      call gtk_widget_queue_draw(tab_bar_widget)
    end if
  end subroutine on_tab_motion

  ! Handle mouse leave (clear hover state)
  subroutine on_tab_leave(controller, user_data) bind(c)
    type(c_ptr), value :: controller, user_data

    ! Clear hover state when mouse leaves the tab bar
    if (hovered_tab /= 0 .and. c_associated(tab_bar_widget)) then
      hovered_tab = 0
      hovered_close_button = 0
      call gtk_widget_queue_draw(tab_bar_widget)
    end if
  end subroutine on_tab_leave

  ! Handle clicks
  subroutine on_tab_click(gesture, n_press, x, y, user_data) bind(c)
    use tab_manager, only: num_tabs
    type(c_ptr), value :: gesture, user_data
    integer(c_int), value :: n_press
    real(c_double), value :: x, y
    integer :: i

    ! Check plus button
    if (x >= plus_button_x .and. x < plus_button_x + PLUS_BUTTON_WIDTH .and. &
        y >= plus_button_y .and. y < plus_button_y + TAB_HEIGHT) then
      if (associated(new_tab_cb)) call new_tab_cb()
      return
    end if

    ! Check tabs
    do i = 1, num_tabs
      if (x >= tab_rects(i)%x .and. x < tab_rects(i)%x + tab_rects(i)%width .and. &
          y >= tab_rects(i)%y .and. y < tab_rects(i)%y + tab_rects(i)%height) then

        ! Check if close button was clicked
        if (x >= tab_rects(i)%x + tab_rects(i)%width - CLOSE_BUTTON_SIZE - CLOSE_BUTTON_MARGIN .and. &
            x < tab_rects(i)%x + tab_rects(i)%width - CLOSE_BUTTON_MARGIN) then
          if (associated(close_cb)) call close_cb(i)
        else
          ! Tab body clicked
          if (associated(switch_cb)) call switch_cb(i)
        end if
        return
      end if
    end do
  end subroutine on_tab_click

  ! Refresh (trigger redraw)
  subroutine refresh_cairo_tab_bar()
    if (c_associated(tab_bar_widget)) then
      call gtk_widget_queue_draw(tab_bar_widget)
    end if
  end subroutine refresh_cairo_tab_bar

  ! Get widget
  function get_cairo_tab_bar_widget() result(widget)
    type(c_ptr) :: widget
    widget = tab_bar_widget
  end function get_cairo_tab_bar_widget

  ! Register callbacks
  subroutine register_cairo_tab_switch_callback(callback)
    procedure(tab_switch_callback) :: callback
    switch_cb => callback
  end subroutine register_cairo_tab_switch_callback

  subroutine register_cairo_tab_close_callback(callback)
    procedure(tab_close_callback) :: callback
    close_cb => callback
  end subroutine register_cairo_tab_close_callback

  subroutine register_cairo_new_tab_callback(callback)
    procedure(new_tab_callback) :: callback
    new_tab_cb => callback
  end subroutine register_cairo_new_tab_callback

end module cairo_tab_bar
