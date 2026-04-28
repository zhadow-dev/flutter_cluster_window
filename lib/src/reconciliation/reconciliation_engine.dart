import '../core/cluster_state.dart';
import '../core/drag_state.dart';

/// Strategy for resolving conflicts between Dart state and native reality.
enum ReconciliationMode {
  /// Dart wins — forces the native layer to match Dart state.
  /// Used for all programmatic operations.
  dartWins,

  /// Native wins — accepts the native position into Dart state.
  /// Used only during active user drag, and only for the dragged surface.
  nativeWins,
}

/// Ensures that Dart state and native window positions remain in sync.
///
/// Reconciliation is **suppressed** while [ClusterLock] is active (during
/// drag) to prevent jitter. After drag ends, a single reconciliation pass
/// runs to correct any accumulated drift.
///
/// Currently a stub — logs mismatches but does not auto-correct. A future
/// version will query native positions via the bridge and generate
/// correction commands.
class ReconciliationEngine {
  final DragState dragState;
  final ClusterLock clusterLock;

  ReconciliationEngine({
    required this.dragState,
    required this.clusterLock,
  });

  /// Returns the reconciliation mode for [surfaceId] based on the current
  /// drag state.
  ReconciliationMode modeForSurface(String surfaceId) {
    if (dragState.isDraggingSurface(surfaceId)) {
      return ReconciliationMode.nativeWins;
    }
    return ReconciliationMode.dartWins;
  }

  /// Runs a reconciliation pass against [state].
  ///
  /// No-op while the cluster lock is held.
  void reconcile(ClusterState state) {
    if (clusterLock.isLocked) return;
  }

  /// Releases resources.
  void dispose() {}
}
