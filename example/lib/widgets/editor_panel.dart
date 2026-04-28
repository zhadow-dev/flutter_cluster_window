import 'package:flutter/material.dart';
import 'package:flutter_cluster_window/flutter_cluster_window.dart';

/// Simulated code content for the file tree.
const _fileContents = <String, String>{
  'main.dart': '''import 'dart:ui' show Rect, Offset;
import 'package:flutter_cluster_window/flutter_cluster_window.dart';

void main() async {
  final cluster = ClusterController(
    clusterId: 'ide',
    bridge: WindowsNativeBridge(),
    primarySurfaceId: 'editor',
    surfaceOffsets: {
      'toolbar': SurfaceOffset(dx: 0, dy: -60),
      'sidebar': SurfaceOffset(dx: -260, dy: 0),
    },
  );

  await cluster.start();

  // Create the 3 windows — each becomes a real OS window.
  cluster.addSurface('editor',
    frame: Rect.fromLTWH(260, 60, 940, 700));
  cluster.addSurface('toolbar',
    frame: Rect.fromLTWH(0, 0, 1200, 50));
  cluster.addSurface('sidebar',
    frame: Rect.fromLTWH(0, 60, 250, 700));

  // Listen for state changes.
  cluster.onStateChanged.listen((state) {
    print('State v\${state.version}: '
        '\${state.aliveSurfaces.length} surfaces');
  });

  // Move the entire cluster.
  cluster.move(Offset(100, 50));
}''',
  'cluster_controller.dart': '''/// ClusterController — the single public API.
///
/// Wires: CommandBus, StateReducer, Scheduler,
///        EventSequencer, FocusRouter, LayoutEngine,
///        ReconciliationEngine, FailureHandler.
///
/// Rules:
/// - Dart owns ALL state
/// - Native = stateless executor
/// - Every mutation flows through CommandBus
/// - Failures ARE commands, not side effects
class ClusterController {
  final String clusterId;
  final NativeBridge _bridge;

  // Core pipeline
  late final StateReducer _reducer;
  late final Scheduler _scheduler;
  late final CommandBus _commandBus;

  void move(Offset delta) {
    _commandBus.dispatch(
      MoveClusterCommand(delta: delta),
    );
  }
}''',
  'commands.dart': '''/// Sealed command hierarchy.
/// Every mutation in the system is a Command.
sealed class Command {}

class MoveClusterCommand extends Command {
  final Offset delta;
  MoveClusterCommand({required this.delta});
}

class CreateSurfaceCommand extends Command {
  final String surfaceId;
  final Rect frame;
  CreateSurfaceCommand({
    required this.surfaceId,
    required this.frame,
  });
}

class FocusSurfaceCommand extends Command {
  final String surfaceId;
  FocusSurfaceCommand({required this.surfaceId});
}

class EnterDegradedCommand extends Command {
  final String lostSurfaceId;
  final String reason;
  EnterDegradedCommand({
    required this.lostSurfaceId,
    required this.reason,
  });
}''',
  'events.dart': '''/// Native events — forwarded from OS to Dart.
/// Each event has a sequenceId for ordering.
sealed class NativeEvent {
  int get sequenceId;
  String get surfaceId;
}

class WindowCreatedEvent extends NativeEvent {
  final int nativeHandle;
  // ..
}

class WindowMovedEvent extends NativeEvent {
  final Rect actualFrame;
  final NativeEventSource source;
  // ..
}

class DragStartedEvent extends NativeEvent {}
class DragEndedEvent extends NativeEvent {}
class WindowLostEvent extends NativeEvent {
  final String reason;
}''',
  'state_reducer.dart': '''/// Pure state reducer. NO side effects.
/// oldState + command → newState (version++)
class StateReducer {
  ClusterState reduce(
    ClusterState state,
    Command cmd,
  ) {
    final newState = switch (cmd) {
      MoveClusterCommand() =>
        _moveCluster(state, cmd),
      CreateSurfaceCommand() =>
        _createSurface(state, cmd),
      FocusSurfaceCommand() =>
        _focusSurface(state, cmd),
      EnterDegradedCommand() =>
        _enterDegraded(state, cmd),
      // ... 9 more handlers
    };

    // MANDATORY: version++ on every change.
    return newState.copyWith(
      version: state.version + 1,
    );
  }
}''',
  'scheduler.dart': '''/// 3-tier priority scheduler.
/// High:   focus, create (< 1 frame)
/// Medium: move, resize (coalesced)
/// Low:    reconcile, sync
///
/// Features:
/// - Move coalescing (latest wins)
/// - Pressure-based flush override
/// - Batch execution via DeferWindowPos
class Scheduler {
  final NativeBridge _bridge;

  void enqueue(NativeCommand cmd) {
    final queue = switch (cmd.priority) {
      CommandPriority.high => _highQueue,
      CommandPriority.medium => _mediumQueue,
      CommandPriority.low => _lowQueue,
    };

    // Coalesce moves: replace existing
    if (cmd.type == NativeCommandType.moveWindow) {
      _coalesceMove(queue, cmd);
    } else {
      queue.add(cmd);
    }
  }
}''',
  'chaos_test.dart': '''group('Chaos Tests', () {
  test('spam 500 moves — stays consistent', () {
    for (var i = 0; i < 500; i++) {
      commandBus.dispatch(
        MoveClusterCommand(delta: Offset(1, 0)),
      );
    }
    // State: moved exactly 500px right.
    expect(main.frame.left, closeTo(600, 0.1));
    expect(state.version, 504);
  });

  test('split-brain recovery', () {
    commandBus.dispatch(EnterDegradedCommand(
      lostSurfaceId: 'main',
      reason: 'native_crash',
    ));
    expect(state.mode, ClusterMode.degraded);
    expect(main.isAlive, false);
    // Other surfaces still operational.
    expect(toolbar.isAlive, true);
  });

  test('rapid focus switching', () {
    for (var i = 0; i < 200; i++) {
      commandBus.dispatch(FocusSurfaceCommand(
        surfaceId: i.isEven ? 'main' : 'toolbar',
      ));
    }
    // Only ONE surface focused.
    expect(focusedCount, 1);
  });
});''',
  'reducer_test.dart': '''group('StateReducer', () {
  test('version increments monotonically', () {
    state = reducer.reduce(state,
      CreateSurfaceCommand(
        surfaceId: 'main',
        frame: Rect.fromLTWH(100, 100, 800, 600),
      ));
    expect(state.version, 1);

    state = reducer.reduce(state,
      CreateSurfaceCommand(
        surfaceId: 'toolbar',
        frame: Rect.fromLTWH(100, 40, 800, 50),
      ));
    expect(state.version, 2);
  });

  test('dead surfaces do not move', () {
    state = reducer.reduce(state,
      DestroySurfaceCommand(surfaceId: 'main'));

    state = reducer.reduce(state,
      MoveClusterCommand(delta: Offset(50, 50)));

    expect(main.frame, originalFrame);
  });
});''',
  'pubspec.yaml': '''name: flutter_cluster_window
description: >
  Deterministic multi-window cluster runtime
  for Flutter Desktop.
version: 0.0.1

environment:
  sdk: ^3.11.5
  flutter: '>=3.3.0'

dependencies:
  flutter:
    sdk: flutter

flutter:
  plugin:
    platforms:
      windows:
        pluginClass: FlutterClusterWindowPluginCApi''',
  'README.md': '''# flutter_cluster_window

A deterministic multi-window cluster runtime
for Flutter Desktop.

## Philosophy

- Single Source of Truth: Dart owns ALL state
- Native = stateless executor + event forwarder
- Every mutation flows through CommandBus
- Failures ARE commands, not side effects

## Architecture

```
Flutter (Dart)
├── ClusterController
├── CommandBus + StateReducer
├── Scheduler (3-tier priority)
├── EventSequencer (buffered)
├── FocusRouter (debounced)
├── LayoutEngine
└── ReconciliationEngine

Native Bridge (C++)
├── Minimal handle registry
├── DeferWindowPos batching
└── WndProc event forwarding
```''',
};

/// Simulated code editor panel for the example IDE.
class EditorPanel extends StatelessWidget {
  final bool isActive;
  final String activeFile;
  final VoidCallback onTap;
  final ClusterState? clusterState;

  const EditorPanel({
    super.key,
    required this.isActive,
    required this.activeFile,
    required this.onTap,
    required this.clusterState,
  });

  @override
  Widget build(BuildContext context) {
    final content = _fileContents[activeFile] ?? '// No content';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          border: Border(
            left: BorderSide(
              color: isActive
                  ? const Color(0xFF58A6FF).withValues(alpha: 0.3)
                  : const Color(0xFF21262D),
            ),
          ),
        ),
        child: Column(
          children: [
            _EditorTabBar(
              activeFile: activeFile,
              clusterState: clusterState,
            ),
            Expanded(
              child: _CodeView(content: content),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab bar displaying the active file name and surface indicator.
class _EditorTabBar extends StatelessWidget {
  final String activeFile;
  final ClusterState? clusterState;

  const _EditorTabBar({
    required this.activeFile,
    required this.clusterState,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border(
          bottom: BorderSide(color: const Color(0xFF21262D)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFF58A6FF),
                  width: 2,
                ),
                right: BorderSide(color: const Color(0xFF21262D)),
              ),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getFileIcon(activeFile),
                    size: 14,
                    color: _getFileIconColor(activeFile),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    activeFile,
                    style: TextStyle(
                      color: const Color(0xFFE6EDF3),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          if (clusterState != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF3FB950),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3FB950).withValues(alpha: 0.4),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'editor',
                    style: TextStyle(
                      color: const Color(0xFF484F58),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String file) {
    if (file.endsWith('.dart')) return Icons.code;
    if (file.endsWith('.yaml')) return Icons.settings;
    if (file.endsWith('.md')) return Icons.description;
    return Icons.insert_drive_file;
  }

  Color _getFileIconColor(String file) {
    if (file.endsWith('.dart')) return const Color(0xFF79C0FF);
    if (file.endsWith('.yaml')) return const Color(0xFFF0883E);
    if (file.endsWith('.md')) return const Color(0xFF8B949E);
    return const Color(0xFF8B949E);
  }
}

/// Scrollable code view with line numbers and syntax highlighting.
class _CodeView extends StatelessWidget {
  final String content;

  const _CodeView({required this.content});

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');

    return Container(
      color: const Color(0xFF0D1117),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: lines.length,
        itemBuilder: (context, index) {
          return _CodeLine(
            lineNumber: index + 1,
            content: lines[index],
          );
        },
      ),
    );
  }
}

/// A single line of code with hover highlight and basic syntax colouring.
class _CodeLine extends StatefulWidget {
  final int lineNumber;
  final String content;

  const _CodeLine({
    required this.lineNumber,
    required this.content,
  });

  @override
  State<_CodeLine> createState() => _CodeLineState();
}

class _CodeLineState extends State<_CodeLine> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        color: _hovering
            ? const Color(0xFF161B22).withValues(alpha: 0.5)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Line number gutter.
            SizedBox(
              width: 56,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${widget.lineNumber}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: _hovering
                        ? const Color(0xFF484F58)
                        : const Color(0xFF30363D),
                    fontSize: 13,
                    fontFamily: 'Consolas',
                    height: 1.5,
                  ),
                ),
              ),
            ),

            // Code content.
            Expanded(
              child: Text(
                widget.content,
                style: TextStyle(
                  color: _colorize(widget.content),
                  fontSize: 13,
                  fontFamily: 'Consolas',
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns a colour based on the leading keyword of the line.
  Color _colorize(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('///') || trimmed.startsWith('//')) {
      return const Color(0xFF484F58);
    }
    if (trimmed.startsWith('import ') || trimmed.startsWith('export ')) {
      return const Color(0xFFFF7B72);
    }
    if (trimmed.startsWith('class ') || trimmed.startsWith('sealed ') ||
        trimmed.startsWith('enum ') || trimmed.startsWith('abstract ')) {
      return const Color(0xFFF0883E);
    }
    if (trimmed.startsWith('final ') || trimmed.startsWith('var ') ||
        trimmed.startsWith('late ') || trimmed.startsWith('const ')) {
      return const Color(0xFF79C0FF);
    }
    if (trimmed.startsWith('void ') || trimmed.startsWith('Future') ||
        trimmed.startsWith('async') || trimmed.startsWith('await')) {
      return const Color(0xFFD2A8FF);
    }
    if (trimmed.startsWith('test(') || trimmed.startsWith('group(') ||
        trimmed.startsWith('expect(')) {
      return const Color(0xFF3FB950);
    }
    if (trimmed.startsWith('#') || trimmed.startsWith('name:') ||
        trimmed.startsWith('description:') || trimmed.startsWith('version:')) {
      return const Color(0xFFF0883E);
    }
    return const Color(0xFFE6EDF3);
  }
}
