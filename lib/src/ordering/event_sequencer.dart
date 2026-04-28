import '../core/events.dart';

/// Buffered event sequencer that guarantees strict in-order processing.
///
/// Native events may arrive out of order. This sequencer buffers
/// out-of-order events and releases them only when the sequence is
/// contiguous. For example, if events 1, 2, 4 arrive, event 4 is held
/// until event 3 arrives — then 3 and 4 are released together.
class EventSequencer {
  int _expected;
  final Map<int, NativeEvent> _buffer = {};

  /// Maximum buffer size before a forced flush to prevent memory leaks.
  final int maxBufferSize;

  /// How long to wait for a missing event before skipping the gap.
  final Duration gapTimeout;

  DateTime? _lastGapDetected;

  EventSequencer({
    int startSequence = 1,
    this.maxBufferSize = 100,
    this.gapTimeout = const Duration(milliseconds: 500),
  }) : _expected = startSequence;

  /// The next expected sequence ID.
  int get expected => _expected;

  /// Number of events currently buffered (waiting for gaps to fill).
  int get bufferedCount => _buffer.length;

  /// Pushes an event into the sequencer.
  ///
  /// Returns a list of events ready for processing, in order. May return
  /// an empty list if the event fills a gap that isn't yet complete, or
  /// multiple events if a gap was just filled.
  List<NativeEvent> push(NativeEvent event) {
    if (event.sequenceId < _expected) return const [];
    if (_buffer.containsKey(event.sequenceId)) return const [];

    _buffer[event.sequenceId] = event;

    final ready = <NativeEvent>[];
    while (_buffer.containsKey(_expected)) {
      ready.add(_buffer.remove(_expected)!);
      _expected++;
    }

    if (ready.isNotEmpty) {
      _lastGapDetected = null;
    } else if (_buffer.isNotEmpty) {
      _lastGapDetected ??= DateTime.now();
    }

    return ready;
  }

  /// Force-flushes buffered events when the gap has persisted too long
  /// or the buffer exceeds [maxBufferSize].
  ///
  /// Should be called periodically (e.g. from the scheduler tick).
  List<NativeEvent> forceFlushIfNeeded() {
    if (_buffer.isEmpty) return const [];

    final shouldFlush = _buffer.length >= maxBufferSize ||
        (_lastGapDetected != null &&
            DateTime.now().difference(_lastGapDetected!) > gapTimeout);

    if (!shouldFlush) return const [];

    final sortedKeys = _buffer.keys.toList()..sort();
    _expected = sortedKeys.first;

    final ready = <NativeEvent>[];
    while (_buffer.containsKey(_expected)) {
      ready.add(_buffer.remove(_expected)!);
      _expected++;
    }

    _lastGapDetected = _buffer.isNotEmpty ? DateTime.now() : null;
    return ready;
  }

  /// Resets the sequencer state (e.g. during cluster restart).
  void reset({int startSequence = 1}) {
    _expected = startSequence;
    _buffer.clear();
    _lastGapDetected = null;
  }
}
