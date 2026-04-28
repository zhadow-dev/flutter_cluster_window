import 'dart:async';
import 'dart:collection';

import '../bridge/native_bridge.dart';
import '../bridge/native_command.dart';

/// Priority levels for native commands.
///
/// Execution order: high → medium → low.
/// Within the same priority, commands execute in insertion order.
enum CommandPriority {
  /// Focus changes and create/destroy — executed first.
  high,

  /// Move, resize, show/hide — batched for performance.
  medium,

  /// Reconciliation corrections — executed last.
  low,
}

/// Throttles, batches, and orders native commands before execution.
///
/// Key behaviours:
/// - Runs at most 60 updates/sec (16 ms tick interval).
/// - Maintains three priority queues: high → medium → low.
/// - Coalesces move commands per-surface (only the latest is kept).
/// - Applies back-pressure when the medium queue exceeds the threshold.
/// - Triggers an immediate flush when total pending commands exceed the
///   pressure flush threshold.
class Scheduler {
  final NativeBridge _bridge;

  /// Maximum pending move commands per surface before back-pressure.
  final int backpressureThreshold;

  /// Total pending count that triggers an immediate flush.
  final int pressureFlushThreshold;

  /// Interval between scheduled ticks.
  final Duration tickInterval;

  final Queue<NativeCommand> _high = Queue();
  final Queue<NativeCommand> _medium = Queue();
  final Queue<NativeCommand> _low = Queue();

  Timer? _tickTimer;
  bool _isFlushing = false;

  /// Tracks the latest move command per surface for coalescing.
  final Map<String, NativeCommand> _latestMovePerSurface = {};

  Scheduler(
    this._bridge, {
    this.backpressureThreshold = 5,
    this.pressureFlushThreshold = 20,
    this.tickInterval = const Duration(milliseconds: 16),
  });

  /// Total pending commands across all queues.
  int get pendingCount => _high.length + _medium.length + _low.length;

  /// Whether the scheduler tick loop is running.
  bool get isRunning => _tickTimer != null;

  /// Starts the periodic tick loop.
  void start() {
    if (_tickTimer != null) return;
    _tickTimer = Timer.periodic(tickInterval, (_) => _tick());
  }

  /// Stops the periodic tick loop.
  void stop() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  /// Enqueues a single native command.
  ///
  /// Move commands are coalesced per-surface. If total pending commands
  /// exceed [pressureFlushThreshold], an immediate flush is triggered.
  void enqueue(NativeCommand cmd) {
    if (cmd.type == NativeCommandType.moveWindow) {
      _enqueueMoveWithBackpressure(cmd);
    } else {
      _queueFor(cmd.priority).add(cmd);
    }

    if (pendingCount > pressureFlushThreshold) {
      _tick();
    }
  }

  /// Enqueues multiple native commands.
  void enqueueAll(List<NativeCommand> commands) {
    for (final cmd in commands) {
      enqueue(cmd);
    }
  }

  /// Forces an immediate flush of all queues.
  Future<void> flush() => _tick();

  /// Enqueues a move command with per-surface coalescing and back-pressure.
  void _enqueueMoveWithBackpressure(NativeCommand cmd) {
    assert(cmd.type == NativeCommandType.moveWindow);

    final existing = _latestMovePerSurface[cmd.surfaceId];
    if (existing != null) {
      _medium.removeWhere(
        (c) =>
            c.type == NativeCommandType.moveWindow &&
            c.surfaceId == cmd.surfaceId,
      );
    }

    _latestMovePerSurface[cmd.surfaceId] = cmd;
    _medium.add(cmd);

    if (_medium.length > backpressureThreshold) {
      _compactMediumQueue();
    }
  }

  /// Compacts the medium queue by keeping only the latest command per surface.
  void _compactMediumQueue() {
    final latest = <String, NativeCommand>{};
    final nonMove = <NativeCommand>[];

    for (final cmd in _medium) {
      if (cmd.type == NativeCommandType.moveWindow) {
        latest[cmd.surfaceId] = cmd;
      } else {
        nonMove.add(cmd);
      }
    }

    _medium.clear();
    _medium.addAll(nonMove);
    _medium.addAll(latest.values);
  }

  Queue<NativeCommand> _queueFor(CommandPriority priority) => switch (priority) {
        CommandPriority.high => _high,
        CommandPriority.medium => _medium,
        CommandPriority.low => _low,
      };

  /// Drains all queues in priority order: high → medium (batched) → low.
  Future<void> _tick() async {
    if (_isFlushing) return;
    if (pendingCount == 0) return;

    _isFlushing = true;
    try {
      // High priority: execute one-by-one.
      while (_high.isNotEmpty) {
        final cmd = _high.removeFirst();
        await _bridge.executeCommand(cmd);
      }

      // Medium priority: batch all moves together.
      if (_medium.isNotEmpty) {
        final moves = <NativeCommand>[];
        final others = <NativeCommand>[];

        while (_medium.isNotEmpty) {
          final cmd = _medium.removeFirst();
          if (cmd.type == NativeCommandType.moveWindow) {
            moves.add(cmd);
          } else {
            others.add(cmd);
          }
        }

        for (final cmd in others) {
          await _bridge.executeCommand(cmd);
        }

        if (moves.isNotEmpty) {
          await _bridge.executeBatch(moves);
        }

        _latestMovePerSurface.clear();
      }

      // Low priority: execute one-by-one.
      while (_low.isNotEmpty) {
        final cmd = _low.removeFirst();
        await _bridge.executeCommand(cmd);
      }
    } finally {
      _isFlushing = false;
    }
  }

  /// Clears all pending commands without executing them.
  void clear() {
    _high.clear();
    _medium.clear();
    _low.clear();
    _latestMovePerSurface.clear();
  }

  /// Stops the tick timer and clears all queues.
  void dispose() {
    stop();
    clear();
  }
}
