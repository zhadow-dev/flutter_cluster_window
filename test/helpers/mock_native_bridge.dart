import 'dart:async';

import 'package:flutter_cluster_window/src/bridge/native_bridge.dart';
import 'package:flutter_cluster_window/src/bridge/native_command.dart';
import 'package:flutter_cluster_window/src/core/events.dart';

/// Mock NativeBridge for testing.
///
/// Records all commands and allows manual event injection.
class MockNativeBridge implements NativeBridge {
  final List<NativeCommand> executedCommands = [];
  final List<List<NativeCommand>> executedBatches = [];
  final _eventController = StreamController<NativeEvent>.broadcast();

  /// Artificial delay to simulate slow native execution.
  Duration executionDelay = Duration.zero;

  /// If set, the next executeCommand call will throw.
  Object? nextError;

  @override
  Stream<NativeEvent> get events => _eventController.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> executeCommand(NativeCommand command) async {
    if (executionDelay > Duration.zero) {
      await Future.delayed(executionDelay);
    }
    if (nextError != null) {
      final err = nextError!;
      nextError = null;
      throw err;
    }
    executedCommands.add(command);
  }

  @override
  Future<void> executeBatch(List<NativeCommand> commands) async {
    if (executionDelay > Duration.zero) {
      await Future.delayed(executionDelay);
    }
    executedBatches.add(List.from(commands));
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

  /// Inject a native event (simulates native → Dart).
  void injectEvent(NativeEvent event) {
    _eventController.add(event);
  }

  /// Clear recorded commands.
  void clearRecords() {
    executedCommands.clear();
    executedBatches.clear();
  }
}
