import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cluster_window/src/core/cluster_state.dart';
import 'package:flutter_cluster_window/src/core/command_bus.dart';
import 'package:flutter_cluster_window/src/core/commands.dart';
import 'package:flutter_cluster_window/src/core/state_reducer.dart';
import 'package:flutter_cluster_window/src/core/surface_state.dart';
import 'package:flutter_cluster_window/src/scheduler/scheduler.dart';

import 'helpers/mock_native_bridge.dart';

void main() {
  late CommandBus commandBus;
  late MockNativeBridge bridge;
  late Scheduler scheduler;
  late List<InvalidCommandException> errors;
  late List<ClusterState> states;

  setUp(() {
    bridge = MockNativeBridge();
    scheduler = Scheduler(bridge);
    commandBus = CommandBus(
      initialState: ClusterState(
        clusterId: 'test',
        lifecycle: ClusterLifecyclePhase.running,
      ),
      reducer: StateReducer(),
      scheduler: scheduler,
    );
    errors = [];
    states = [];

    // Set up listeners BEFORE dispatching.
    commandBus.errorStream.listen(errors.add);
    commandBus.stateStream.listen(states.add);
  });

  tearDown(() {
    commandBus.dispose();
    scheduler.dispose();
  });

  group('CommandBus', () {
    group('lifecycle validation', () {
      test('rejects MoveSurfaceCommand for non-existent surface', () async {
        commandBus.dispatch(MoveSurfaceCommand(
          surfaceId: 'ghost',
          frame: Rect.fromLTWH(0, 0, 100, 100),
        ));

        // Give async stream a moment to deliver.
        await Future<void>.delayed(Duration.zero);

        expect(errors.length, 1);
        expect(errors.first.message, contains('does not exist'));
      });

      test('rejects FocusSurfaceCommand for dead surface', () async {
        // Create and then destroy.
        commandBus.dispatch(CreateSurfaceCommand(
          surfaceId: 'main',
          frame: Rect.fromLTWH(0, 0, 100, 100),
        ));
        commandBus.dispatch(DestroySurfaceCommand(surfaceId: 'main'));

        // Try to focus dead surface.
        commandBus.dispatch(FocusSurfaceCommand(surfaceId: 'main'));

        await Future<void>.delayed(Duration.zero);

        expect(errors.length, 1);
        expect(errors.first.message, contains('not alive'));
      });

      test('rejects CreateSurfaceCommand for existing surface', () async {
        commandBus.dispatch(CreateSurfaceCommand(
          surfaceId: 'main',
          frame: Rect.fromLTWH(0, 0, 100, 100),
        ));

        // Duplicate create.
        commandBus.dispatch(CreateSurfaceCommand(
          surfaceId: 'main',
          frame: Rect.fromLTWH(0, 0, 200, 200),
        ));

        await Future<void>.delayed(Duration.zero);

        expect(errors.length, 1);
        expect(errors.first.message, contains('already exists'));
      });

      test('rejects MoveClusterCommand when cluster is terminated', () async {
        commandBus.dispatch(TerminateClusterCommand());
        commandBus.dispatch(MoveClusterCommand(delta: Offset(10, 10)));

        await Future<void>.delayed(Duration.zero);

        expect(errors.length, 1);
        expect(errors.first.message, contains('not operational'));
      });

      test('allows EnterDegradedCommand always (failure path)', () async {
        commandBus.dispatch(EnterDegradedCommand(
          lostSurfaceId: 'ghost',
          reason: 'crash',
        ));

        await Future<void>.delayed(Duration.zero);

        expect(errors, isEmpty);
      });
    });

    group('state broadcasting', () {
      test('broadcasts state on every successful dispatch', () async {
        commandBus.dispatch(CreateSurfaceCommand(
          surfaceId: 'main',
          frame: Rect.fromLTWH(0, 0, 100, 100),
        ));

        commandBus.dispatch(CreateSurfaceCommand(
          surfaceId: 'toolbar',
          frame: Rect.fromLTWH(0, 0, 100, 50),
        ));

        await Future<void>.delayed(Duration.zero);

        expect(states.length, 2);
        expect(states[0].surfaces.length, 1);
        expect(states[1].surfaces.length, 2);
      });

      test('does NOT broadcast on rejected command', () async {
        // This should be rejected (surface doesn't exist).
        commandBus.dispatch(FocusSurfaceCommand(surfaceId: 'ghost'));

        await Future<void>.delayed(Duration.zero);

        expect(states, isEmpty);
      });
    });

    group('version tracking', () {
      test('version increments monotonically', () {
        commandBus.dispatch(CreateSurfaceCommand(
          surfaceId: 'main',
          frame: Rect.fromLTWH(0, 0, 100, 100),
        ));
        expect(commandBus.state.version, 1);

        commandBus.dispatch(CreateSurfaceCommand(
          surfaceId: 'toolbar',
          frame: Rect.fromLTWH(0, 0, 100, 50),
        ));
        expect(commandBus.state.version, 2);

        commandBus.dispatch(FocusSurfaceCommand(surfaceId: 'main'));
        expect(commandBus.state.version, 3);
      });
    });
  });
}
