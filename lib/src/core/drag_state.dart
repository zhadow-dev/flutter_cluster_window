/// Tracks whether a surface is being dragged by the user.
///
/// During an active drag, the native layer's position is accepted as truth
/// for the dragged surface while Dart remains authoritative for all others.
class DragState {
  bool isDragging;
  String? surfaceId;

  DragState({this.isDragging = false, this.surfaceId});

  /// Begins a drag operation on [surface].
  void startDrag(String surface) {
    isDragging = true;
    surfaceId = surface;
  }

  /// Ends the current drag operation.
  void endDrag() {
    isDragging = false;
    surfaceId = null;
  }

  /// Returns `true` if [id] is the surface currently being dragged.
  bool isDraggingSurface(String id) => isDragging && surfaceId == id;

  @override
  String toString() =>
      'DragState(isDragging: $isDragging, surface: $surfaceId)';
}

/// Atomic lock that suppresses reconciliation during cluster-wide moves.
///
/// While locked, reconciliation corrections are suppressed to prevent jitter.
/// A single reconciliation pass runs when the lock is released.
class ClusterLock {
  bool isLocked = false;

  void lock() => isLocked = true;
  void unlock() => isLocked = false;

  @override
  String toString() => 'ClusterLock(locked: $isLocked)';
}
