import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cluster_window/src/ordering/event_sequencer.dart';
import 'package:flutter_cluster_window/src/core/events.dart';

/// Helper to create a WindowMovedEvent with a given sequenceId.
WindowMovedEvent _movedEvent(int seq) => WindowMovedEvent(
      sequenceId: seq,
      surfaceId: 'main',
      actualFrame: Rect.fromLTWH(0, 0, 100, 100),
      source: NativeEventSource.system,
    );

void main() {
  late EventSequencer sequencer;

  setUp(() {
    sequencer = EventSequencer();
  });

  group('EventSequencer (buffered)', () {
    test('processes events in order', () {
      final r1 = sequencer.push(_movedEvent(1));
      final r2 = sequencer.push(_movedEvent(2));
      final r3 = sequencer.push(_movedEvent(3));

      expect(r1.length, 1);
      expect(r2.length, 1);
      expect(r3.length, 1);
      expect(r1.first.sequenceId, 1);
      expect(r2.first.sequenceId, 2);
      expect(r3.first.sequenceId, 3);
    });

    test('buffers out-of-order events and releases when gap fills', () {
      // Events arrive: 1, 2, 4, 3
      final r1 = sequencer.push(_movedEvent(1));
      final r2 = sequencer.push(_movedEvent(2));
      final r4 = sequencer.push(_movedEvent(4)); // Gap: missing 3
      final r3 = sequencer.push(_movedEvent(3)); // Fills gap

      expect(r1.length, 1);
      expect(r2.length, 1);
      expect(r4.length, 0); // Buffered, not released
      expect(r3.length, 2); // Releases 3 AND 4
      expect(r3[0].sequenceId, 3);
      expect(r3[1].sequenceId, 4);
    });

    test('drops duplicate events (already processed)', () {
      sequencer.push(_movedEvent(1));
      sequencer.push(_movedEvent(2));

      // Duplicate of already-processed event.
      final dup = sequencer.push(_movedEvent(1));
      expect(dup.length, 0);
    });

    test('drops duplicate events (buffered)', () {
      sequencer.push(_movedEvent(1));
      sequencer.push(_movedEvent(3)); // Buffered

      // Duplicate of buffered event.
      final dup = sequencer.push(_movedEvent(3));
      expect(dup.length, 0);
    });

    test('handles large gap with force-flush', () {
      sequencer = EventSequencer(maxBufferSize: 3);

      sequencer.push(_movedEvent(1));
      // Skip 2, buffer 3,4,5 (exceeds maxBufferSize=3)
      sequencer.push(_movedEvent(3));
      sequencer.push(_movedEvent(4));
      sequencer.push(_movedEvent(5));

      final flushed = sequencer.forceFlushIfNeeded();
      expect(flushed.length, 3); // 3,4,5 force-flushed
      expect(flushed[0].sequenceId, 3);
      expect(flushed[1].sequenceId, 4);
      expect(flushed[2].sequenceId, 5);
    });

    test('reset clears all state', () {
      sequencer.push(_movedEvent(1));
      sequencer.push(_movedEvent(3)); // Buffered

      sequencer.reset();

      expect(sequencer.expected, 1);
      expect(sequencer.bufferedCount, 0);
    });

    test('bufferedCount is accurate', () {
      sequencer.push(_movedEvent(1));
      expect(sequencer.bufferedCount, 0);

      sequencer.push(_movedEvent(3)); // Gap
      expect(sequencer.bufferedCount, 1);

      sequencer.push(_movedEvent(5)); // Another gap
      expect(sequencer.bufferedCount, 2);

      sequencer.push(_movedEvent(2)); // Fills first gap → releases 2,3
      expect(sequencer.bufferedCount, 1); // Only 5 remains
    });
  });
}
