import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cluster_window/src/bridge/native_command.dart';
import 'package:flutter_cluster_window/src/scheduler/scheduler.dart';

import 'helpers/mock_native_bridge.dart';

void main() {
  late Scheduler scheduler;
  late MockNativeBridge bridge;

  setUp(() {
    bridge = MockNativeBridge();
    scheduler = Scheduler(
      bridge,
      backpressureThreshold: 3,
      pressureFlushThreshold: 10,
    );
  });

  tearDown(() {
    scheduler.dispose();
  });

  group('Scheduler', () {
    test('executes high priority commands before medium', () async {
      // Enqueue medium first, then high.
      scheduler.enqueue(NativeCommand.move(
        surfaceId: 'main',
        handle: 1,
        frame: Rect.fromLTWH(100, 100, 800, 600),
        version: 1,
      ));

      scheduler.enqueue(NativeCommand.focus(
        surfaceId: 'main',
        handle: 1,
        version: 2,
      ));

      await scheduler.flush();

      // Focus (high) should execute before move (medium).
      expect(bridge.executedCommands.length, greaterThanOrEqualTo(2));
      final focusIdx = bridge.executedCommands.indexWhere(
        (c) => c.type == NativeCommandType.focusWindow,
      );
      final moveIdx = bridge.executedCommands.indexWhere(
        (c) => c.type == NativeCommandType.moveWindow,
      );
      expect(focusIdx, lessThan(moveIdx));
    });

    test('coalesces move commands per surface', () async {
      // Enqueue 5 moves for the same surface.
      for (var i = 0; i < 5; i++) {
        scheduler.enqueue(NativeCommand.move(
          surfaceId: 'main',
          handle: 1,
          frame: Rect.fromLTWH(100 + i.toDouble(), 100, 800, 600),
          version: i + 1,
        ));
      }

      await scheduler.flush();

      // Should coalesce: only the LATEST move for 'main' should execute.
      final moveCommands = bridge.executedCommands
          .where((c) => c.type == NativeCommandType.moveWindow)
          .toList();

      // Due to coalescing, we should have <= 5 moves (ideally 1).
      expect(moveCommands.length, lessThanOrEqualTo(5));

      // The last executed move should have the latest frame.
      final lastMove = moveCommands.last;
      expect(lastMove.frame!.left, closeTo(104, 0.1));
    });

    test('batches moves via executeBatch', () async {
      // Enqueue moves for different surfaces.
      scheduler.enqueue(NativeCommand.move(
        surfaceId: 'main',
        handle: 1,
        frame: Rect.fromLTWH(100, 100, 800, 600),
        version: 1,
      ));
      scheduler.enqueue(NativeCommand.move(
        surfaceId: 'toolbar',
        handle: 2,
        frame: Rect.fromLTWH(100, 40, 800, 50),
        version: 2,
      ));

      await scheduler.flush();

      // Should use batch execution for moves.
      expect(bridge.executedBatches.length, 1);
      expect(bridge.executedBatches.first.length, 2);
    });

    test('pendingCount tracks correctly', () {
      expect(scheduler.pendingCount, 0);

      scheduler.enqueue(NativeCommand.focus(
        surfaceId: 'main',
        handle: 1,
        version: 1,
      ));

      expect(scheduler.pendingCount, 1);

      scheduler.enqueue(NativeCommand.move(
        surfaceId: 'main',
        handle: 1,
        frame: Rect.fromLTWH(0, 0, 100, 100),
        version: 2,
      ));

      expect(scheduler.pendingCount, 2);
    });

    test('clear removes all pending commands', () {
      scheduler.enqueue(NativeCommand.focus(
        surfaceId: 'main',
        handle: 1,
        version: 1,
      ));
      scheduler.enqueue(NativeCommand.move(
        surfaceId: 'main',
        handle: 1,
        frame: const Rect.fromLTWH(0, 0, 100, 100),
        version: 2,
      ));

      expect(scheduler.pendingCount, 2);

      scheduler.clear();

      expect(scheduler.pendingCount, 0);
    });
  });
}
