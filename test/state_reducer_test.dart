import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cluster_window/src/core/cluster_state.dart';
import 'package:flutter_cluster_window/src/core/commands.dart';
import 'package:flutter_cluster_window/src/core/state_reducer.dart';
import 'package:flutter_cluster_window/src/core/surface_state.dart';

void main() {
  late StateReducer reducer;
  late ClusterState baseState;

  setUp(() {
    reducer = StateReducer();
    baseState = ClusterState(
      clusterId: 'test',
      lifecycle: ClusterLifecyclePhase.running,
      version: 0,
    );
  });

  group('StateReducer', () {
    group('version incrementing', () {
      test('every reduce increments version by 1', () {
        final state = reducer.reduce(
          baseState,
          CreateSurfaceCommand(
            surfaceId: 'main',
            frame: Rect.fromLTWH(100, 100, 800, 600),
          ),
        );
        expect(state.version, 1);

        final state2 = reducer.reduce(
          state,
          CreateSurfaceCommand(
            surfaceId: 'toolbar',
            frame: Rect.fromLTWH(100, 40, 800, 50),
          ),
        );
        expect(state2.version, 2);
      });
    });

    group('CreateSurfaceCommand', () {
      test('creates a new surface with correct properties', () {
        final state = reducer.reduce(
          baseState,
          CreateSurfaceCommand(
            surfaceId: 'main',
            frame: Rect.fromLTWH(100, 100, 800, 600),
            zIndex: 1,
          ),
        );

        expect(state.surfaces.length, 1);
        expect(state.surfaces['main'], isNotNull);
        expect(state.surfaces['main']!.id, 'main');
        expect(state.surfaces['main']!.frame,
            Rect.fromLTWH(100, 100, 800, 600));
        expect(state.surfaces['main']!.zIndex, 1);
        expect(state.surfaces['main']!.lifecycle,
            SurfaceLifecyclePhase.created);
        expect(state.surfaces['main']!.visible, false);
        expect(state.surfaces['main']!.focused, false);
        expect(state.surfaces['main']!.isAlive, true);
      });
    });

    group('MoveClusterCommand', () {
      test('moves all alive surfaces by delta', () {
        var state = reducer.reduce(
          baseState,
          CreateSurfaceCommand(
            surfaceId: 'main',
            frame: Rect.fromLTWH(100, 100, 800, 600),
          ),
        );

        // Attach to make operational.
        state = reducer.reduce(
          state,
          AttachHandleCommand(surfaceId: 'main', nativeHandle: 1),
        );

        state = reducer.reduce(
          state,
          CreateSurfaceCommand(
            surfaceId: 'toolbar',
            frame: Rect.fromLTWH(100, 40, 800, 50),
          ),
        );

        state = reducer.reduce(
          state,
          AttachHandleCommand(surfaceId: 'toolbar', nativeHandle: 2),
        );

        state = reducer.reduce(
          state,
          MoveClusterCommand(delta: const Offset(10, 20)),
        );

        expect(state.surfaces['main']!.frame,
            Rect.fromLTWH(110, 120, 800, 600));
        expect(state.surfaces['toolbar']!.frame,
            Rect.fromLTWH(110, 60, 800, 50));
      });

      test('does not move dead surfaces', () {
        var state = reducer.reduce(
          baseState,
          CreateSurfaceCommand(
            surfaceId: 'main',
            frame: Rect.fromLTWH(100, 100, 800, 600),
          ),
        );

        state = reducer.reduce(
          state,
          AttachHandleCommand(surfaceId: 'main', nativeHandle: 1),
        );

        state = reducer.reduce(
          state,
          DestroySurfaceCommand(surfaceId: 'main'),
        );

        final originalFrame = state.surfaces['main']!.frame;

        state = reducer.reduce(
          state,
          MoveClusterCommand(delta: const Offset(50, 50)),
        );

        // Dead surface should not have moved.
        expect(state.surfaces['main']!.frame, originalFrame);
      });
    });

    group('FocusSurfaceCommand', () {
      test('focuses target and unfocuses all others', () {
        var state = reducer.reduce(
          baseState,
          CreateSurfaceCommand(
            surfaceId: 'main',
            frame: Rect.fromLTWH(100, 100, 800, 600),
          ),
        );

        state = reducer.reduce(
          state,
          CreateSurfaceCommand(
            surfaceId: 'toolbar',
            frame: Rect.fromLTWH(100, 40, 800, 50),
          ),
        );

        state = reducer.reduce(
          state,
          FocusSurfaceCommand(surfaceId: 'main'),
        );

        expect(state.surfaces['main']!.focused, true);
        expect(state.surfaces['toolbar']!.focused, false);
        expect(state.activeSurfaceId, 'main');

        state = reducer.reduce(
          state,
          FocusSurfaceCommand(surfaceId: 'toolbar'),
        );

        expect(state.surfaces['main']!.focused, false);
        expect(state.surfaces['toolbar']!.focused, true);
        expect(state.activeSurfaceId, 'toolbar');
      });
    });

    group('DestroySurfaceCommand', () {
      test('transitions surface to destroying and marks dead', () {
        var state = reducer.reduce(
          baseState,
          CreateSurfaceCommand(
            surfaceId: 'main',
            frame: Rect.fromLTWH(100, 100, 800, 600),
          ),
        );

        state = reducer.reduce(
          state,
          DestroySurfaceCommand(surfaceId: 'main'),
        );

        expect(state.surfaces['main']!.lifecycle,
            SurfaceLifecyclePhase.destroying);
        expect(state.surfaces['main']!.isAlive, false);
        expect(state.surfaces['main']!.focused, false);
      });

      test('clears activeSurfaceId if destroyed surface was active', () {
        var state = reducer.reduce(
          baseState,
          CreateSurfaceCommand(
            surfaceId: 'main',
            frame: Rect.fromLTWH(100, 100, 800, 600),
          ),
        );

        state = reducer.reduce(
          state,
          FocusSurfaceCommand(surfaceId: 'main'),
        );

        expect(state.activeSurfaceId, 'main');

        state = reducer.reduce(
          state,
          DestroySurfaceCommand(surfaceId: 'main'),
        );

        expect(state.activeSurfaceId, isNull);
      });
    });

    group('EnterDegradedCommand', () {
      test('enters degraded mode and marks surface dead', () {
        var state = reducer.reduce(
          baseState,
          CreateSurfaceCommand(
            surfaceId: 'main',
            frame: Rect.fromLTWH(100, 100, 800, 600),
          ),
        );

        state = reducer.reduce(
          state,
          EnterDegradedCommand(lostSurfaceId: 'main', reason: 'crash'),
        );

        expect(state.mode, ClusterMode.degraded);
        expect(state.lifecycle, ClusterLifecyclePhase.degraded);
        expect(state.surfaces['main']!.isAlive, false);
      });
    });

    group('AcceptNativePositionCommand', () {
      test('accepts native position into state', () {
        var state = reducer.reduce(
          baseState,
          CreateSurfaceCommand(
            surfaceId: 'main',
            frame: Rect.fromLTWH(100, 100, 800, 600),
          ),
        );

        state = reducer.reduce(
          state,
          AcceptNativePositionCommand(
            surfaceId: 'main',
            nativeFrame: Rect.fromLTWH(200, 200, 800, 600),
          ),
        );

        expect(state.surfaces['main']!.frame,
            Rect.fromLTWH(200, 200, 800, 600));
      });
    });

    group('Lifecycle transitions', () {
      test('StartClusterCommand transitions init → running', () {
        final initState = const ClusterState(
          clusterId: 'test',
          lifecycle: ClusterLifecyclePhase.init,
        );

        final state = reducer.reduce(initState, StartClusterCommand());
        expect(state.lifecycle, ClusterLifecyclePhase.running);
      });

      test('TerminateClusterCommand transitions running → terminating', () {
        final state = reducer.reduce(baseState, TerminateClusterCommand());
        expect(state.lifecycle, ClusterLifecyclePhase.terminating);
      });
    });
  });
}
