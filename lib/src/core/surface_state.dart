import 'dart:ui' show Rect;

/// Lifecycle phases for an individual surface (OS window).
///
/// Transitions are strictly ordered:
/// `created → attached → visible → active → destroying → destroyed`
enum SurfaceLifecyclePhase {
  created,
  attached,
  visible,
  active,
  destroying,
  destroyed;

  /// Whether this phase allows operational commands (move, resize, focus).
  bool get isOperational =>
      this == attached || this == visible || this == active;

  /// Whether this surface is considered dead.
  bool get isDead => this == destroying || this == destroyed;

  /// Phases that this phase may transition to.
  Set<SurfaceLifecyclePhase> get validTransitions => switch (this) {
        created => {attached, destroyed},
        attached => {visible, destroying},
        visible => {active, destroying},
        active => {visible, destroying},
        destroying => {destroyed},
        destroyed => {},
      };

  /// Returns `true` if transitioning to [next] is allowed.
  bool canTransitionTo(SurfaceLifecyclePhase next) =>
      validTransitions.contains(next);
}

/// Immutable state of a single surface (OS window) in the cluster.
///
/// This is the single source of truth for a window's position, visibility,
/// focus, and lifecycle. The native layer must match this state; any
/// divergence is corrected by the reconciliation engine.
class SurfaceState {
  final String id;
  final Rect frame;
  final bool visible;
  final bool focused;
  final bool isAlive;
  final int zIndex;
  final int version;
  final SurfaceLifecyclePhase lifecycle;

  /// Native window handle, managed by Dart and passed to native per-command.
  final int? nativeHandle;

  const SurfaceState({
    required this.id,
    required this.frame,
    this.visible = false,
    this.focused = false,
    this.isAlive = true,
    this.zIndex = 0,
    this.version = 0,
    this.lifecycle = SurfaceLifecyclePhase.created,
    this.nativeHandle,
  });

  /// Creates a shallow copy with the specified fields replaced.
  SurfaceState copyWith({
    String? id,
    Rect? frame,
    bool? visible,
    bool? focused,
    bool? isAlive,
    int? zIndex,
    int? version,
    SurfaceLifecyclePhase? lifecycle,
    int? nativeHandle,
  }) {
    return SurfaceState(
      id: id ?? this.id,
      frame: frame ?? this.frame,
      visible: visible ?? this.visible,
      focused: focused ?? this.focused,
      isAlive: isAlive ?? this.isAlive,
      zIndex: zIndex ?? this.zIndex,
      version: version ?? this.version,
      lifecycle: lifecycle ?? this.lifecycle,
      nativeHandle: nativeHandle ?? this.nativeHandle,
    );
  }

  /// Serialises this state to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'frame': {
          'x': frame.left,
          'y': frame.top,
          'w': frame.width,
          'h': frame.height,
        },
        'visible': visible,
        'focused': focused,
        'isAlive': isAlive,
        'zIndex': zIndex,
        'version': version,
        'lifecycle': lifecycle.name,
        'nativeHandle': nativeHandle,
      };

  /// Deserialises a [SurfaceState] from a JSON-compatible map.
  factory SurfaceState.fromJson(Map<String, dynamic> json) {
    final f = json['frame'] as Map<String, dynamic>;
    return SurfaceState(
      id: json['id'] as String,
      frame: Rect.fromLTWH(
        (f['x'] as num).toDouble(),
        (f['y'] as num).toDouble(),
        (f['w'] as num).toDouble(),
        (f['h'] as num).toDouble(),
      ),
      visible: json['visible'] as bool? ?? false,
      focused: json['focused'] as bool? ?? false,
      isAlive: json['isAlive'] as bool? ?? true,
      zIndex: json['zIndex'] as int? ?? 0,
      version: json['version'] as int? ?? 0,
      lifecycle: SurfaceLifecyclePhase.values.byName(
        json['lifecycle'] as String? ?? 'created',
      ),
      nativeHandle: json['nativeHandle'] as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SurfaceState &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          frame == other.frame &&
          visible == other.visible &&
          focused == other.focused &&
          isAlive == other.isAlive &&
          zIndex == other.zIndex &&
          version == other.version &&
          lifecycle == other.lifecycle &&
          nativeHandle == other.nativeHandle;

  @override
  int get hashCode => Object.hash(
        id,
        frame,
        visible,
        focused,
        isAlive,
        zIndex,
        version,
        lifecycle,
        nativeHandle,
      );

  @override
  String toString() =>
      'SurfaceState(id: $id, frame: $frame, visible: $visible, '
      'focused: $focused, isAlive: $isAlive, zIndex: $zIndex, '
      'version: $version, lifecycle: $lifecycle, handle: $nativeHandle)';
}
