import 'dart:async';
import 'dart:ui' show Offset, Rect;

import 'core/cluster_state.dart';
import 'core/command_bus.dart';
import 'core/commands.dart';
import 'core/drag_state.dart';
import 'core/events.dart';
import 'core/state_differ.dart';
import 'core/state_reducer.dart';
import 'bridge/native_bridge.dart';
import 'failure/failure_handler.dart';
import 'focus/focus_router.dart';
import 'layout/layout_engine.dart';
import 'ordering/event_sequencer.dart';
import 'reconciliation/reconciliation_engine.dart';
import 'scheduler/scheduler.dart';

/// The single public API for the cluster runtime.
///
/// Wires together all subsystems: [CommandBus], [StateReducer], [Scheduler],
/// [EventSequencer], [FocusRouter], [LayoutEngine], [ReconciliationEngine],
/// and [FailureHandler].
///
/// ```dart
/// final cluster = ClusterController(
///   clusterId: 'editor',
///   bridge: WindowsNativeBridge(),
/// );
///
/// await cluster.start();
/// await cluster.addSurface('main', frame: Rect.fromLTWH(100, 100, 800, 600));
///
/// cluster.move(Offset(10, 10));
/// cluster.onStateChanged.listen((state) { ... });
///
/// await cluster.close();
/// ```
class ClusterController {
  final String clusterId;
  final NativeBridge _bridge;

  late final StateReducer _reducer;
  late final Scheduler _scheduler;
  late final CommandBus _commandBus;
  late final StateDiffer _differ;

  late final EventSequencer _eventSequencer;
  late final FocusRouter _focusRouter;
  late final LayoutEngine _layoutEngine;
  late final ReconciliationEngine _reconciliationEngine;
  late final FailureHandler _failureHandler;

  late final DragState _dragState;
  late final ClusterLock _clusterLock;

  final String _primarySurfaceId;
  final Map<String, SurfaceOffset> _surfaceOffsets;

  StreamSubscription<NativeEvent>? _eventSub;
  bool _initialized = false;

  ClusterController({
    required this.clusterId,
    required NativeBridge bridge,
    String primarySurfaceId = 'main',
    Map<String, SurfaceOffset> surfaceOffsets = const {},
  })  : _bridge = bridge,
        _primarySurfaceId = primarySurfaceId,
        _surfaceOffsets = Map.from(surfaceOffsets) {
    _reducer = StateReducer();
    _differ = StateDiffer();
    _scheduler = Scheduler(_bridge);
    _commandBus = CommandBus(
      initialState: ClusterState(clusterId: clusterId),
      reducer: _reducer,
      scheduler: _scheduler,
      differ: _differ,
    );

    _eventSequencer = EventSequencer();
    _dragState = DragState();
    _clusterLock = ClusterLock();

    _focusRouter = FocusRouter(
      onFocusReady: (cmd) => _commandBus.dispatch(cmd),
    );

    _layoutEngine = LayoutEngine();

    _reconciliationEngine = ReconciliationEngine(
      dragState: _dragState,
      clusterLock: _clusterLock,
    );

    _failureHandler = FailureHandler();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Current cluster state (read-only).
  ClusterState get state => _commandBus.state;

  /// Stream of every state transition.
  Stream<ClusterState> get onStateChanged => _commandBus.stateStream;

  /// Stream of failure events.
  Stream<FailureEvent> get onFailure => _failureHandler.failures;

  /// Stream of validation errors.
  Stream<InvalidCommandException> get onError => _commandBus.errorStream;

  /// Stream of dispatched commands (useful for debugging and replay).
  Stream<Command> get onCommand => _commandBus.commandStream;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Initialises the native bridge, starts the scheduler tick loop, and
  /// transitions the cluster to [ClusterLifecyclePhase.running].
  Future<void> start() async {
    if (_initialized) return;

    await _bridge.initialize();
    _eventSub = _bridge.events.listen(_handleNativeEvent);
    _scheduler.start();
    _commandBus.dispatch(StartClusterCommand());
    _initialized = true;
  }

  /// Shuts down the cluster, destroys all surfaces, and releases resources.
  Future<void> close() async {
    if (!_initialized) return;

    _focusRouter.flushPending();
    _commandBus.dispatch(TerminateClusterCommand());

    for (final surface in state.aliveSurfaces.toList()) {
      _commandBus.dispatch(DestroySurfaceCommand(surfaceId: surface.id));
    }

    await _scheduler.flush();
    _scheduler.stop();
    _eventSub?.cancel();
    _eventSub = null;

    await _bridge.dispose();
    _focusRouter.dispose();
    _reconciliationEngine.dispose();
    _failureHandler.dispose();
    _commandBus.dispose();
    _scheduler.dispose();

    _initialized = false;
  }

  // ---------------------------------------------------------------------------
  // Cluster operations
  // ---------------------------------------------------------------------------

  /// Moves the entire cluster by [delta] pixels.
  void move(Offset delta) {
    _commandBus.dispatch(MoveClusterCommand(delta: delta));
  }

  /// Sets the cluster display mode (normal, fullscreen, compact, etc.).
  void setMode(ClusterMode mode) {
    _commandBus.dispatch(SetModeCommand(mode: mode));
  }

  // ---------------------------------------------------------------------------
  // Surface operations
  // ---------------------------------------------------------------------------

  /// Creates a new surface in Dart state and requests native window creation.
  ///
  /// The native handle is attached when a [WindowCreatedEvent] arrives.
  void addSurface(
    String id, {
    required Rect frame,
    int zIndex = 0,
  }) {
    _commandBus.dispatch(CreateSurfaceCommand(
      surfaceId: id,
      frame: frame,
      zIndex: zIndex,
    ));
  }

  /// Removes a surface from the cluster and destroys the native window.
  void removeSurface(String id) {
    _commandBus.dispatch(DestroySurfaceCommand(surfaceId: id));
  }

  /// Replaces the current layout offsets and recomputes all positions.
  void updateLayout(Map<String, SurfaceOffset> offsets) {
    _surfaceOffsets.clear();
    _surfaceOffsets.addAll(offsets);
    _recomputeLayout();
  }

  // ---------------------------------------------------------------------------
  // Event processing (native → Dart)
  // ---------------------------------------------------------------------------

  /// Entry point for all native-to-Dart communication.
  void _handleNativeEvent(NativeEvent event) {
    final orderedEvents = _eventSequencer.push(event);
    final forceFlushed = _eventSequencer.forceFlushIfNeeded();

    for (final e in [...orderedEvents, ...forceFlushed]) {
      _processOrderedEvent(e);
    }
  }

  /// Dispatches a single in-order event to the appropriate handler.
  void _processOrderedEvent(NativeEvent event) {
    switch (event) {
      case WindowCreatedEvent():
        _onWindowCreated(event);
      case WindowMovedEvent():
        _onWindowMoved(event);
      case WindowFocusedEvent():
        _onWindowFocused(event);
      case WindowLostEvent():
        _onWindowLost(event);
      case WindowDestroyedEvent():
        _onWindowDestroyed(event);
      case DragStartedEvent():
        _onDragStarted(event);
      case DragEndedEvent():
        _onDragEnded(event);
      case WindowResizedEvent():
        _onWindowResized(event);
    }
  }

  void _onWindowCreated(WindowCreatedEvent event) {
    _commandBus.dispatch(AttachHandleCommand(
      surfaceId: event.surfaceId,
      nativeHandle: event.nativeHandle,
    ));
    _commandBus.dispatch(SetVisibilityCommand(
      surfaceId: event.surfaceId,
      visible: true,
    ));
  }

  void _onWindowMoved(WindowMovedEvent event) {
    if (_dragState.isDraggingSurface(event.surfaceId)) {
      _commandBus.dispatch(AcceptNativePositionCommand(
        surfaceId: event.surfaceId,
        nativeFrame: event.actualFrame,
      ));
      _recomputeLayoutFromDrag(event.surfaceId, event.actualFrame);
    }
  }

  void _onWindowFocused(WindowFocusedEvent event) {
    _focusRouter.handleFocusEvent(event, state);
  }

  void _onWindowLost(WindowLostEvent event) {
    final cmd = _failureHandler.handleWindowLost(event);
    _commandBus.dispatch(cmd);
  }

  void _onWindowDestroyed(WindowDestroyedEvent event) {
    _commandBus.dispatch(SurfaceDestroyedCommand(surfaceId: event.surfaceId));
  }

  void _onWindowResized(WindowResizedEvent event) {
    if (_dragState.isDraggingSurface(event.surfaceId)) {
      _commandBus.dispatch(AcceptNativePositionCommand(
        surfaceId: event.surfaceId,
        nativeFrame: event.actualFrame,
      ));
    }
  }

  void _onDragStarted(DragStartedEvent event) {
    _dragState.startDrag(event.surfaceId);
    _clusterLock.lock();
  }

  void _onDragEnded(DragEndedEvent event) {
    _dragState.endDrag();
    _clusterLock.unlock();
    _reconciliationEngine.reconcile(state);
    _recomputeLayout();
  }

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  /// Recomputes positions for all non-primary surfaces based on the current
  /// primary surface position.
  void _recomputeLayout() {
    if (_surfaceOffsets.isEmpty) return;

    final layout = _layoutEngine.computeLayout(
      state: state,
      primarySurfaceId: _primarySurfaceId,
      offsets: _surfaceOffsets,
    );

    for (final entry in layout.entries) {
      final surface = state.surfaces[entry.key];
      if (surface != null && surface.frame != entry.value) {
        _commandBus.dispatch(MoveSurfaceCommand(
          surfaceId: entry.key,
          frame: entry.value,
        ));
      }
    }
  }

  /// Recomputes positions for non-dragged surfaces while the user is actively
  /// dragging the primary surface.
  void _recomputeLayoutFromDrag(String draggedSurfaceId, Rect newFrame) {
    if (_surfaceOffsets.isEmpty) return;
    if (draggedSurfaceId != _primarySurfaceId) return;

    final layout = _layoutEngine.computeLayout(
      state: state,
      primarySurfaceId: _primarySurfaceId,
      offsets: _surfaceOffsets,
    );

    for (final entry in layout.entries) {
      if (entry.key == draggedSurfaceId) continue;
      final surface = state.surfaces[entry.key];
      if (surface != null && surface.frame != entry.value) {
        _commandBus.dispatch(MoveSurfaceCommand(
          surfaceId: entry.key,
          frame: entry.value,
        ));
      }
    }
  }
}
