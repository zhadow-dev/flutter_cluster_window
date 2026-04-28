import 'dart:async';

import 'cluster_state.dart';
import 'commands.dart';
import 'state_differ.dart';
import 'state_reducer.dart';
import '../scheduler/scheduler.dart';

/// Exception thrown when a command violates lifecycle rules.
class InvalidCommandException implements Exception {
  final String message;
  final Command command;

  InvalidCommandException(this.message, this.command);

  @override
  String toString() =>
      'InvalidCommandException: $message (command: $command)';
}

/// Central command dispatcher — all state mutations flow through here.
///
/// Pipeline:
/// 1. `dispatch(Command)` validates the command against the current lifecycle.
/// 2. The [StateReducer] produces a new immutable [ClusterState].
/// 3. The [StateDiffer] computes the minimal set of native commands.
/// 4. The [Scheduler] enqueues those native commands.
/// 5. The new state is broadcast to all listeners.
///
/// Dispatch is always **synchronous** and never blocks the UI thread.
/// Native execution happens asynchronously via the scheduler.
class CommandBus {
  ClusterState _state;
  final StateReducer _reducer;
  final Scheduler _scheduler;
  final StateDiffer _differ;

  final _stateController = StreamController<ClusterState>.broadcast();
  final _commandController = StreamController<Command>.broadcast();
  final _errorController = StreamController<InvalidCommandException>.broadcast();

  CommandBus({
    required ClusterState initialState,
    required StateReducer reducer,
    required Scheduler scheduler,
    StateDiffer? differ,
  })  : _state = initialState,
        _reducer = reducer,
        _scheduler = scheduler,
        _differ = differ ?? StateDiffer();

  /// Current cluster state (read-only).
  ClusterState get state => _state;

  /// Stream of every state transition.
  Stream<ClusterState> get stateStream => _stateController.stream;

  /// Stream of every dispatched command (useful for debugging and replay).
  Stream<Command> get commandStream => _commandController.stream;

  /// Stream of commands rejected by lifecycle validation.
  Stream<InvalidCommandException> get errorStream => _errorController.stream;

  /// Dispatches a [Command] through the full pipeline.
  ///
  /// The command is validated, reduced, diffed, scheduled, and broadcast
  /// in a single synchronous pass.
  void dispatch(Command cmd) {
    final error = _validate(cmd, _state);
    if (error != null) {
      _errorController.add(error);
      return;
    }

    final oldState = _state;
    final newState = _reducer.reduce(oldState, cmd);
    _state = newState;

    final nativeCommands = _differ.diff(oldState, newState);
    if (nativeCommands.isNotEmpty) {
      _scheduler.enqueueAll(nativeCommands);
    }

    _commandController.add(cmd);
    _stateController.add(newState);
  }

  /// Validates a command against the current lifecycle state.
  ///
  /// Returns `null` if valid, or an [InvalidCommandException] describing
  /// the violation.
  InvalidCommandException? _validate(Command cmd, ClusterState state) {
    return switch (cmd) {
      MoveSurfaceCommand(:final surfaceId) =>
        _validateSurfaceExists(surfaceId, state, cmd) ??
        _validateSurfaceAlive(surfaceId, state, cmd),

      FocusSurfaceCommand(:final surfaceId) =>
        _validateSurfaceExists(surfaceId, state, cmd) ??
        _validateSurfaceAlive(surfaceId, state, cmd),

      SetVisibilityCommand(:final surfaceId) =>
        _validateSurfaceExists(surfaceId, state, cmd) ??
        _validateSurfaceAlive(surfaceId, state, cmd),

      DestroySurfaceCommand(:final surfaceId) =>
        _validateSurfaceExists(surfaceId, state, cmd),

      AttachHandleCommand(:final surfaceId) =>
        _validateSurfaceExists(surfaceId, state, cmd),

      AcceptNativePositionCommand(:final surfaceId) =>
        _validateSurfaceExists(surfaceId, state, cmd) ??
        _validateSurfaceAlive(surfaceId, state, cmd),

      CreateSurfaceCommand(:final surfaceId) =>
        state.surfaces.containsKey(surfaceId)
            ? InvalidCommandException(
                'Surface "$surfaceId" already exists', cmd)
            : null,

      MoveClusterCommand() => _validateClusterOperational(state, cmd),
      SetModeCommand() => _validateClusterOperational(state, cmd),

      StartClusterCommand() =>
        state.lifecycle != ClusterLifecyclePhase.init
            ? InvalidCommandException(
                'Cluster is not in INIT phase (current: ${state.lifecycle})',
                cmd)
            : null,

      TerminateClusterCommand() =>
        state.lifecycle.isDead
            ? InvalidCommandException('Cluster is already dead', cmd)
            : null,

      EnterDegradedCommand() => null,
      SurfaceDestroyedCommand() => null,
    };
  }

  InvalidCommandException? _validateSurfaceExists(
      String surfaceId, ClusterState state, Command cmd) {
    if (!state.surfaces.containsKey(surfaceId)) {
      return InvalidCommandException(
          'Surface "$surfaceId" does not exist', cmd);
    }
    return null;
  }

  InvalidCommandException? _validateSurfaceAlive(
      String surfaceId, ClusterState state, Command cmd) {
    final surface = state.surfaces[surfaceId];
    if (surface != null && !surface.isAlive) {
      return InvalidCommandException(
          'Surface "$surfaceId" is not alive (lifecycle: ${surface.lifecycle})',
          cmd);
    }
    return null;
  }

  InvalidCommandException? _validateClusterOperational(
      ClusterState state, Command cmd) {
    if (!state.lifecycle.isOperational) {
      return InvalidCommandException(
          'Cluster is not operational (lifecycle: ${state.lifecycle})', cmd);
    }
    return null;
  }

  /// Replaces the current state directly. Intended for testing and
  /// initialisation only.
  void setState(ClusterState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  /// Closes all broadcast streams.
  void dispose() {
    _stateController.close();
    _commandController.close();
    _errorController.close();
  }
}
