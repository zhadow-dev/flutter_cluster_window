import 'cluster_state.dart';
import 'commands.dart';
import 'surface_state.dart';

/// Pure state reducer with no side effects, I/O, or async.
///
/// Applies: `oldState + command → newState` (with `version++`).
/// This is the **only** place where [ClusterState] is transformed.
class StateReducer {
  /// Reduces [cmd] against [state] and returns a new [ClusterState]
  /// with an incremented version.
  ClusterState reduce(ClusterState state, Command cmd) {
    final newState = switch (cmd) {
      MoveClusterCommand() => _moveCluster(state, cmd),
      MoveSurfaceCommand() => _moveSurface(state, cmd),
      SetModeCommand() => _setMode(state, cmd),
      CreateSurfaceCommand() => _createSurface(state, cmd),
      DestroySurfaceCommand() => _destroySurface(state, cmd),
      FocusSurfaceCommand() => _focusSurface(state, cmd),
      SetVisibilityCommand() => _setVisibility(state, cmd),
      AttachHandleCommand() => _attachHandle(state, cmd),
      EnterDegradedCommand() => _enterDegraded(state, cmd),
      SurfaceDestroyedCommand() => _surfaceDestroyed(state, cmd),
      AcceptNativePositionCommand() => _acceptNativePosition(state, cmd),
      StartClusterCommand() => _startCluster(state, cmd),
      TerminateClusterCommand() => _terminateCluster(state, cmd),
    };

    return newState.copyWith(version: state.version + 1);
  }

  ClusterState _moveCluster(ClusterState state, MoveClusterCommand cmd) {
    final updatedSurfaces = <String, SurfaceState>{};
    for (final entry in state.surfaces.entries) {
      final s = entry.value;
      if (s.isAlive && s.lifecycle.isOperational) {
        updatedSurfaces[entry.key] = s.copyWith(
          frame: s.frame.shift(cmd.delta),
        );
      } else {
        updatedSurfaces[entry.key] = s;
      }
    }

    return state.copyWith(
      surfaces: updatedSurfaces,
      bounds: state.bounds.shift(cmd.delta),
    );
  }

  ClusterState _moveSurface(ClusterState state, MoveSurfaceCommand cmd) {
    final surface = state.surfaces[cmd.surfaceId];
    if (surface == null) return state;

    return state.copyWith(
      surfaces: {
        ...state.surfaces,
        cmd.surfaceId: surface.copyWith(frame: cmd.frame),
      },
    );
  }

  ClusterState _setMode(ClusterState state, SetModeCommand cmd) {
    return state.copyWith(mode: cmd.mode);
  }

  ClusterState _createSurface(ClusterState state, CreateSurfaceCommand cmd) {
    final surface = SurfaceState(
      id: cmd.surfaceId,
      frame: cmd.frame,
      zIndex: cmd.zIndex,
      lifecycle: SurfaceLifecyclePhase.created,
    );

    return state.copyWith(
      surfaces: {...state.surfaces, cmd.surfaceId: surface},
    );
  }

  ClusterState _destroySurface(ClusterState state, DestroySurfaceCommand cmd) {
    final surface = state.surfaces[cmd.surfaceId];
    if (surface == null) return state;

    final updated = surface.copyWith(
      lifecycle: SurfaceLifecyclePhase.destroying,
      isAlive: false,
      focused: false,
    );

    final newActive =
        state.activeSurfaceId == cmd.surfaceId ? null : state.activeSurfaceId;

    return state.copyWith(
      surfaces: {...state.surfaces, cmd.surfaceId: updated},
      activeSurfaceId: () => newActive,
    );
  }

  ClusterState _focusSurface(ClusterState state, FocusSurfaceCommand cmd) {
    final target = state.surfaces[cmd.surfaceId];
    if (target == null || !target.isAlive) return state;

    final updatedSurfaces = <String, SurfaceState>{};
    for (final entry in state.surfaces.entries) {
      updatedSurfaces[entry.key] = entry.value.copyWith(
        focused: entry.key == cmd.surfaceId,
      );
    }

    return state.copyWith(
      surfaces: updatedSurfaces,
      activeSurfaceId: () => cmd.surfaceId,
    );
  }

  ClusterState _setVisibility(ClusterState state, SetVisibilityCommand cmd) {
    final surface = state.surfaces[cmd.surfaceId];
    if (surface == null) return state;

    final updated = surface.copyWith(visible: cmd.visible);

    SurfaceLifecyclePhase? newLifecycle;
    if (cmd.visible && surface.lifecycle == SurfaceLifecyclePhase.attached) {
      newLifecycle = SurfaceLifecyclePhase.visible;
    }

    return state.copyWith(
      surfaces: {
        ...state.surfaces,
        cmd.surfaceId: newLifecycle != null
            ? updated.copyWith(lifecycle: newLifecycle)
            : updated,
      },
    );
  }

  ClusterState _attachHandle(ClusterState state, AttachHandleCommand cmd) {
    final surface = state.surfaces[cmd.surfaceId];
    if (surface == null) return state;

    return state.copyWith(
      surfaces: {
        ...state.surfaces,
        cmd.surfaceId: surface.copyWith(
          nativeHandle: cmd.nativeHandle,
          lifecycle: SurfaceLifecyclePhase.attached,
        ),
      },
    );
  }

  ClusterState _enterDegraded(ClusterState state, EnterDegradedCommand cmd) {
    final surface = state.surfaces[cmd.lostSurfaceId];

    final updatedSurfaces = Map<String, SurfaceState>.from(state.surfaces);
    if (surface != null) {
      updatedSurfaces[cmd.lostSurfaceId] = surface.copyWith(
        isAlive: false,
        focused: false,
        lifecycle: SurfaceLifecyclePhase.destroyed,
      );
    }

    final newActive = state.activeSurfaceId == cmd.lostSurfaceId
        ? null
        : state.activeSurfaceId;

    return state.copyWith(
      surfaces: updatedSurfaces,
      mode: ClusterMode.degraded,
      lifecycle: ClusterLifecyclePhase.degraded,
      activeSurfaceId: () => newActive,
    );
  }

  ClusterState _surfaceDestroyed(
      ClusterState state, SurfaceDestroyedCommand cmd) {
    final surface = state.surfaces[cmd.surfaceId];
    if (surface == null) return state;

    return state.copyWith(
      surfaces: {
        ...state.surfaces,
        cmd.surfaceId: surface.copyWith(
          lifecycle: SurfaceLifecyclePhase.destroyed,
          isAlive: false,
        ),
      },
    );
  }

  ClusterState _acceptNativePosition(
      ClusterState state, AcceptNativePositionCommand cmd) {
    final surface = state.surfaces[cmd.surfaceId];
    if (surface == null) return state;

    return state.copyWith(
      surfaces: {
        ...state.surfaces,
        cmd.surfaceId: surface.copyWith(frame: cmd.nativeFrame),
      },
    );
  }

  ClusterState _startCluster(ClusterState state, StartClusterCommand cmd) {
    return state.copyWith(lifecycle: ClusterLifecyclePhase.running);
  }

  ClusterState _terminateCluster(
      ClusterState state, TerminateClusterCommand cmd) {
    return state.copyWith(lifecycle: ClusterLifecyclePhase.terminating);
  }
}
