/// Deterministic multi-window cluster runtime for Flutter Desktop.
///
/// Treats multiple OS windows as a single logical application.
/// Dart owns all state; the native layer acts as a stateless executor
/// and event forwarder.
///
/// ```dart
/// import 'package:flutter_cluster_window/flutter_cluster_window.dart';
///
/// void main(List<String> args) {
///   ClusterApp.run(
///     args: args,
///     clusterId: 'ide',
///     surfaces: [
///       ClusterSurface(
///         id: 'editor',
///         role: SurfaceRole.primary,
///         size: Size(940, 700),
///         builder: () => EditorApp(),
///       ),
///       ClusterSurface(
///         id: 'sidebar',
///         role: SurfaceRole.panel,
///         size: Size(220, 700),
///         anchor: SurfaceAnchor.left(gap: 8),
///         builder: () => SidebarApp(),
///       ),
///     ],
///   );
/// }
/// ```
library;

// Bootstrap
export 'src/bootstrap/cluster_app.dart';
export 'src/bootstrap/cluster_surface.dart';

// Core
export 'src/cluster_controller.dart';
export 'src/core/cluster_state.dart';
export 'src/core/surface_state.dart';
export 'src/core/surface_role.dart';
export 'src/core/commands.dart';
export 'src/core/events.dart';
export 'src/core/drag_state.dart' show DragState, ClusterLock;
export 'src/core/command_bus.dart' show CommandBus, InvalidCommandException;

// Layout
export 'src/layout/layout_engine.dart';
export 'src/layout/surface_anchor.dart';

// Bridge
export 'src/bridge/native_bridge.dart';
export 'src/bridge/native_command.dart';

// Failure
export 'src/failure/failure_handler.dart' show FailureEvent, FailureHandler;

// Scheduler
export 'src/scheduler/scheduler.dart' show Scheduler, CommandPriority;

// Ordering
export 'src/ordering/event_sequencer.dart';

// Focus
export 'src/focus/focus_router.dart';

// Reconciliation
export 'src/reconciliation/reconciliation_engine.dart';

// Widgets
export 'src/widgets/cluster_widgets.dart';
