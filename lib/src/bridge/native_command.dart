import 'dart:ui' show Rect;

import '../scheduler/scheduler.dart';

/// Native command types sent from Dart to the platform layer.
enum NativeCommandType {
  createWindow,
  moveWindow,
  showWindow,
  hideWindow,
  focusWindow,
  destroyWindow,
}

/// A serialisable command sent from Dart to the native layer.
///
/// Contains everything the native side needs to execute the operation.
/// The native layer never decides *what* to do — it only executes.
class NativeCommand {
  final NativeCommandType type;
  final String surfaceId;
  final int? handle;
  final Rect? frame;
  final int version;
  final CommandPriority priority;

  const NativeCommand({
    required this.type,
    required this.surfaceId,
    this.handle,
    this.frame,
    required this.version,
    required this.priority,
  });

  /// Creates a window-creation command.
  factory NativeCommand.create({
    required String surfaceId,
    required Rect frame,
    required int version,
  }) =>
      NativeCommand(
        type: NativeCommandType.createWindow,
        surfaceId: surfaceId,
        frame: frame,
        version: version,
        priority: CommandPriority.high,
      );

  /// Creates a window-move command.
  factory NativeCommand.move({
    required String surfaceId,
    required int handle,
    required Rect frame,
    required int version,
  }) =>
      NativeCommand(
        type: NativeCommandType.moveWindow,
        surfaceId: surfaceId,
        handle: handle,
        frame: frame,
        version: version,
        priority: CommandPriority.medium,
      );

  /// Creates a show-window command.
  factory NativeCommand.show({
    required String surfaceId,
    required int handle,
    required int version,
  }) =>
      NativeCommand(
        type: NativeCommandType.showWindow,
        surfaceId: surfaceId,
        handle: handle,
        version: version,
        priority: CommandPriority.medium,
      );

  /// Creates a hide-window command.
  factory NativeCommand.hide({
    required String surfaceId,
    required int handle,
    required int version,
  }) =>
      NativeCommand(
        type: NativeCommandType.hideWindow,
        surfaceId: surfaceId,
        handle: handle,
        version: version,
        priority: CommandPriority.medium,
      );

  /// Creates a focus-window command.
  factory NativeCommand.focus({
    required String surfaceId,
    required int handle,
    required int version,
  }) =>
      NativeCommand(
        type: NativeCommandType.focusWindow,
        surfaceId: surfaceId,
        handle: handle,
        version: version,
        priority: CommandPriority.high,
      );

  /// Creates a destroy-window command.
  factory NativeCommand.destroy({
    required String surfaceId,
    required int handle,
    required int version,
  }) =>
      NativeCommand(
        type: NativeCommandType.destroyWindow,
        surfaceId: surfaceId,
        handle: handle,
        version: version,
        priority: CommandPriority.high,
      );

  /// Serialises this command for MethodChannel transport.
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'surfaceId': surfaceId,
        if (handle != null) 'handle': handle,
        if (frame != null)
          'frame': {
            'x': frame!.left.round(),
            'y': frame!.top.round(),
            'w': frame!.width.round(),
            'h': frame!.height.round(),
          },
        'version': version,
      };

  @override
  String toString() =>
      'NativeCommand(${type.name}, surface: $surfaceId, handle: $handle, '
      'frame: $frame, v$version)';
}
