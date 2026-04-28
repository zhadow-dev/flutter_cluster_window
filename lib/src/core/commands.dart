import 'dart:ui' show Offset, Rect;

import 'cluster_state.dart';

/// Base class for all commands in the cluster system.
///
/// Every state mutation flows through a [Command] subclass. Each command
/// carries a [timestamp] for ordering and debugging.
sealed class Command {
  final DateTime timestamp;

  Command({DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  /// Serialises this command to a JSON-compatible map.
  Map<String, dynamic> toJson();
}

/// Moves the entire cluster by [delta] pixels, preserving relative positions.
class MoveClusterCommand extends Command {
  final Offset delta;

  MoveClusterCommand({required this.delta, super.timestamp});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'MOVE_CLUSTER',
        'delta': {'dx': delta.dx, 'dy': delta.dy},
        'timestamp': timestamp.microsecondsSinceEpoch,
      };

  @override
  String toString() => 'MoveClusterCommand(delta: $delta)';
}

/// Moves a single surface to an absolute [frame].
class MoveSurfaceCommand extends Command {
  final String surfaceId;
  final Rect frame;

  MoveSurfaceCommand({
    required this.surfaceId,
    required this.frame,
    super.timestamp,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'MOVE_SURFACE',
        'surfaceId': surfaceId,
        'frame': {
          'x': frame.left,
          'y': frame.top,
          'w': frame.width,
          'h': frame.height,
        },
        'timestamp': timestamp.microsecondsSinceEpoch,
      };

  @override
  String toString() => 'MoveSurfaceCommand(surface: $surfaceId, frame: $frame)';
}

/// Changes the cluster operational mode.
class SetModeCommand extends Command {
  final ClusterMode mode;

  SetModeCommand({required this.mode, super.timestamp});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'SET_MODE',
        'mode': mode.name,
        'timestamp': timestamp.microsecondsSinceEpoch,
      };

  @override
  String toString() => 'SetModeCommand(mode: $mode)';
}

/// Creates a new surface in the cluster.
class CreateSurfaceCommand extends Command {
  final String surfaceId;
  final Rect frame;
  final int zIndex;

  CreateSurfaceCommand({
    required this.surfaceId,
    required this.frame,
    this.zIndex = 0,
    super.timestamp,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'CREATE_SURFACE',
        'surfaceId': surfaceId,
        'frame': {
          'x': frame.left,
          'y': frame.top,
          'w': frame.width,
          'h': frame.height,
        },
        'zIndex': zIndex,
        'timestamp': timestamp.microsecondsSinceEpoch,
      };

  @override
  String toString() =>
      'CreateSurfaceCommand(surface: $surfaceId, frame: $frame)';
}

/// Initiates destruction of a surface (transitions lifecycle to `destroying`).
class DestroySurfaceCommand extends Command {
  final String surfaceId;

  DestroySurfaceCommand({required this.surfaceId, super.timestamp});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'DESTROY_SURFACE',
        'surfaceId': surfaceId,
        'timestamp': timestamp.microsecondsSinceEpoch,
      };

  @override
  String toString() => 'DestroySurfaceCommand(surface: $surfaceId)';
}

/// Sets focus to a specific surface. The entire cluster activates.
class FocusSurfaceCommand extends Command {
  final String surfaceId;

  FocusSurfaceCommand({required this.surfaceId, super.timestamp});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'FOCUS_SURFACE',
        'surfaceId': surfaceId,
        'timestamp': timestamp.microsecondsSinceEpoch,
      };

  @override
  String toString() => 'FocusSurfaceCommand(surface: $surfaceId)';
}

/// Sets the visibility of a surface.
class SetVisibilityCommand extends Command {
  final String surfaceId;
  final bool visible;

  SetVisibilityCommand({
    required this.surfaceId,
    required this.visible,
    super.timestamp,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'SET_VISIBILITY',
        'surfaceId': surfaceId,
        'visible': visible,
        'timestamp': timestamp.microsecondsSinceEpoch,
      };

  @override
  String toString() =>
      'SetVisibilityCommand(surface: $surfaceId, visible: $visible)';
}

/// Attaches a native window handle to a surface after creation.
class AttachHandleCommand extends Command {
  final String surfaceId;
  final int nativeHandle;

  AttachHandleCommand({
    required this.surfaceId,
    required this.nativeHandle,
    super.timestamp,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'ATTACH_HANDLE',
        'surfaceId': surfaceId,
        'nativeHandle': nativeHandle,
        'timestamp': timestamp.microsecondsSinceEpoch,
      };

  @override
  String toString() =>
      'AttachHandleCommand(surface: $surfaceId, handle: $nativeHandle)';
}

/// Enters degraded mode due to a lost surface.
class EnterDegradedCommand extends Command {
  final String lostSurfaceId;
  final String reason;

  EnterDegradedCommand({
    required this.lostSurfaceId,
    this.reason = 'unknown',
    super.timestamp,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'ENTER_DEGRADED',
        'lostSurfaceId': lostSurfaceId,
        'reason': reason,
        'timestamp': timestamp.microsecondsSinceEpoch,
      };

  @override
  String toString() =>
      'EnterDegradedCommand(lost: $lostSurfaceId, reason: $reason)';
}

/// Marks a surface as fully destroyed (final lifecycle transition).
class SurfaceDestroyedCommand extends Command {
  final String surfaceId;

  SurfaceDestroyedCommand({required this.surfaceId, super.timestamp});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'SURFACE_DESTROYED',
        'surfaceId': surfaceId,
        'timestamp': timestamp.microsecondsSinceEpoch,
      };

  @override
  String toString() => 'SurfaceDestroyedCommand(surface: $surfaceId)';
}

/// Accepts a native window position into Dart state during user drag.
class AcceptNativePositionCommand extends Command {
  final String surfaceId;
  final Rect nativeFrame;

  AcceptNativePositionCommand({
    required this.surfaceId,
    required this.nativeFrame,
    super.timestamp,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'ACCEPT_NATIVE_POSITION',
        'surfaceId': surfaceId,
        'frame': {
          'x': nativeFrame.left,
          'y': nativeFrame.top,
          'w': nativeFrame.width,
          'h': nativeFrame.height,
        },
        'timestamp': timestamp.microsecondsSinceEpoch,
      };

  @override
  String toString() =>
      'AcceptNativePositionCommand(surface: $surfaceId, frame: $nativeFrame)';
}

/// Starts the cluster lifecycle (`init → running`).
class StartClusterCommand extends Command {
  StartClusterCommand({super.timestamp});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'START_CLUSTER',
        'timestamp': timestamp.microsecondsSinceEpoch,
      };

  @override
  String toString() => 'StartClusterCommand()';
}

/// Terminates the cluster (`→ terminating`).
class TerminateClusterCommand extends Command {
  TerminateClusterCommand({super.timestamp});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'TERMINATE_CLUSTER',
        'timestamp': timestamp.microsecondsSinceEpoch,
      };

  @override
  String toString() => 'TerminateClusterCommand()';
}
