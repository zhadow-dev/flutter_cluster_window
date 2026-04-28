import 'dart:async';
import 'dart:ui' show Rect;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cluster_window/src/core/cluster_state.dart';
import 'package:flutter_cluster_window/src/core/commands.dart';
import 'package:flutter_cluster_window/src/core/events.dart';
import 'package:flutter_cluster_window/src/core/surface_state.dart';
import 'package:flutter_cluster_window/src/focus/focus_router.dart';

void main() {
  late FocusRouter router;
  late ClusterState state;

  setUp(() {
    state = ClusterState(
      clusterId: 'test',
      lifecycle: ClusterLifecyclePhase.running,
      surfaces: {
        'main': SurfaceState(
          id: 'main',
          frame: Rect.fromLTWH(100, 100, 800, 600),
          isAlive: true,
          lifecycle: SurfaceLifecyclePhase.visible,
        ),
        'toolbar': SurfaceState(
          id: 'toolbar',
          frame: Rect.fromLTWH(100, 40, 800, 50),
          isAlive: true,
          lifecycle: SurfaceLifecyclePhase.visible,
        ),
      },
    );
  });

  tearDown(() {
    router.dispose();
  });

  group('FocusRouter', () {
    test('debounces focus: only fires after debounce period', () {
      fakeAsync((async) {
        final commands = <FocusSurfaceCommand>[];
        router = FocusRouter(
          debounce: const Duration(milliseconds: 50),
          onFocusReady: commands.add,
        );

        router.handleFocusEvent(
          WindowFocusedEvent(sequenceId: 1, surfaceId: 'main'),
          state,
        );

        // Immediately: no command yet.
        expect(commands, isEmpty);

        // After debounce: command fires.
        async.elapse(const Duration(milliseconds: 60));
        expect(commands.length, 1);
        expect(commands.first.surfaceId, 'main');
      });
    });

    test('rapid focus switching: only last focus wins', () {
      fakeAsync((async) {
        final commands = <FocusSurfaceCommand>[];
        router = FocusRouter(
          debounce: const Duration(milliseconds: 50),
          onFocusReady: commands.add,
        );

        // Rapid alt-tab simulation.
        router.handleFocusEvent(
          WindowFocusedEvent(sequenceId: 1, surfaceId: 'main'),
          state,
        );
        async.elapse(const Duration(milliseconds: 10));

        router.handleFocusEvent(
          WindowFocusedEvent(sequenceId: 2, surfaceId: 'toolbar'),
          state,
        );
        async.elapse(const Duration(milliseconds: 10));

        router.handleFocusEvent(
          WindowFocusedEvent(sequenceId: 3, surfaceId: 'main'),
          state,
        );

        // Wait for debounce.
        async.elapse(const Duration(milliseconds: 60));

        // Only ONE command, for the LAST focus target.
        expect(commands.length, 1);
        expect(commands.first.surfaceId, 'main');
      });
    });

    test('ignores focus on dead surfaces', () {
      fakeAsync((async) {
        final commands = <FocusSurfaceCommand>[];
        router = FocusRouter(
          debounce: const Duration(milliseconds: 50),
          onFocusReady: commands.add,
        );

        final stateWithDead = state.copyWith(
          surfaces: {
            ...state.surfaces,
            'main': state.surfaces['main']!.copyWith(isAlive: false),
          },
        );

        router.handleFocusEvent(
          WindowFocusedEvent(sequenceId: 1, surfaceId: 'main'),
          stateWithDead,
        );

        async.elapse(const Duration(milliseconds: 60));
        expect(commands, isEmpty);
      });
    });

    test('flushPending resolves immediately', () {
      final commands = <FocusSurfaceCommand>[];
      router = FocusRouter(
        debounce: const Duration(milliseconds: 50),
        onFocusReady: commands.add,
      );

      router.handleFocusEvent(
        WindowFocusedEvent(sequenceId: 1, surfaceId: 'main'),
        state,
      );

      // Flush before debounce expires.
      router.flushPending();

      expect(commands.length, 1);
      expect(commands.first.surfaceId, 'main');
    });

    test('cancel removes pending focus', () {
      fakeAsync((async) {
        final commands = <FocusSurfaceCommand>[];
        router = FocusRouter(
          debounce: const Duration(milliseconds: 50),
          onFocusReady: commands.add,
        );

        router.handleFocusEvent(
          WindowFocusedEvent(sequenceId: 1, surfaceId: 'main'),
          state,
        );

        router.cancel();

        async.elapse(const Duration(milliseconds: 60));
        expect(commands, isEmpty);
      });
    });
  });
}
