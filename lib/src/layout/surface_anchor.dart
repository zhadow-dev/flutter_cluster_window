import 'dart:ui';

/// Controls how a child window's auto-computed dimension spans.
///
/// For top/bottom anchors this controls the **width**;
/// for left/right anchors this controls the **height**.
enum SpanMode {
  /// Match only the primary window's dimension.
  primary,

  /// Span the full cluster extent including all side panels and gaps.
  full,
}

/// Describes how a child surface is positioned relative to the primary surface.
///
/// The [gap] parameter creates real transparent space between windows (the
/// desktop wallpaper is visible through it).
///
/// For top/bottom anchors the user specifies only height; width is
/// auto-computed. For left/right anchors the user specifies only width;
/// height is auto-computed.
///
/// ```dart
/// SurfaceAnchor.left(gap: 8)
/// SurfaceAnchor.top(gap: 4, span: SpanMode.full)
/// ```
sealed class SurfaceAnchor {
  const SurfaceAnchor();

  /// Anchors to the **left** of the primary surface.
  const factory SurfaceAnchor.left({
    double gap,
    double? verticalOffset,
    SpanMode span,
  }) = LeftSurfaceAnchor;

  /// Anchors to the **right** of the primary surface.
  const factory SurfaceAnchor.right({
    double gap,
    double? verticalOffset,
    SpanMode span,
  }) = RightSurfaceAnchor;

  /// Anchors **above** the primary surface.
  const factory SurfaceAnchor.top({
    double gap,
    SpanMode span,
  }) = TopSurfaceAnchor;

  /// Anchors **below** the primary surface.
  const factory SurfaceAnchor.bottom({
    double gap,
    SpanMode span,
  }) = BottomSurfaceAnchor;

  /// Places the surface at a fixed screen position (does not follow primary).
  const factory SurfaceAnchor.absolute(Offset position) = AbsoluteSurfaceAnchor;

  /// Computes the child's screen bounds given the primary's current bounds.
  ///
  /// [fixedDimension] is the user-specified fixed dimension (width for
  /// left/right, height for top/bottom), already scaled to physical pixels.
  /// [dpiScale] scales gaps and offsets when working in physical pixel space.
  Rect computeBounds(Rect primaryBounds, double fixedDimension, {
    double dpiScale = 1.0,
    double leftReservation = 0,
    double rightReservation = 0,
    double topReservation = 0,
    double bottomReservation = 0,
  });

  /// Returns the screen-edge reservation this anchor requires when the
  /// primary window is maximised.
  EdgeReservation computeReservation(double fixedDimension);

  /// The axis of the fixed dimension: `'width'` for left/right,
  /// `'height'` for top/bottom, `'both'` for absolute.
  String get fixedAxis;

  /// Serialises this anchor for inter-window transport.
  Map<String, dynamic> toJson();

  /// Deserialises a [SurfaceAnchor] from a JSON map.
  static SurfaceAnchor fromJson(Map<String, dynamic> map) {
    final type = map['type'] as String;
    return switch (type) {
      'left' => LeftSurfaceAnchor(
          gap: (map['gap'] as num?)?.toDouble() ?? 8,
          verticalOffset: (map['verticalOffset'] as num?)?.toDouble(),
          span: SpanMode.values.byName(map['span'] as String? ?? 'primary'),
        ),
      'right' => RightSurfaceAnchor(
          gap: (map['gap'] as num?)?.toDouble() ?? 8,
          verticalOffset: (map['verticalOffset'] as num?)?.toDouble(),
          span: SpanMode.values.byName(map['span'] as String? ?? 'primary'),
        ),
      'top' => TopSurfaceAnchor(
          gap: (map['gap'] as num?)?.toDouble() ?? 4,
          span: SpanMode.values.byName(map['span'] as String? ?? 'primary'),
        ),
      'bottom' => BottomSurfaceAnchor(
          gap: (map['gap'] as num?)?.toDouble() ?? 4,
          span: SpanMode.values.byName(map['span'] as String? ?? 'primary'),
        ),
      'absolute' => AbsoluteSurfaceAnchor(Offset(
          (map['x'] as num?)?.toDouble() ?? 0,
          (map['y'] as num?)?.toDouble() ?? 0,
        )),
      _ => throw ArgumentError('Unknown anchor type: $type'),
    };
  }
}

/// Describes how much space an anchor reserves from each screen edge.
class EdgeReservation {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const EdgeReservation({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  static const zero = EdgeReservation();

  @override
  String toString() =>
      'EdgeReservation(L:$left T:$top R:$right B:$bottom)';
}

// ---------------------------------------------------------------------------
// Left anchor
// ---------------------------------------------------------------------------

/// Positions a child to the left of the primary surface.
class LeftSurfaceAnchor extends SurfaceAnchor {
  const LeftSurfaceAnchor({
    this.gap = 8,
    this.verticalOffset,
    this.span = SpanMode.primary,
  });

  /// Gap in logical pixels between this surface and the primary surface.
  final double gap;

  /// Optional vertical offset from the primary surface's top edge.
  final double? verticalOffset;

  /// Controls height computation: [SpanMode.primary] matches the primary
  /// window's height; [SpanMode.full] spans the full cluster height.
  final SpanMode span;

  @override
  String get fixedAxis => 'width';

  @override
  Rect computeBounds(Rect primaryBounds, double fixedDimension, {
    double dpiScale = 1.0,
    double leftReservation = 0,
    double rightReservation = 0,
    double topReservation = 0,
    double bottomReservation = 0,
  }) {
    final g = gap * dpiScale;
    final w = fixedDimension;
    final x = primaryBounds.left - w - g;

    double y;
    double h;
    if (span == SpanMode.full) {
      y = primaryBounds.top - topReservation;
      h = primaryBounds.height + topReservation + bottomReservation;
    } else {
      y = verticalOffset != null
          ? primaryBounds.top + verticalOffset! * dpiScale
          : primaryBounds.top;
      h = primaryBounds.height;
    }
    return Rect.fromLTWH(x, y, w, h);
  }

  @override
  EdgeReservation computeReservation(double fixedDimension) =>
      EdgeReservation(left: fixedDimension + gap);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'left',
        'gap': gap,
        'verticalOffset': verticalOffset,
        'span': span.name,
      };
}

// ---------------------------------------------------------------------------
// Right anchor
// ---------------------------------------------------------------------------

/// Positions a child to the right of the primary surface.
class RightSurfaceAnchor extends SurfaceAnchor {
  const RightSurfaceAnchor({
    this.gap = 8,
    this.verticalOffset,
    this.span = SpanMode.primary,
  });

  final double gap;
  final double? verticalOffset;

  /// Controls height computation (see [LeftSurfaceAnchor.span]).
  final SpanMode span;

  @override
  String get fixedAxis => 'width';

  @override
  Rect computeBounds(Rect primaryBounds, double fixedDimension, {
    double dpiScale = 1.0,
    double leftReservation = 0,
    double rightReservation = 0,
    double topReservation = 0,
    double bottomReservation = 0,
  }) {
    final g = gap * dpiScale;
    final w = fixedDimension;
    final x = primaryBounds.right + g;

    double y;
    double h;
    if (span == SpanMode.full) {
      y = primaryBounds.top - topReservation;
      h = primaryBounds.height + topReservation + bottomReservation;
    } else {
      y = verticalOffset != null
          ? primaryBounds.top + verticalOffset! * dpiScale
          : primaryBounds.top;
      h = primaryBounds.height;
    }
    return Rect.fromLTWH(x, y, w, h);
  }

  @override
  EdgeReservation computeReservation(double fixedDimension) =>
      EdgeReservation(right: fixedDimension + gap);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'right',
        'gap': gap,
        'verticalOffset': verticalOffset,
        'span': span.name,
      };
}

// ---------------------------------------------------------------------------
// Top anchor
// ---------------------------------------------------------------------------

/// Positions a child above the primary surface.
class TopSurfaceAnchor extends SurfaceAnchor {
  const TopSurfaceAnchor({
    this.gap = 4,
    this.span = SpanMode.full,
  });

  final double gap;

  /// Controls width computation: [SpanMode.primary] matches primary width;
  /// [SpanMode.full] spans the full cluster width.
  final SpanMode span;

  @override
  String get fixedAxis => 'height';

  @override
  Rect computeBounds(Rect primaryBounds, double fixedDimension, {
    double dpiScale = 1.0,
    double leftReservation = 0,
    double rightReservation = 0,
    double topReservation = 0,
    double bottomReservation = 0,
  }) {
    final g = gap * dpiScale;
    final h = fixedDimension;
    final y = primaryBounds.top - h - g;

    double x;
    double w;
    if (span == SpanMode.full) {
      x = primaryBounds.left - leftReservation;
      w = primaryBounds.width + leftReservation + rightReservation;
    } else {
      x = primaryBounds.left;
      w = primaryBounds.width;
    }
    return Rect.fromLTWH(x, y, w, h);
  }

  @override
  EdgeReservation computeReservation(double fixedDimension) =>
      EdgeReservation(top: fixedDimension + gap);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'top',
        'gap': gap,
        'span': span.name,
      };
}

// ---------------------------------------------------------------------------
// Bottom anchor
// ---------------------------------------------------------------------------

/// Positions a child below the primary surface.
class BottomSurfaceAnchor extends SurfaceAnchor {
  const BottomSurfaceAnchor({
    this.gap = 4,
    this.span = SpanMode.full,
  });

  final double gap;

  /// Controls width computation (see [TopSurfaceAnchor.span]).
  final SpanMode span;

  @override
  String get fixedAxis => 'height';

  @override
  Rect computeBounds(Rect primaryBounds, double fixedDimension, {
    double dpiScale = 1.0,
    double leftReservation = 0,
    double rightReservation = 0,
    double topReservation = 0,
    double bottomReservation = 0,
  }) {
    final g = gap * dpiScale;
    final h = fixedDimension;
    final y = primaryBounds.bottom + g;

    double x;
    double w;
    if (span == SpanMode.full) {
      x = primaryBounds.left - leftReservation;
      w = primaryBounds.width + leftReservation + rightReservation;
    } else {
      x = primaryBounds.left;
      w = primaryBounds.width;
    }
    return Rect.fromLTWH(x, y, w, h);
  }

  @override
  EdgeReservation computeReservation(double fixedDimension) =>
      EdgeReservation(bottom: fixedDimension + gap);

  @override
  Map<String, dynamic> toJson() => {
        'type': 'bottom',
        'gap': gap,
        'span': span.name,
      };
}

// ---------------------------------------------------------------------------
// Absolute anchor (for overlays)
// ---------------------------------------------------------------------------

/// Positions a surface at a fixed screen coordinate, independent of the
/// primary surface.
class AbsoluteSurfaceAnchor extends SurfaceAnchor {
  const AbsoluteSurfaceAnchor(this.position);

  /// Fixed screen position in logical pixels.
  final Offset position;

  @override
  String get fixedAxis => 'both';

  @override
  Rect computeBounds(Rect primaryBounds, double fixedDimension, {
    double dpiScale = 1.0,
    double leftReservation = 0,
    double rightReservation = 0,
    double topReservation = 0,
    double bottomReservation = 0,
  }) {
    return Rect.fromLTWH(
      position.dx * dpiScale,
      position.dy * dpiScale,
      fixedDimension,
      fixedDimension,
    );
  }

  @override
  EdgeReservation computeReservation(double fixedDimension) =>
      EdgeReservation.zero;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'absolute',
        'x': position.dx,
        'y': position.dy,
      };
}
