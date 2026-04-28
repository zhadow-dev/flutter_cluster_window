import 'dart:async';

import '../core/commands.dart';
import '../core/events.dart';

/// Failure event emitted to external consumers.
class FailureEvent {
  final String surfaceId;
  final String reason;
  final DateTime timestamp;

  FailureEvent({
    required this.surfaceId,
    required this.reason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() =>
      'FailureEvent(surface: $surfaceId, reason: $reason)';
}

/// Converts native failures into commands that flow through the [CommandBus].
///
/// Implements the active failure propagation pattern:
/// `WindowLostEvent → EnterDegradedCommand → Reducer → state.mode = degraded`
///
/// Failures are treated as first-class commands rather than passive side effects.
class FailureHandler {
  final _failureController = StreamController<FailureEvent>.broadcast();

  /// Stream of failure events for external monitoring.
  Stream<FailureEvent> get failures => _failureController.stream;

  /// Handles a window loss event and returns an [EnterDegradedCommand]
  /// that must be dispatched through the [CommandBus].
  EnterDegradedCommand handleWindowLost(WindowLostEvent event) {
    _failureController.add(FailureEvent(
      surfaceId: event.surfaceId,
      reason: event.reason,
    ));

    return EnterDegradedCommand(
      lostSurfaceId: event.surfaceId,
      reason: event.reason,
    );
  }

  /// Handles a generic surface error and returns an [EnterDegradedCommand].
  EnterDegradedCommand handleSurfaceError(String surfaceId, String reason) {
    _failureController.add(FailureEvent(
      surfaceId: surfaceId,
      reason: reason,
    ));

    return EnterDegradedCommand(
      lostSurfaceId: surfaceId,
      reason: reason,
    );
  }

  /// Closes the failure stream.
  void dispose() {
    _failureController.close();
  }
}
