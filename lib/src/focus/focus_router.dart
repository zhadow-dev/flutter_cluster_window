import 'dart:async';

import '../core/cluster_state.dart';
import '../core/commands.dart';
import '../core/events.dart';

/// Manages focus across the cluster with debouncing.
///
/// Rules:
/// - Only one surface can be focused at a time.
/// - When any surface gains OS focus, the entire cluster activates.
/// - Dart is authoritative and overrides native focus conflicts.
/// - Focus changes are debounced (50 ms default) to prevent flickering
///   from rapid Alt+Tab sequences.
///
/// The router does not dispatch commands directly. It delivers ready
/// commands via [onFocusReady] for the caller to dispatch.
class FocusRouter {
  /// Debounce duration for focus changes.
  final Duration debounce;

  Timer? _debounceTimer;
  String? _pendingFocusSurfaceId;

  /// Called when a debounced focus command is ready to dispatch.
  void Function(FocusSurfaceCommand)? onFocusReady;

  FocusRouter({
    this.debounce = const Duration(milliseconds: 50),
    this.onFocusReady,
  });

  /// Handles a native focus event with debouncing.
  ///
  /// The actual [FocusSurfaceCommand] is delivered via [onFocusReady]
  /// after the debounce period elapses.
  void handleFocusEvent(WindowFocusedEvent event, ClusterState state) {
    final surfaceId = event.surfaceId;

    final surface = state.surfaces[surfaceId];
    if (surface == null || !surface.isAlive) return;
    if (state.activeSurfaceId == surfaceId) return;

    _pendingFocusSurfaceId = surfaceId;
    _debounceTimer?.cancel();

    _debounceTimer = Timer(debounce, () {
      final pending = _pendingFocusSurfaceId;
      if (pending != null) {
        onFocusReady?.call(FocusSurfaceCommand(surfaceId: pending));
        _pendingFocusSurfaceId = null;
      }
    });
  }

  /// Returns `true` if the cluster should activate because one of its
  /// surfaces received focus.
  bool shouldActivateCluster(WindowFocusedEvent event, ClusterState state) {
    return state.surfaces.containsKey(event.surfaceId);
  }

  /// Immediately resolves any pending focus (e.g. during cluster shutdown).
  void flushPending() {
    _debounceTimer?.cancel();
    final pending = _pendingFocusSurfaceId;
    if (pending != null) {
      onFocusReady?.call(FocusSurfaceCommand(surfaceId: pending));
      _pendingFocusSurfaceId = null;
    }
  }

  /// Cancels any pending focus change without dispatching.
  void cancel() {
    _debounceTimer?.cancel();
    _pendingFocusSurfaceId = null;
  }

  /// Releases resources held by the focus router.
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingFocusSurfaceId = null;
    onFocusReady = null;
  }
}
