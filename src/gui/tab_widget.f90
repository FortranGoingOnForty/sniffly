! Tab Widget Module for Sniffly
! Manages visual tab bar UI with tab buttons
module tab_widget
  use, intrinsic :: iso_c_binding
  use gtk, only: gtk_box_new, gtk_box_append, gtk_box_remove, &
                 GTK_ORIENTATION_HORIZONTAL, gtk_button_new, &
                 gtk_button_new_with_label, gtk_button_set_label, &
                 gtk_widget_set_size_request, g_signal_connect, &
                 gtk_widget_add_css_class, gtk_widget_remove_css_class, &
                 gtk_label_new, gtk_box_set_spacing, gtk_widget_set_hexpand, &
                 gtk_widget_set_halign, GTK_ALIGN_END
  use tab_manager, only: tab_state, get_tab, num_tabs, active_tab_index, &
                         MAX_TABS, switch_to_tab, create_tab, close_tab
  implicit none
  private

  public :: create_tab_bar, refresh_tab_bar, get_tab_bar_widget, update_tab_visual_states, &
            register_tab_switch_callback

  ! Tab bar container
  type(c_ptr), save :: tab_bar_container = c_null_ptr

  ! Track button pointers to determine which tab was clicked
  type(c_ptr), dimension(MAX_TABS), save :: tab_buttons = c_null_ptr

  ! Tab click callback interface
  abstract interface
    subroutine tab_click_callback(tab_index)
      integer, intent(in) :: tab_index
    end subroutine tab_click_callback
  end interface

  ! Close tab callback interface
  abstract interface
    subroutine close_tab_callback(tab_index)
      integer, intent(in) :: tab_index
    end subroutine close_tab_callback
  end interface

  ! New tab callback interface
  abstract interface
    subroutine new_tab_callback()
    end subroutine new_tab_callback
  end interface

  ! Tab switch callback interface (for UI updates)
  abstract interface
    subroutine tab_switch_callback()
    end subroutine tab_switch_callback
  end interface

  ! Registered callbacks
  procedure(tab_click_callback), pointer, save :: tab_click_cb => null()
  procedure(close_tab_callback), pointer, save :: close_tab_cb => null()
  procedure(new_tab_callback), pointer, save :: new_tab_cb => null()
  procedure(tab_switch_callback), pointer, save :: tab_switch_cb => null()

contains

  ! Create the tab bar (horizontal box with tab buttons)
  function create_tab_bar() result(tab_bar)
    type(c_ptr) :: tab_bar

    ! Create horizontal box for tabs (aligned to right)
    tab_bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 5_c_int)
    call gtk_widget_set_halign(tab_bar, GTK_ALIGN_END)
    call gtk_box_set_spacing(tab_bar, 5_c_int)

    ! Store reference
    tab_bar_container = tab_bar

    print *, "Tab bar container created"
  end function create_tab_bar

  ! Refresh tab bar (rebuild all tab buttons)
  subroutine refresh_tab_bar()
    type(c_ptr) :: plus_btn, tab_btn
    type(tab_state), pointer :: tab
    integer :: i
    character(len=256) :: label_text

    if (.not. c_associated(tab_bar_container)) then
      print *, "ERROR: Tab bar not initialized"
      return
    end if

    print *, "Refreshing tab bar with ", num_tabs, " tabs"

    ! TODO: Clear existing children (need gtk_widget_get_first_child and loop)
    ! For now, we'll just append - proper clearing will be added later

    ! Create plus button first (leftmost)
    plus_btn = gtk_button_new_with_label("+"//c_null_char)
    call gtk_widget_set_size_request(plus_btn, 30_c_int, 28_c_int)
    call g_signal_connect(plus_btn, "clicked"//c_null_char, &
                          c_funloc(on_plus_clicked), c_null_ptr)
    call gtk_box_append(tab_bar_container, plus_btn)

    ! Create tab buttons (one for each tab)
    do i = 1, num_tabs
      tab => get_tab(i)
      if (.not. associated(tab)) cycle

      ! Format label as ".../basename"
      label_text = ".../" // trim(tab%label)

      ! Create tab button
      tab_btn = gtk_button_new_with_label(trim(label_text)//c_null_char)
      call gtk_widget_set_size_request(tab_btn, 120_c_int, 28_c_int)

      ! Store button pointer so we can identify which tab was clicked
      tab_buttons(i) = tab_btn

      ! Add yellow border if active tab
      if (i == active_tab_index) then
        call gtk_widget_add_css_class(tab_btn, "active-tab"//c_null_char)
      end if

      ! Connect click handler
      call g_signal_connect(tab_btn, "clicked"//c_null_char, &
                            c_funloc(on_tab_clicked), c_null_ptr)

      call gtk_box_append(tab_bar_container, tab_btn)
      print *, "Added tab button ", i, ": ", trim(label_text)
    end do

    print *, "Tab bar refreshed"
  end subroutine refresh_tab_bar

  ! Get the tab bar widget pointer
  function get_tab_bar_widget() result(widget)
    type(c_ptr) :: widget
    widget = tab_bar_container
  end function get_tab_bar_widget

  ! Update visual states of tab buttons (yellow border for active tab)
  subroutine update_tab_visual_states()
    integer :: i

    ! Update CSS classes for all tab buttons
    do i = 1, num_tabs
      if (.not. c_associated(tab_buttons(i))) cycle

      ! Remove or add active-tab class based on whether this is the active tab
      if (i == active_tab_index) then
        call gtk_widget_add_css_class(tab_buttons(i), "active-tab"//c_null_char)
      else
        call gtk_widget_remove_css_class(tab_buttons(i), "active-tab"//c_null_char)
      end if
    end do

    print *, "Updated tab visual states - active tab: ", active_tab_index
  end subroutine update_tab_visual_states

  ! Callback when plus button is clicked
  subroutine on_plus_clicked(button, user_data) bind(c)
    use iso_fortran_env, only: output_unit
    type(c_ptr), value :: button, user_data
    integer :: new_tab_index
    type(tab_state), pointer :: new_tab, current_tab
    character(len=512) :: new_tab_path

    print *, "Plus button clicked - creating new tab"

    ! Get the current tab's path and use that for the new tab
    ! TODO: Add directory picker to let user choose path
    current_tab => get_tab(active_tab_index)
    if (associated(current_tab)) then
      new_tab_path = current_tab%scan_path
    else
      ! Fallback to home directory using environment variable
      call get_environment_variable("HOME", new_tab_path)
    end if

    ! Create a new tab with the same path as current tab
    new_tab_index = create_tab(trim(new_tab_path))

    if (new_tab_index < 0) then
      print *, "ERROR: Failed to create new tab (max tabs reached?)"
      return
    end if

    print *, "Created new tab ", new_tab_index

    ! Rebuild tab bar to show the new tab
    ! TODO: Implement proper clear_tab_bar to avoid duplicates
    ! For now, just refresh which will add the new tab
    call refresh_tab_bar()

    print *, "Tab bar refreshed with new tab"
  end subroutine on_plus_clicked

  ! Callback when a tab button is clicked
  subroutine on_tab_clicked(button, user_data) bind(c)
    type(c_ptr), value :: button, user_data
    integer :: i, clicked_tab_index

    ! Find which tab was clicked by comparing button pointers
    clicked_tab_index = -1
    do i = 1, num_tabs
      if (c_associated(tab_buttons(i), button)) then
        clicked_tab_index = i
        exit
      end if
    end do

    if (clicked_tab_index == -1) then
      print *, "WARNING: Could not determine which tab was clicked"
      return
    end if

    print *, "Tab ", clicked_tab_index, " clicked"

    ! If already on this tab, nothing to do
    if (clicked_tab_index == active_tab_index) then
      print *, "Already on tab ", clicked_tab_index
      return
    end if

    ! Switch to the clicked tab
    call switch_to_tab(clicked_tab_index)

    ! Update tab visual states (yellow border)
    call update_tab_visual_states()

    ! Call registered UI update callback (if registered)
    if (associated(tab_switch_cb)) then
      call tab_switch_cb()
    end if

    print *, "Switched to tab ", clicked_tab_index
  end subroutine on_tab_clicked

  ! Register tab click callback
  subroutine register_tab_click_callback(callback)
    procedure(tab_click_callback) :: callback
    tab_click_cb => callback
  end subroutine register_tab_click_callback

  ! Register close tab callback
  subroutine register_close_tab_callback(callback)
    procedure(close_tab_callback) :: callback
    close_tab_cb => callback
  end subroutine register_close_tab_callback

  ! Register new tab callback
  subroutine register_new_tab_callback(callback)
    procedure(new_tab_callback) :: callback
    new_tab_cb => callback
  end subroutine register_new_tab_callback

  ! Register tab switch callback (for UI updates)
  subroutine register_tab_switch_callback(callback)
    procedure(tab_switch_callback) :: callback
    tab_switch_cb => callback
    print *, "Tab switch callback registered"
  end subroutine register_tab_switch_callback

end module tab_widget
