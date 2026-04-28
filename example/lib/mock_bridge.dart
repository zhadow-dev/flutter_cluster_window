import 'dart:async';

import 'package:flutter_cluster_window/flutter_cluster_window.dart';

/// In-memory mock of [NativeBridge] for the example app.
///
/// Simulates the native layer entirely in Dart, allowing the example
/// to demonstrate the full cluster pipeline without any C++ code.
class ExampleMockBridge implements NativeBridge {
  final _eventController = StreamController<NativeEvent>.broadcast();
  final List<NativeCommand> executedCommands = [];
  int _sequenceCounter = 0;

  @override
  Stream<NativeEvent> get events => _eventController.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> executeCommand(NativeCommand command) async {
    executedCommands.add(command);
  }

  @override
  Future<void> executeBatch(List<NativeCommand> commands) async {
    executedCommands.addAll(commands);
  }

  @override
  Future<Map<String, Map<String, dynamic>>> queryAllPositions() async {
    return {};
  }

  @override
  Future<void> dispose() async {
    _eventController.close();
  }

  // ---------------------------------------------------------------------------
  // Simulation helpers
  // ---------------------------------------------------------------------------

  /// Simulates a window being created by the native layer.
  void simulateWindowCreated(String surfaceId, int handle) {
    _eventController.add(WindowCreatedEvent(
      sequenceId: ++_sequenceCounter,
      surfaceId: surfaceId,
      nativeHandle: handle,
    ));
  }

  /// Simulates a window gaining OS focus.
  void simulateWindowFocused(String surfaceId) {
    _eventController.add(WindowFocusedEvent(
      sequenceId: ++_sequenceCounter,
      surfaceId: surfaceId,
    ));
  }

  /// Simulates a window crash or handle invalidation.
  void simulateWindowLost(String surfaceId, String reason) {
    _eventController.add(WindowLostEvent(
      sequenceId: ++_sequenceCounter,
      surfaceId: surfaceId,
      reason: reason,
    ));
  }

  /// Simulates the start of a user drag operation.
  void simulateDragStarted(String surfaceId) {
    _eventController.add(DragStartedEvent(
      sequenceId: ++_sequenceCounter,
      surfaceId: surfaceId,
    ));
  }

  /// Simulates the end of a user drag operation.
  void simulateDragEnded(String surfaceId) {
    _eventController.add(DragEndedEvent(
      sequenceId: ++_sequenceCounter,
      surfaceId: surfaceId,
    ));
  }
}
