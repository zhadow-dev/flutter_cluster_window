import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cluster_window/src/core/cluster_state.dart';
import 'package:flutter_cluster_window/src/core/command_bus.dart';
import 'package:flutter_cluster_window/src/core/commands.dart';
import 'package:flutter_cluster_window/src/core/events.dart';
import 'package:flutter_cluster_window/src/core/state_reducer.dart';
import 'package:flutter_cluster_window/src/core/surface_state.dart';
import 'package:flutter_cluster_window/src/ordering/event_sequencer.dart';
import 'package:flutter_cluster_window/src/scheduler/scheduler.dart';

import 'helpers/mock_native_bridge.dart';

void main() {
  late CommandBus commandBus;
  late MockNativeBridge bridge;
  late Scheduler scheduler;
  late EventSequencer sequencer;

  setUp(() {
    bridge = MockNativeBridge();
    scheduler = Scheduler(bridge, backpressureThreshold: 5);
    commandBus = CommandBus(
      initialState: ClusterState(
        clusterId: 'chaos',
        lifecycle: ClusterLifecyclePhase.running,
      ),
      reducer: StateReducer(),
      scheduler: scheduler,
    );
    sequencer = EventSequencer();

    // Set up surfaces.
    commandBus.dispatch(CreateSurfaceCommand(
      surfaceId: 'main',
      frame: Rect.fromLTWH(100, 100, 800, 600),
    ));
    commandBus.dispatch(AttachHandleCommand(
      surfaceId: 'main',
      nativeHandle: 1,
    ));
    commandBus.dispatch(CreateSurfaceCommand(
      surfaceId: 'toolbar',
      frame: Rect.fromLTWH(100, 40, 800, 50),
    ));
    commandBus.dispatch(AttachHandleCommand(
      surfaceId: 'toolbar',
      nativeHandle: 2,
    ));
  });

  tearDown(() {
    commandBus.dispose();
    scheduler.dispose();
  });

  group('Chaos Tests', () {
    test('spam 500 move commands — system stays consistent', () {
      // Spam 500 moves. Backpressure should coalesce.
      for (var i = 0; i < 500; i++) {
        commandBus.dispatch(
          MoveClusterCommand(delta: Offset(1, 0)),
        );
      }

      // State must be consistent: moved 500px to the right.
      final mainFrame = commandBus.state.surfaces['main']!.frame;
      expect(mainFrame.left, closeTo(600, 0.1)); // 100 + 500
      expect(mainFrame.top, closeTo(100, 0.1));

      final toolbarFrame = commandBus.state.surfaces['toolbar']!.frame;
      expect(toolbarFrame.left, closeTo(600, 0.1)); // 100 + 500
      expect(toolbarFrame.top, closeTo(40, 0.1));

      // Version must be 500 + 4 (4 setup commands).
      expect(commandBus.state.version, 504);
    });

    test('split-brain: Dart thinks surface exists, native destroyed it', () {
      // Dart state has 'main' alive.
      expect(commandBus.state.surfaces['main']!.isAlive, true);

      // Simulate native silently destroying the window.
      commandBus.dispatch(EnterDegradedCommand(
        lostSurfaceId: 'main',
        reason: 'native_silent_destroy',
      ));

      // System must enter DEGRADED, not crash.
      expect(commandBus.state.mode, ClusterMode.degraded);
      expect(commandBus.state.lifecycle, ClusterLifecyclePhase.degraded);
      expect(commandBus.state.surfaces['main']!.isAlive, false);

      // Other surfaces must still work.
      expect(commandBus.state.surfaces['toolbar']!.isAlive, true);

      // Moving cluster should still work (only alive surfaces move).
      commandBus.dispatch(MoveClusterCommand(delta: Offset(10, 10)));
      expect(commandBus.state.surfaces['toolbar']!.frame.left, closeTo(110, 0.1));
      // Dead surface should NOT have moved.
      expect(commandBus.state.surfaces['main']!.frame.left, closeTo(100, 0.1));
    });

    test('duplicate events with same sequenceId are ignored', () {
      final event = WindowMovedEvent(
        sequenceId: 1,
        surfaceId: 'main',
        actualFrame: Rect.fromLTWH(200, 200, 800, 600),
        source: NativeEventSource.userDrag,
      );

      final r1 = sequencer.push(event);
      final r2 = sequencer.push(event); // Same sequenceId.

      expect(r1.length, 1);
      expect(r2.length, 0); // Duplicate dropped.
    });

    test('event freeze: no native events for extended period', () {
      // Push event 1.
      sequencer.push(WindowMovedEvent(
        sequenceId: 1,
        surfaceId: 'main',
        actualFrame: Rect.fromLTWH(100, 100, 800, 600),
        source: NativeEventSource.system,
      ));

      // Push event 5 (gap: 2,3,4 missing).
      sequencer.push(WindowMovedEvent(
        sequenceId: 5,
        surfaceId: 'main',
        actualFrame: Rect.fromLTWH(100, 100, 800, 600),
        source: NativeEventSource.system,
      ));

      // Sequencer should buffer but not crash.
      expect(sequencer.bufferedCount, 1);

      // Force flush should recover gracefully.
      sequencer = EventSequencer(maxBufferSize: 1);
      sequencer.push(WindowMovedEvent(
        sequenceId: 1,
        surfaceId: 'main',
        actualFrame: Rect.fromLTWH(100, 100, 800, 600),
        source: NativeEventSource.system,
      ));
      sequencer.push(WindowMovedEvent(
        sequenceId: 5,
        surfaceId: 'main',
        actualFrame: Rect.fromLTWH(100, 100, 800, 600),
        source: NativeEventSource.system,
      ));

      final flushed = sequencer.forceFlushIfNeeded();
      expect(flushed.length, 1); // Event 5 force-flushed.
    });

    test('rapid focus switching does not corrupt state', () {
      // Rapidly alternate focus between surfaces.
      for (var i = 0; i < 200; i++) {
        final surfaceId = i.isEven ? 'main' : 'toolbar';
        commandBus.dispatch(FocusSurfaceCommand(surfaceId: surfaceId));
      }

      // Final state must be consistent.
      final state = commandBus.state;
      final focusedSurfaces = state.surfaces.values.where((s) => s.focused);
      expect(focusedSurfaces.length, 1); // Only ONE surface focused.
      expect(state.activeSurfaceId, isNotNull);
    });

    test('operations on destroyed surface are rejected', () async {
      final errors = <InvalidCommandException>[];
      commandBus.errorStream.listen(errors.add);

      // Destroy main.
      commandBus.dispatch(DestroySurfaceCommand(surfaceId: 'main'));
      commandBus.dispatch(SurfaceDestroyedCommand(surfaceId: 'main'));

      // Try to operate on destroyed surface.
      commandBus.dispatch(FocusSurfaceCommand(surfaceId: 'main'));
      commandBus.dispatch(MoveSurfaceCommand(
        surfaceId: 'main',
        frame: Rect.fromLTWH(0, 0, 100, 100),
      ));
      commandBus.dispatch(SetVisibilityCommand(
        surfaceId: 'main',
        visible: true,
      ));

      await Future<void>.delayed(Duration.zero);
      expect(errors.length, 3);
    });

    test('scheduler backpressure: keeps only latest move per surface', () {
      bridge.clearRecords();

      // Queue 10 moves for the same surface.
      for (var i = 0; i < 10; i++) {
        commandBus.dispatch(
          MoveClusterCommand(delta: Offset(1, 0)),
        );
      }

      // Final state is correct regardless of backpressure.
      final mainFrame = commandBus.state.surfaces['main']!.frame;
      expect(mainFrame.left, closeTo(110, 0.1)); // 100 + 10
    });

    test('enter degraded then continue operating with remaining surfaces', () {
      // Kill main window.
      commandBus.dispatch(EnterDegradedCommand(
        lostSurfaceId: 'main',
        reason: 'crash',
      ));

      expect(commandBus.state.mode, ClusterMode.degraded);

      // Create a new surface while degraded — should work.
      commandBus.dispatch(CreateSurfaceCommand(
        surfaceId: 'replacement',
        frame: Rect.fromLTWH(100, 100, 800, 600),
      ));

      expect(commandBus.state.surfaces['replacement'], isNotNull);
      expect(commandBus.state.surfaces['replacement']!.isAlive, true);
    });
  });
}
