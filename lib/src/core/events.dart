import 'dart:ui' show Rect;

/// Origin of a native event.
enum NativeEventSource {
  /// The OS moved/resized the window (e.g. snap, display change).
  system,

  /// The user dragged or resized the window interactively.
  userDrag,

  /// A programmatic command issued by the cluster runtime.
  programmatic,
}

/// Base class for events emitted from the native layer to Dart.
///
/// Every event carries a monotonically increasing [sequenceId] for ordering
/// guarantees and a [timestamp] for debugging.
sealed class NativeEvent {
  final int sequenceId;
  final DateTime timestamp;

  NativeEvent({
    required this.sequenceId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Deserialises a [NativeEvent] from a JSON map.
  factory NativeEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'WINDOW_MOVED' => WindowMovedEvent.fromJson(json),
      'WINDOW_RESIZED' => WindowResizedEvent.fromJson(json),
      'WINDOW_FOCUSED' => WindowFocusedEvent.fromJson(json),
      'WINDOW_LOST' => WindowLostEvent.fromJson(json),
      'WINDOW_CREATED' => WindowCreatedEvent.fromJson(json),
      'WINDOW_DESTROYED' => WindowDestroyedEvent.fromJson(json),
      'DRAG_STARTED' => DragStartedEvent.fromJson(json),
      'DRAG_ENDED' => DragEndedEvent.fromJson(json),
      _ => throw ArgumentError('Unknown native event type: $type'),
    };
  }

  /// Serialises this event to a JSON-compatible map.
  Map<String, dynamic> toJson();
}

/// Emitted when a window is moved (by user drag or by the OS).
class WindowMovedEvent extends NativeEvent {
  final String surfaceId;
  final Rect actualFrame;
  final NativeEventSource source;

  WindowMovedEvent({
    required super.sequenceId,
    required this.surfaceId,
    required this.actualFrame,
    required this.source,
    super.timestamp,
  });

  factory WindowMovedEvent.fromJson(Map<String, dynamic> json) {
    final f = json['actualFrame'] as Map<String, dynamic>;
    return WindowMovedEvent(
      sequenceId: json['sequenceId'] as int,
      surfaceId: json['surfaceId'] as String,
      actualFrame: Rect.fromLTWH(
        (f['x'] as num).toDouble(),
        (f['y'] as num).toDouble(),
        (f['w'] as num).toDouble(),
        (f['h'] as num).toDouble(),
      ),
      source: NativeEventSource.values.byName(json['source'] as String),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'WINDOW_MOVED',
        'sequenceId': sequenceId,
        'surfaceId': surfaceId,
        'actualFrame': {
          'x': actualFrame.left,
          'y': actualFrame.top,
          'w': actualFrame.width,
          'h': actualFrame.height,
        },
        'source': source.name,
      };

  @override
  String toString() =>
      'WindowMovedEvent(surface: $surfaceId, frame: $actualFrame, source: $source)';
}

/// Emitted when a window is resized.
class WindowResizedEvent extends NativeEvent {
  final String surfaceId;
  final Rect actualFrame;
  final NativeEventSource source;

  WindowResizedEvent({
    required super.sequenceId,
    required this.surfaceId,
    required this.actualFrame,
    required this.source,
    super.timestamp,
  });

  factory WindowResizedEvent.fromJson(Map<String, dynamic> json) {
    final f = json['actualFrame'] as Map<String, dynamic>;
    return WindowResizedEvent(
      sequenceId: json['sequenceId'] as int,
      surfaceId: json['surfaceId'] as String,
      actualFrame: Rect.fromLTWH(
        (f['x'] as num).toDouble(),
        (f['y'] as num).toDouble(),
        (f['w'] as num).toDouble(),
        (f['h'] as num).toDouble(),
      ),
      source: NativeEventSource.values.byName(json['source'] as String),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'WINDOW_RESIZED',
        'sequenceId': sequenceId,
        'surfaceId': surfaceId,
        'actualFrame': {
          'x': actualFrame.left,
          'y': actualFrame.top,
          'w': actualFrame.width,
          'h': actualFrame.height,
        },
        'source': source.name,
      };

  @override
  String toString() =>
      'WindowResizedEvent(surface: $surfaceId, frame: $actualFrame)';
}

/// Emitted when a window gains OS focus.
class WindowFocusedEvent extends NativeEvent {
  final String surfaceId;

  WindowFocusedEvent({
    required super.sequenceId,
    required this.surfaceId,
    super.timestamp,
  });

  factory WindowFocusedEvent.fromJson(Map<String, dynamic> json) {
    return WindowFocusedEvent(
      sequenceId: json['sequenceId'] as int,
      surfaceId: json['surfaceId'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'WINDOW_FOCUSED',
        'sequenceId': sequenceId,
        'surfaceId': surfaceId,
      };

  @override
  String toString() => 'WindowFocusedEvent(surface: $surfaceId)';
}

/// Emitted when a window is lost (crashed or handle invalidated).
class WindowLostEvent extends NativeEvent {
  final String surfaceId;
  final String reason;

  WindowLostEvent({
    required super.sequenceId,
    required this.surfaceId,
    this.reason = 'unknown',
    super.timestamp,
  });

  factory WindowLostEvent.fromJson(Map<String, dynamic> json) {
    return WindowLostEvent(
      sequenceId: json['sequenceId'] as int,
      surfaceId: json['surfaceId'] as String,
      reason: json['reason'] as String? ?? 'unknown',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'WINDOW_LOST',
        'sequenceId': sequenceId,
        'surfaceId': surfaceId,
        'reason': reason,
      };

  @override
  String toString() =>
      'WindowLostEvent(surface: $surfaceId, reason: $reason)';
}

/// Emitted when a native window has been successfully created.
class WindowCreatedEvent extends NativeEvent {
  final String surfaceId;
  final int nativeHandle;

  WindowCreatedEvent({
    required super.sequenceId,
    required this.surfaceId,
    required this.nativeHandle,
    super.timestamp,
  });

  factory WindowCreatedEvent.fromJson(Map<String, dynamic> json) {
    return WindowCreatedEvent(
      sequenceId: json['sequenceId'] as int,
      surfaceId: json['surfaceId'] as String,
      nativeHandle: json['nativeHandle'] as int,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'WINDOW_CREATED',
        'sequenceId': sequenceId,
        'surfaceId': surfaceId,
        'nativeHandle': nativeHandle,
      };

  @override
  String toString() =>
      'WindowCreatedEvent(surface: $surfaceId, handle: $nativeHandle)';
}

/// Emitted when a native window has been destroyed.
class WindowDestroyedEvent extends NativeEvent {
  final String surfaceId;

  WindowDestroyedEvent({
    required super.sequenceId,
    required this.surfaceId,
    super.timestamp,
  });

  factory WindowDestroyedEvent.fromJson(Map<String, dynamic> json) {
    return WindowDestroyedEvent(
      sequenceId: json['sequenceId'] as int,
      surfaceId: json['surfaceId'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'WINDOW_DESTROYED',
        'sequenceId': sequenceId,
        'surfaceId': surfaceId,
      };

  @override
  String toString() => 'WindowDestroyedEvent(surface: $surfaceId)';
}

/// Emitted when the user starts dragging a window.
class DragStartedEvent extends NativeEvent {
  final String surfaceId;

  DragStartedEvent({
    required super.sequenceId,
    required this.surfaceId,
    super.timestamp,
  });

  factory DragStartedEvent.fromJson(Map<String, dynamic> json) {
    return DragStartedEvent(
      sequenceId: json['sequenceId'] as int,
      surfaceId: json['surfaceId'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'DRAG_STARTED',
        'sequenceId': sequenceId,
        'surfaceId': surfaceId,
      };

  @override
  String toString() => 'DragStartedEvent(surface: $surfaceId)';
}

/// Emitted when the user stops dragging a window.
class DragEndedEvent extends NativeEvent {
  final String surfaceId;

  DragEndedEvent({
    required super.sequenceId,
    required this.surfaceId,
    super.timestamp,
  });

  factory DragEndedEvent.fromJson(Map<String, dynamic> json) {
    return DragEndedEvent(
      sequenceId: json['sequenceId'] as int,
      surfaceId: json['surfaceId'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'DRAG_ENDED',
        'sequenceId': sequenceId,
        'surfaceId': surfaceId,
      };

  @override
  String toString() => 'DragEndedEvent(surface: $surfaceId)';
}
