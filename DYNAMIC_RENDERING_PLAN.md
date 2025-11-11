# Dynamic Rendering Plan - SpaceSniffer-Style Progressive Scanning

## Goal
Implement real-time progressive rendering where treemap boxes grow, shrink, and reposition as directories are scanned, similar to SpaceSniffer's iconic behavior.

## Current State
- **Synchronous scanning**: Full directory tree is scanned before any rendering
- **Static layout**: Once rendered, boxes don't change size
- **Progress bar only**: User sees only a progress bar during scan, no visual feedback of structure

## Target Behavior (SpaceSniffer-like)
1. **Immediate rendering**: Start drawing boxes as soon as first directory is scanned
2. **Progressive updates**: Boxes dynamically resize as subdirectories are discovered
3. **Relative sizing**: Boxes continuously adjust relative to siblings as scan progresses
4. **Visual feedback**: User sees the file structure emerge in real-time
5. **Smooth experience**: No jarring jumps, boxes flow and adapt gracefully

## Technical Challenges

### 1. **Asynchronous Scanning**
- **Current**: Recursive `scan_directory()` blocks until complete
- **Needed**: Non-blocking scan that yields partial results
- **Options**:
  - Thread-based: Scan in background thread, communicate via shared state
  - Idle callback: Scan one directory per GTK idle iteration
  - Generator pattern: Yield after each directory scan

### 2. **Incremental Layout Updates**
- **Current**: `squarify_layout()` computes entire layout at once
- **Needed**: Re-layout on every size update
- **Performance**: Must be fast enough for 30-60 FPS during scan
- **Solution approaches**:
  - Cached layouts with partial invalidation
  - Incremental squarify (update only affected nodes)
  - Layout diffing to minimize recalculation

### 3. **Size Estimation**
- **Problem**: When scanning `/foo`, we don't know final size until all children scanned
- **SpaceSniffer approach**: Use "estimated" sizes that grow as scan progresses
- **Implementation**:
  - Track `scanned_size` vs `estimated_total_size` per node
  - Mark nodes as `scan_complete` flag
  - Use heuristics for estimation (e.g., average file size × file count estimate)

### 4. **Treemap Algorithm Modifications**
- **Standard squarify**: Assumes all sizes are final
- **Dynamic squarify**: Must handle changing sizes gracefully
- **Requirements**:
  - Stable positioning (boxes shouldn't jump around too much)
  - Smooth transitions (animate size changes)
  - Handle new children appearing mid-render

### 5. **Threading & GTK Integration**
- **GTK is not thread-safe**: All widget updates must be on main thread
- **Architecture**:
  ```
  Main Thread (GTK)              Background Thread (Scanner)
  ┌──────────────┐               ┌────────────────┐
  │ Render loop  │◄──Messages────│ scan_directory │
  │ (60 FPS)     │               │ (breadth-first)│
  │              │───Request────►│                │
  │ Layout calc  │               │ File I/O       │
  └──────────────┘               └────────────────┘
  ```

### 6. **State Synchronization**
- **Problem**: Scan thread modifies tree while render thread reads it
- **Solution options**:
  - Double buffering: Scan writes to buffer, swap atomically
  - Read-write locks: Readers don't block each other
  - Message passing: Scan sends deltas, render applies them

## Proposed Architecture

### Phase 1: Non-Blocking Scan (Idle Callback Approach)
**Simplest, no threading**

```fortran
module progressive_scanner
  type :: scan_state
    character(len=512) :: current_path
    integer :: depth
    type(file_node), pointer :: current_node
    logical :: complete
    ! Queue of directories to scan
    character(len=512), dimension(1000) :: pending_dirs
    integer :: queue_head, queue_tail
  end type scan_state

  type(scan_state), save :: scanner

contains

  ! Initialize scan
  subroutine start_progressive_scan(root_path)
    scanner%queue_head = 1
    scanner%queue_tail = 1
    scanner%pending_dirs(1) = root_path
    scanner%complete = .false.

    ! Register idle callback
    call g_idle_add(c_funloc(scan_one_directory), c_null_ptr)
  end subroutine

  ! Scan one directory per idle iteration
  function scan_one_directory(user_data) bind(c) result(continue)
    type(c_ptr), value :: user_data
    integer(c_int) :: continue

    if (scanner%queue_head > scanner%queue_tail) then
      scanner%complete = .true.
      continue = 0_c_int  ! Stop calling
      return
    end if

    ! Scan one directory
    call scan_single_directory(scanner%pending_dirs(scanner%queue_head))
    scanner%queue_head = scanner%queue_head + 1

    ! Request redraw
    call gtk_widget_queue_draw(widget_ptr)

    continue = 1_c_int  ! Keep calling
  end function

end module progressive_scanner
```

**Pros**:
- Simple, no threading complexity
- GTK-friendly
- Easy to debug

**Cons**:
- Slower than threaded (I/O blocks GUI)
- May feel sluggish on slow disks

### Phase 2: Background Thread Scan
**Better performance, more complex**

```fortran
module threaded_scanner
  use omp_lib

  type :: scan_message
    integer :: msg_type  ! 1=new_node, 2=update_size, 3=complete
    character(len=512) :: path
    integer(int64) :: size
    integer :: parent_id, node_id
  end type

  ! Thread-safe message queue
  type(scan_message), dimension(10000) :: message_queue
  integer :: queue_read_pos = 1, queue_write_pos = 1
  !$omp threadprivate(queue_read_pos, queue_write_pos)

contains

  subroutine start_background_scan(root_path)
    !$omp parallel
    !$omp single
    call scan_directory_async(root_path)
    !$omp end single
    !$omp end parallel

    ! Register timer to process messages on main thread
    call g_timeout_add(16_c_int, c_funloc(process_scan_messages), c_null_ptr)
  end subroutine

  recursive subroutine scan_directory_async(path)
    ! Scan directory, send messages for each discovery
    ! ...
    call send_message(NEW_NODE, path, size, parent_id)
    !$omp task
    call scan_directory_async(child_path)
    !$omp end task
  end subroutine

  function process_scan_messages(user_data) bind(c) result(continue)
    ! Process up to 100 messages per frame
    do i = 1, 100
      if (has_messages()) then
        call apply_message(read_message())
      end if
    end do
    call gtk_widget_queue_draw(widget_ptr)
    continue = 1_c_int
  end function

end module threaded_scanner
```

## Implementation Phases

### Phase 1: Foundation (1-2 days)
- [ ] Add `scan_complete` flag to `file_node` type
- [ ] Add `estimated_size` vs `actual_size` fields
- [ ] Modify `scan_directory` to be interruptible (return after N files)
- [ ] Create `scan_state` module to track progress

### Phase 2: Idle Callback Scanning (1 day)
- [ ] Implement breadth-first scan queue
- [ ] Add `g_idle_add` callback for progressive scanning
- [ ] Update sizes incrementally as scan progresses
- [ ] Trigger redraws after each directory

### Phase 3: Dynamic Layout (2-3 days)
- [ ] Cache last layout in tree nodes
- [ ] Implement layout diffing (detect what changed)
- [ ] Partial layout recalculation
- [ ] Smooth transitions (animate box movements)

### Phase 4: Performance Optimization (1-2 days)
- [ ] Throttle redraws (max 30 FPS)
- [ ] Batch size updates before layout
- [ ] Only re-layout visible nodes
- [ ] Add "scan paused" state for user interaction

### Phase 5: Threading (Optional, 2-3 days)
- [ ] Implement background thread scanner
- [ ] Message queue for thread communication
- [ ] Lock-free or minimal locking strategy
- [ ] Test on multi-core systems

## Visual Design Decisions

### 1. **Incomplete Nodes Visual Indicator**
- **Option A**: Pulsing border while scanning
- **Option B**: Different color saturation (dimmer until complete)
- **Option C**: Animated gradient sweep
- **Recommendation**: Subtle pulse + slightly dimmer

### 2. **Transition Animation**
- **Duration**: 100-200ms per size update
- **Easing**: Ease-out for natural feel
- **Method**: Linear interpolation in `render_node()`

### 3. **Performance Targets**
- **Min framerate**: 30 FPS during scan
- **Max layout time**: 16ms per frame (60 FPS budget)
- **Redraw throttle**: Every 3-5 directories scanned

## Edge Cases to Handle

1. **Permission denied**: Mark node as complete with error state
2. **Symlink loops**: Detect and skip
3. **Very deep trees**: Limit recursion depth
4. **Very wide directories**: Limit children per node (group small files)
5. **Rapid navigation**: Cancel in-progress scans
6. **Window resize during scan**: Re-layout without restarting scan

## Testing Strategy

1. **Unit tests**:
   - Scan queue push/pop
   - Message queue thread safety
   - Layout diffing algorithm

2. **Integration tests**:
   - Scan small directory (10 files)
   - Scan deep directory (10 levels)
   - Scan wide directory (1000 files)
   - Navigate during scan

3. **Performance tests**:
   - Measure framerate on large directory
   - Profile layout recalculation time
   - Memory leak detection

## Success Metrics

- ✅ Boxes appear within 100ms of starting scan
- ✅ Smooth animation (30+ FPS) throughout scan
- ✅ No visual artifacts or flickering
- ✅ User can interact (click, navigate) during scan
- ✅ Memory usage stays reasonable (< 500MB for typical home directory)

## Future Enhancements

- **Scan prioritization**: Scan visible areas first
- **Incremental updates**: Update only changed subtrees
- **Predictive scanning**: Prefetch likely navigation targets
- **Network filesystem awareness**: Adjust timeouts for slow disks
- **Cancellation**: Allow user to stop scan mid-progress

## References

- SpaceSniffer behavior analysis: https://www.youtube.com/watch?v=... (TBD)
- GTK idle callbacks: https://docs.gtk.org/glib/func.idle_add.html
- Fortran OpenMP: https://www.openmp.org/wp-content/uploads/openmp-4.5.pdf
