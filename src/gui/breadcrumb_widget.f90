! Custom Cairo Breadcrumb Widget for Sniffly
! Renders path as clickable, color-coded text segments with hover effects
module breadcrumb_widget
  use, intrinsic :: iso_c_binding
  use gtk, only: gtk_drawing_area_new, gtk_drawing_area_set_draw_func, &
                 gtk_widget_set_size_request, gtk_event_controller_motion_new, &
                 gtk_widget_add_controller, g_signal_connect, &
                 gtk_gesture_click_new, gtk_widget_queue_draw
  use cairo, only: cairo_set_source_rgb, cairo_set_source_rgba, cairo_move_to
  use pango, only: pango_cairo_create_layout, pango_layout_set_text, &
                   pango_font_description_from_string, pango_layout_set_font_description, &
                   pango_cairo_show_layout, pango_layout_get_pixel_size, &
                   pango_font_description_free
  implicit none
  private

  public :: create_breadcrumb_widget, update_breadcrumb_cache, &
            set_navigation_callback, get_breadcrumb_widget_ptr

  ! Callback interface for navigation events
  abstract interface
    subroutine navigation_callback()
    end subroutine navigation_callback
  end interface

  ! Segment bounds for hit-testing
  type :: segment_bounds
    integer(c_int) :: x, y, width, height
  end type segment_bounds

  ! Maximum number of path segments
  integer, parameter :: MAX_SEGMENTS = 50

  ! Path segment cache (updated on main thread only via update_breadcrumb_cache)
  character(len=512), dimension(MAX_SEGMENTS), save :: cached_segment_paths = ""
  character(len=256), dimension(MAX_SEGMENTS), save :: cached_segment_names = ""
  integer, save :: cached_segment_count = 0

  ! Hover state
  integer, save :: hovered_segment = 0  ! 0 = none, 1+ = segment index
  integer, save :: last_hovered_segment = -1

  ! Click bounds for each segment (populated during draw)
  type(segment_bounds), dimension(MAX_SEGMENTS), save :: segment_rects

  ! Widget pointer
  type(c_ptr), save :: breadcrumb_widget_ptr = c_null_ptr

  ! Navigation callback (called when user clicks a segment)
  procedure(navigation_callback), pointer, save :: nav_callback => null()

contains

  ! Create and initialize the breadcrumb drawing area widget
  function create_breadcrumb_widget() result(widget)
    type(c_ptr) :: widget, motion_controller, click_controller

    ! Create drawing area
    widget = gtk_drawing_area_new()
    breadcrumb_widget_ptr = widget

    if (.not. c_associated(widget)) then
      print *, "ERROR: Failed to create breadcrumb drawing area"
      return
    end if

    ! Set minimum height (width will expand to fill)
    call gtk_widget_set_size_request(widget, -1_c_int, 30_c_int)

    ! Set draw function (called when widget needs to redraw)
    call gtk_drawing_area_set_draw_func(widget, &
                                        c_funloc(on_draw_breadcrumb), &
                                        c_null_ptr, &
                                        c_null_funptr)

    ! Add motion event controller for hover
    motion_controller = gtk_event_controller_motion_new()
    call g_signal_connect(motion_controller, "motion"//c_null_char, &
                           c_funloc(on_breadcrumb_motion), c_null_ptr)
    call gtk_widget_add_controller(widget, motion_controller)

    ! Add click gesture controller for navigation
    click_controller = gtk_gesture_click_new()
    call g_signal_connect(click_controller, "pressed"//c_null_char, &
                           c_funloc(on_breadcrumb_click), c_null_ptr)
    call gtk_widget_add_controller(widget, click_controller)

    print *, "Breadcrumb widget created successfully"
  end function create_breadcrumb_widget

  ! Get widget pointer (for external access)
  function get_breadcrumb_widget_ptr() result(ptr)
    type(c_ptr) :: ptr
    ptr = breadcrumb_widget_ptr
  end function get_breadcrumb_widget_ptr

  ! Register a callback to be called when navigation occurs
  subroutine set_navigation_callback(callback)
    procedure(navigation_callback) :: callback
    nav_callback => callback
    print *, "Breadcrumb navigation callback registered"
  end subroutine set_navigation_callback

  ! Update cached path segments (called from main thread on navigation events)
  ! This is the ONLY function that modifies cached_segment_*
  subroutine update_breadcrumb_cache(full_path)
    character(len=*), intent(in) :: full_path
    character(len=512) :: home_dir, working_path
    integer :: i, slash_pos, start_pos, home_len
    logical :: uses_tilde

    print *, "Updating breadcrumb cache for: ", trim(full_path)

    ! Reset cache
    cached_segment_count = 0
    cached_segment_paths = ""
    cached_segment_names = ""

    if (len_trim(full_path) == 0) return

    ! Get home directory for ~ abbreviation
    call get_environment_variable("HOME", home_dir)
    home_len = len_trim(home_dir)

    ! Check if path starts with home directory
    working_path = trim(full_path)
    uses_tilde = .false.
    if (home_len > 0) then
      if (len_trim(full_path) >= home_len) then
        if (full_path(1:home_len) == home_dir(1:home_len)) then
          ! Replace home with ~
          if (len_trim(full_path) == home_len) then
            working_path = "~"
          else if (full_path(home_len+1:home_len+1) == "/") then
            working_path = "~" // trim(full_path(home_len+1:))
          end if
          uses_tilde = .true.
        end if
      end if
    end if

    ! Handle root path
    if (trim(working_path) == "/") then
      cached_segment_count = 1
      cached_segment_paths(1) = "/"
      cached_segment_names(1) = "/"
      print *, "  Segment 1: / -> /"
      call queue_redraw()
      return
    end if

    ! Handle home-only path
    if (trim(working_path) == "~") then
      cached_segment_count = 1
      cached_segment_paths(1) = trim(full_path)  ! Store actual path for navigation
      cached_segment_names(1) = "~"
      print *, "  Segment 1: ", trim(full_path), " -> ~"
      call queue_redraw()
      return
    end if

    ! Parse path into segments
    start_pos = 1

    ! Skip leading / or ~
    if (working_path(1:1) == "/" .or. working_path(1:1) == "~") then
      start_pos = 2
      ! Add root segment
      cached_segment_count = 1
      if (uses_tilde) then
        cached_segment_paths(1) = trim(home_dir)
        cached_segment_names(1) = "~"
      else
        cached_segment_paths(1) = "/"
        cached_segment_names(1) = "/"
      end if
      print *, "  Segment 1: ", trim(cached_segment_paths(1)), " -> ", trim(cached_segment_names(1))
    end if

    ! Parse remaining segments
    do while (start_pos <= len_trim(working_path) .and. cached_segment_count < MAX_SEGMENTS)
      ! Skip any leading slashes
      do while (start_pos <= len_trim(working_path) .and. working_path(start_pos:start_pos) == "/")
        start_pos = start_pos + 1
      end do

      ! Check if we've reached the end
      if (start_pos > len_trim(working_path)) exit

      ! Find next slash
      slash_pos = index(working_path(start_pos:), "/")

      if (slash_pos == 0) then
        ! Last segment (no trailing slash)
        cached_segment_count = cached_segment_count + 1
        ! Build full path for this segment
        if (uses_tilde) then
          cached_segment_paths(cached_segment_count) = trim(home_dir) // &
                                                        trim(working_path(2:len_trim(working_path)))
        else
          cached_segment_paths(cached_segment_count) = trim(working_path)
        end if
        ! Extract just the name
        cached_segment_names(cached_segment_count) = trim(working_path(start_pos:))
        print *, "  Segment ", cached_segment_count, ": ", &
                 trim(cached_segment_paths(cached_segment_count)), " -> ", &
                 trim(cached_segment_names(cached_segment_count))
        exit
      else
        ! Intermediate segment
        cached_segment_count = cached_segment_count + 1
        ! Build full path up to this segment
        if (uses_tilde) then
          cached_segment_paths(cached_segment_count) = trim(home_dir) // &
                                                        trim(working_path(2:start_pos+slash_pos-2))
        else
          cached_segment_paths(cached_segment_count) = trim(working_path(1:start_pos+slash_pos-2))
        end if
        ! Extract just the name
        cached_segment_names(cached_segment_count) = trim(working_path(start_pos:start_pos+slash_pos-2))
        print *, "  Segment ", cached_segment_count, ": ", &
                 trim(cached_segment_paths(cached_segment_count)), " -> ", &
                 trim(cached_segment_names(cached_segment_count))
        start_pos = start_pos + slash_pos
      end if
    end do

    print *, "Breadcrumb cache updated: ", cached_segment_count, " segments"

    ! Trigger redraw
    call queue_redraw()
  end subroutine update_breadcrumb_cache

  ! Helper: Queue redraw of widget
  subroutine queue_redraw()
    if (c_associated(breadcrumb_widget_ptr)) then
      call gtk_widget_queue_draw(breadcrumb_widget_ptr)
    end if
  end subroutine queue_redraw

  ! Draw callback - render the breadcrumb
  subroutine on_draw_breadcrumb(area, cr, width, height, user_data) bind(c)
    type(c_ptr), value :: area, cr, user_data
    integer(c_int), value :: width, height
    type(c_ptr) :: layout, font_desc
    integer(c_int), target :: text_width, text_height
    integer(c_int) :: x_offset
    integer :: i
    character(len=:), allocatable :: separator

    ! Early return if no segments
    if (cached_segment_count == 0) return

    ! Create Pango layout for text rendering
    layout = pango_cairo_create_layout(cr)
    if (.not. c_associated(layout)) then
      print *, "ERROR: Failed to create Pango layout"
      return
    end if

    separator = " / "
    x_offset = 5  ! Left padding

    ! Draw each segment
    do i = 1, cached_segment_count
      ! Set font and color based on segment state

      ! Root segment (first): green
      if (i == 1) then
        call cairo_set_source_rgb(cr, 0.0_c_double, 0.6_c_double, 0.0_c_double)
        font_desc = pango_font_description_from_string("Sans 11"//c_null_char)

      ! Active segment (last): bold red
      else if (i == cached_segment_count) then
        call cairo_set_source_rgb(cr, 0.8_c_double, 0.0_c_double, 0.0_c_double)
        font_desc = pango_font_description_from_string("Sans Bold 11"//c_null_char)

      ! Hovered segment: darker gray
      else if (i == hovered_segment) then
        call cairo_set_source_rgb(cr, 0.3_c_double, 0.3_c_double, 0.3_c_double)
        font_desc = pango_font_description_from_string("Sans 11"//c_null_char)

      ! Inactive segment: gray
      else
        call cairo_set_source_rgb(cr, 0.5_c_double, 0.5_c_double, 0.5_c_double)
        font_desc = pango_font_description_from_string("Sans 11"//c_null_char)
      end if

      ! Set font
      call pango_layout_set_font_description(layout, font_desc)
      call pango_font_description_free(font_desc)

      ! Set text
      call pango_layout_set_text(layout, trim(cached_segment_names(i))//c_null_char, &
                                  int(len_trim(cached_segment_names(i)), c_int))

      ! Get text size
      call pango_layout_get_pixel_size(layout, c_loc(text_width), c_loc(text_height))

      ! Store bounds for hit-testing
      segment_rects(i)%x = x_offset
      segment_rects(i)%y = 0
      segment_rects(i)%width = text_width
      segment_rects(i)%height = height

      ! Position and draw text
      call cairo_move_to(cr, real(x_offset, c_double), &
                         real((height - text_height) / 2, c_double))  ! Vertically center
      call pango_cairo_show_layout(cr, layout)

      ! Update offset
      x_offset = x_offset + text_width

      ! Draw separator (if not last segment)
      if (i < cached_segment_count) then
        ! Set separator color (gray)
        call cairo_set_source_rgb(cr, 0.5_c_double, 0.5_c_double, 0.5_c_double)
        font_desc = pango_font_description_from_string("Sans 11"//c_null_char)
        call pango_layout_set_font_description(layout, font_desc)
        call pango_font_description_free(font_desc)

        call pango_layout_set_text(layout, trim(separator)//c_null_char, &
                                    int(len_trim(separator), c_int))
        call pango_layout_get_pixel_size(layout, c_loc(text_width), c_loc(text_height))
        call cairo_move_to(cr, real(x_offset, c_double), &
                           real((height - text_height) / 2, c_double))
        call pango_cairo_show_layout(cr, layout)

        x_offset = x_offset + text_width
      end if
    end do

    ! Clean up (Pango layout is freed by GTK automatically)
  end subroutine on_draw_breadcrumb

  ! Motion callback - track hover state
  subroutine on_breadcrumb_motion(controller, x, y, user_data) bind(c)
    type(c_ptr), value :: controller, user_data
    real(c_double), value :: x, y
    integer :: new_hovered

    ! Find which segment is under the mouse
    new_hovered = find_segment_at_position(x, y)

    ! Only redraw if hover state CHANGED (optimization)
    if (new_hovered /= last_hovered_segment) then
      last_hovered_segment = new_hovered
      hovered_segment = new_hovered
      call queue_redraw()
    end if
  end subroutine on_breadcrumb_motion

  ! Click callback - handle navigation
  subroutine on_breadcrumb_click(gesture, n_press, x, y, user_data) bind(c)
    use treemap_renderer, only: get_current_view_node, scan_directory
    use types, only: file_node
    type(c_ptr), value :: gesture, user_data
    integer(c_int), value :: n_press
    real(c_double), value :: x, y
    integer :: clicked_segment
    type(file_node), pointer :: current_view
    character(len=:), allocatable :: target_path

    ! Find which segment was clicked
    clicked_segment = find_segment_at_position(x, y)

    if (clicked_segment > 0 .and. clicked_segment <= cached_segment_count) then
      ! Don't navigate if clicking the active (last) segment
      if (clicked_segment == cached_segment_count) then
        print *, "Clicked active segment - no navigation"
        return
      end if

      print *, "Breadcrumb clicked: segment ", clicked_segment, " (", &
               trim(cached_segment_names(clicked_segment)), ")"

      ! Get the full path for this segment
      target_path = trim(cached_segment_paths(clicked_segment))
      print *, "Navigating to: ", target_path

      ! Scan the target directory
      ! This will update the current view and trigger callbacks
      call scan_directory(target_path)

      ! Call navigation callback to update UI
      if (associated(nav_callback)) then
        call nav_callback()
      end if

      ! Redraw
      call queue_redraw()
    end if
  end subroutine on_breadcrumb_click

  ! Helper: Find which segment is at given position
  function find_segment_at_position(x, y) result(segment_index)
    real(c_double), intent(in) :: x, y
    integer :: segment_index
    integer :: i

    segment_index = 0
    do i = 1, cached_segment_count
      if (x >= segment_rects(i)%x .and. &
          x <= segment_rects(i)%x + segment_rects(i)%width .and. &
          y >= segment_rects(i)%y .and. &
          y <= segment_rects(i)%y + segment_rects(i)%height) then
        segment_index = i
        return
      end if
    end do
  end function find_segment_at_position

end module breadcrumb_widget
