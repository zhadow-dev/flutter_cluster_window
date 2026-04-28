import '../core/cluster_state.dart';
import '../core/surface_state.dart';
import '../bridge/native_command.dart';

/// Computes the minimal set of native commands required to transition
/// from [oldState] to [newState].
///
/// Only emits commands for properties that actually changed. Never sends
/// a full-layout refresh, which is critical for performance during drag.
class StateDiffer {
  /// Diffs two [ClusterState] snapshots and returns the minimal command set.
  List<NativeCommand> diff(ClusterState oldState, ClusterState newState) {
    final commands = <NativeCommand>[];

    for (final entry in newState.surfaces.entries) {
      final id = entry.key;
      final newSurface = entry.value;
      final oldSurface = oldState.surfaces[id];

      if (oldSurface == null) {
        // New surface — emit a creation command.
        if (newSurface.lifecycle.isOperational || 
            newSurface.lifecycle == SurfaceLifecyclePhase.created) {
          commands.add(NativeCommand.create(
            surfaceId: id,
            frame: newSurface.frame,
            version: newState.version,
          ));
        }
        continue;
      }

      // Position or size changed.
      if (oldSurface.frame != newSurface.frame &&
          newSurface.nativeHandle != null) {
        commands.add(NativeCommand.move(
          surfaceId: id,
          handle: newSurface.nativeHandle!,
          frame: newSurface.frame,
          version: newState.version,
        ));
      }

      // Visibility changed.
      if (oldSurface.visible != newSurface.visible &&
          newSurface.nativeHandle != null) {
        if (newSurface.visible) {
          commands.add(NativeCommand.show(
            surfaceId: id,
            handle: newSurface.nativeHandle!,
            version: newState.version,
          ));
        } else {
          commands.add(NativeCommand.hide(
            surfaceId: id,
            handle: newSurface.nativeHandle!,
            version: newState.version,
          ));
        }
      }

      // Focus gained.
      if (!oldSurface.focused &&
          newSurface.focused &&
          newSurface.nativeHandle != null) {
        commands.add(NativeCommand.focus(
          surfaceId: id,
          handle: newSurface.nativeHandle!,
          version: newState.version,
        ));
      }

      // Lifecycle transitioned to destroying.
      if (!oldSurface.lifecycle.isDead &&
          newSurface.lifecycle == SurfaceLifecyclePhase.destroying &&
          newSurface.nativeHandle != null) {
        commands.add(NativeCommand.destroy(
          surfaceId: id,
          handle: newSurface.nativeHandle!,
          version: newState.version,
        ));
      }
    }

    // Surfaces removed entirely from state.
    for (final id in oldState.surfaces.keys) {
      if (!newState.surfaces.containsKey(id)) {
        final old = oldState.surfaces[id]!;
        if (old.nativeHandle != null) {
          commands.add(NativeCommand.destroy(
            surfaceId: id,
            handle: old.nativeHandle!,
            version: newState.version,
          ));
        }
      }
    }

    return commands;
  }
}
