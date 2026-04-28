import 'dart:async';

import 'package:flutter/services.dart';

import 'native_bridge.dart';
import 'native_command.dart';
import '../core/events.dart';

/// Windows implementation of [NativeBridge].
///
/// Communicates with the C++ plugin via [MethodChannel] and [EventChannel].
/// The C++ side maintains a minimal HWND registry; all `surfaceId → handle`
/// mapping lives in Dart.
class WindowsNativeBridge implements NativeBridge {
  static const _channel = MethodChannel('flutter_cluster_window');
  static const _eventChannel = EventChannel('flutter_cluster_window/events');

  final _eventController = StreamController<NativeEvent>.broadcast();
  StreamSubscription? _eventSub;

  @override
  Stream<NativeEvent> get events => _eventController.stream;

  @override
  Future<void> initialize() async {
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        if (data is Map) {
          try {
            final event = NativeEvent.fromJson(Map<String, dynamic>.from(data));
            _eventController.add(event);
          } catch (_) {
            // Malformed event — silently ignored.
          }
        }
      },
      onError: (_) {
        // EventChannel transport error — silently ignored.
      },
    );

    await _channel.invokeMethod('initialize');
  }

  @override
  Future<void> executeCommand(NativeCommand command) async {
    await _channel.invokeMethod('executeCommand', command.toJson());
  }

  @override
  Future<void> executeBatch(List<NativeCommand> commands) async {
    await _channel.invokeMethod('executeBatch', {
      'commands': commands.map((c) => c.toJson()).toList(),
    });
  }

  @override
  Future<Map<String, Map<String, dynamic>>> queryAllPositions() async {
    final result =
        await _channel.invokeMethod<Map>('queryAllPositions') ?? {};
    return result.cast<String, Map<String, dynamic>>();
  }

  @override
  Future<void> dispose() async {
    _eventSub?.cancel();
    _eventSub = null;
    _eventController.close();
    await _channel.invokeMethod('dispose');
  }
}
