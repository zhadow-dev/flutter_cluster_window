import 'dart:async';

import '../core/events.dart';
import 'native_command.dart';

/// Platform-agnostic interface for the native window management layer.
///
/// The native bridge is a **stateless executor** and **event forwarder**.
/// It executes commands from Dart (create, move, show, hide, focus, destroy)
/// and forwards raw OS events back to Dart without making any decisions.
///
/// On Windows the implementation uses a minimal HWND registry required by
/// Win32. All `surfaceId → handle` mapping lives in Dart.
abstract class NativeBridge {
  /// Stream of native events ordered by the [EventSequencer].
  Stream<NativeEvent> get events;

  /// Executes a single native command.
  Future<void> executeCommand(NativeCommand command);

  /// Executes a batch of move commands atomically.
  ///
  /// On Windows this uses `BeginDeferWindowPos` / `DeferWindowPos` /
  /// `EndDeferWindowPos` to apply all moves in a single screen-refresh cycle.
  Future<void> executeBatch(List<NativeCommand> commands);

  /// Queries the actual native positions of all tracked windows.
  ///
  /// Used by the reconciliation engine to detect position drift.
  Future<Map<String, Map<String, dynamic>>> queryAllPositions();

  /// Initialises the native bridge.
  Future<void> initialize();

  /// Disposes the native bridge and releases all resources.
  Future<void> dispose();
}
