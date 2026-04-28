import 'dart:ui' show Rect;

import 'surface_state.dart';

/// Operational mode of the cluster.
enum ClusterMode {
  /// Normal multi-window layout.
  normal,

  /// All surfaces merged into a single fullscreen window.
  fullscreen,

  /// Compact / minimised layout.
  compact,

  /// One or more surfaces lost; the system continues with the remainder.
  degraded,
}

/// Lifecycle phases for the entire cluster.
///
/// Valid transitions:
/// `init → running → degraded → terminating → terminated`
enum ClusterLifecyclePhase {
  init,
  running,
  degraded,
  terminating,
  terminated;

  /// Whether the cluster can accept operational commands.
  bool get isOperational => this == running || this == degraded;

  /// Whether the cluster has entered a terminal phase.
  bool get isDead => this == terminating || this == terminated;

  /// Phases that this phase may transition to.
  Set<ClusterLifecyclePhase> get validTransitions => switch (this) {
        init => {running, terminated},
        running => {degraded, terminating},
        degraded => {running, terminating},
        terminating => {terminated},
        terminated => {},
      };

  /// Returns `true` if transitioning to [next] is allowed.
  bool canTransitionTo(ClusterLifecyclePhase next) =>
      validTransitions.contains(next);
}

/// Immutable state of the entire window cluster.
///
/// The [CommandBus] holds exactly one instance. Every mutation produces a
/// new instance with an incremented [version].
class ClusterState {
  final String clusterId;
  final Map<String, SurfaceState> surfaces;
  final String? activeSurfaceId;
  final ClusterMode mode;
  final Rect bounds;
  final int version;
  final ClusterLifecyclePhase lifecycle;

  const ClusterState({
    required this.clusterId,
    this.surfaces = const {},
    this.activeSurfaceId,
    this.mode = ClusterMode.normal,
    this.bounds = Rect.zero,
    this.version = 0,
    this.lifecycle = ClusterLifecyclePhase.init,
  });

  /// The currently focused surface, or `null` if none.
  SurfaceState? get activeSurface =>
      activeSurfaceId != null ? surfaces[activeSurfaceId] : null;

  /// All surfaces that have not been destroyed.
  Iterable<SurfaceState> get aliveSurfaces =>
      surfaces.values.where((s) => s.isAlive);

  /// All surfaces that are currently visible.
  Iterable<SurfaceState> get visibleSurfaces =>
      surfaces.values.where((s) => s.visible);

  /// Creates a shallow copy with the specified fields replaced.
  ClusterState copyWith({
    String? clusterId,
    Map<String, SurfaceState>? surfaces,
    String? Function()? activeSurfaceId,
    ClusterMode? mode,
    Rect? bounds,
    int? version,
    ClusterLifecyclePhase? lifecycle,
  }) {
    return ClusterState(
      clusterId: clusterId ?? this.clusterId,
      surfaces: surfaces ?? this.surfaces,
      activeSurfaceId:
          activeSurfaceId != null ? activeSurfaceId() : this.activeSurfaceId,
      mode: mode ?? this.mode,
      bounds: bounds ?? this.bounds,
      version: version ?? this.version,
      lifecycle: lifecycle ?? this.lifecycle,
    );
  }

  /// Serialises this state to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'clusterId': clusterId,
        'surfaces': surfaces.map((k, v) => MapEntry(k, v.toJson())),
        'activeSurfaceId': activeSurfaceId,
        'mode': mode.name,
        'bounds': {
          'x': bounds.left,
          'y': bounds.top,
          'w': bounds.width,
          'h': bounds.height,
        },
        'version': version,
        'lifecycle': lifecycle.name,
      };

  /// Deserialises a [ClusterState] from a JSON-compatible map.
  factory ClusterState.fromJson(Map<String, dynamic> json) {
    final b = json['bounds'] as Map<String, dynamic>;
    final surfacesJson = json['surfaces'] as Map<String, dynamic>;
    return ClusterState(
      clusterId: json['clusterId'] as String,
      surfaces: surfacesJson.map(
        (k, v) => MapEntry(k, SurfaceState.fromJson(v as Map<String, dynamic>)),
      ),
      activeSurfaceId: json['activeSurfaceId'] as String?,
      mode: ClusterMode.values.byName(json['mode'] as String? ?? 'normal'),
      bounds: Rect.fromLTWH(
        (b['x'] as num).toDouble(),
        (b['y'] as num).toDouble(),
        (b['w'] as num).toDouble(),
        (b['h'] as num).toDouble(),
      ),
      version: json['version'] as int? ?? 0,
      lifecycle: ClusterLifecyclePhase.values.byName(
        json['lifecycle'] as String? ?? 'init',
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClusterState &&
          runtimeType == other.runtimeType &&
          clusterId == other.clusterId &&
          _mapsEqual(surfaces, other.surfaces) &&
          activeSurfaceId == other.activeSurfaceId &&
          mode == other.mode &&
          bounds == other.bounds &&
          version == other.version &&
          lifecycle == other.lifecycle;

  @override
  int get hashCode => Object.hash(
        clusterId,
        Object.hashAll(surfaces.entries),
        activeSurfaceId,
        mode,
        bounds,
        version,
        lifecycle,
      );

  @override
  String toString() =>
      'ClusterState(id: $clusterId, surfaces: ${surfaces.length}, '
      'active: $activeSurfaceId, mode: $mode, version: $version, '
      'lifecycle: $lifecycle)';

  static bool _mapsEqual(
    Map<String, SurfaceState> a,
    Map<String, SurfaceState> b,
  ) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}
