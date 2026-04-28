import 'dart:ui' show Rect;

import '../core/cluster_state.dart';

/// Computes absolute positions for all surfaces based on relative offsets
/// from the primary surface.
///
/// Currently uses simple dx/dy offsets. A constraint-based DSL may be
/// introduced in a future version.
class LayoutEngine {
  /// Computes the layout for all alive surfaces.
  ///
  /// [primarySurfaceId] is the anchor surface; all others are positioned
  /// relative to it using the provided [offsets].
  ///
  /// Returns a map of `surfaceId → computed Rect`, or an empty map if
  /// the primary surface doesn't exist or the cluster has fewer than
  /// two surfaces.
  Map<String, Rect> computeLayout({
    required ClusterState state,
    required String primarySurfaceId,
    required Map<String, SurfaceOffset> offsets,
  }) {
    final primary = state.surfaces[primarySurfaceId];
    if (primary == null || !primary.isAlive) return {};

    final result = <String, Rect>{primarySurfaceId: primary.frame};

    for (final entry in offsets.entries) {
      final id = entry.key;
      if (id == primarySurfaceId) continue;

      final surface = state.surfaces[id];
      if (surface == null || !surface.isAlive) continue;

      final offset = entry.value;

      result[id] = Rect.fromLTWH(
        primary.frame.left + offset.dx,
        primary.frame.top + offset.dy,
        offset.width ?? surface.frame.width,
        offset.height ?? surface.frame.height,
      );
    }

    return result;
  }
}

/// Relative offset of a surface from the primary surface.
class SurfaceOffset {
  /// Horizontal offset from the primary surface's left edge.
  final double dx;

  /// Vertical offset from the primary surface's top edge.
  final double dy;

  /// Optional override for the surface width.
  final double? width;

  /// Optional override for the surface height.
  final double? height;

  const SurfaceOffset({
    required this.dx,
    required this.dy,
    this.width,
    this.height,
  });

  @override
  String toString() =>
      'SurfaceOffset(dx: $dx, dy: $dy, w: $width, h: $height)';
}
