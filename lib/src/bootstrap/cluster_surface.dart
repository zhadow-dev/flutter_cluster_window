import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/surface_role.dart';
import '../core/surface_visual.dart';
import '../layout/surface_anchor.dart';

/// Declarative definition of a single surface (OS window) in the cluster.
///
/// Each surface describes its layout, visual contract, and the widget tree
/// to render inside the window.
class ClusterSurface {
  /// Unique identifier for this surface within the cluster.
  final String id;

  /// The role this surface plays (primary, panel, chrome, or overlay).
  final SurfaceRole role;

  /// Logical size of the window. For anchored surfaces, only the fixed
  /// dimension matters (width for left/right, height for top/bottom).
  final Size size;

  /// Positioning strategy relative to the primary surface.
  /// If `null`, the surface uses an absolute position.
  final SurfaceAnchor? anchor;

  /// Whether the window should have no OS-drawn title bar or border.
  final bool frameless;

  /// Visual rendering contract for this surface.
  ///
  /// Controls backdrop effect, stacking layer, and corner style.
  /// Shadow is NOT here — it is a cluster-level decision managed by
  /// [ClusterVisualConfig].
  final SurfaceVisual visual;

  /// Factory that builds the widget tree rendered inside this window.
  final Widget Function() builder;

  /// When `true`, showing this overlay minimises the rest of the cluster.
  /// When `false`, the overlay appears alongside the cluster.
  final bool hideClusterOnShow;

  /// When `true`, the window shrinks to fit its content size after the
  /// first frame.  The [size] field acts as the **maximum** constraint.
  ///
  /// Useful for toolbars, status bars, or overlays whose height/width
  /// depends on content rather than a fixed value.
  final bool shrinkToContent;

  /// Alignment of this surface relative to the primary surface after
  /// shrink-to-content resizing.
  ///
  /// Only meaningful when [shrinkToContent] is `true`.  For example,
  /// `Alignment.center` centres a right-anchored panel vertically
  /// against the primary window.  When `null`, the window keeps its
  /// default anchor-computed position (top-aligned).
  final Alignment? contentAlignment;

  ClusterSurface({
    required this.id,
    required this.role,
    required this.size,
    this.anchor,
    this.frameless = true,
    SurfaceVisual? visual,
    this.hideClusterOnShow = true,
    this.shrinkToContent = false,
    this.contentAlignment,
    required this.builder,
  }) : visual = visual ?? SurfaceVisual.forRole(role);

  /// Whether this surface has the [SurfaceRole.primary] role.
  bool get isPrimary => role == SurfaceRole.primary;

  /// Serialises this surface's configuration to JSON (excluding [builder]).
  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'width': size.width,
        'height': size.height,
        'anchor': anchor?.toJson(),
        'frameless': frameless,
        'visual': visual.toJson(),
        'shrinkToContent': shrinkToContent,
        'contentAlignmentX': contentAlignment?.x,
        'contentAlignmentY': contentAlignment?.y,
      };

  /// Encodes this surface's configuration as a JSON string for
  /// inter-window transport.
  String encode() => jsonEncode(toJson());

  /// Decodes a [ClusterSurface] from a JSON string and a [builder] callback.
  static ClusterSurface decode(String json, Widget Function() builder) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final alignX = (map['contentAlignmentX'] as num?)?.toDouble();
    final alignY = (map['contentAlignmentY'] as num?)?.toDouble();

    // Decode visual from nested map, or fall back to role-based default.
    SurfaceVisual? visual;
    if (map['visual'] != null) {
      visual = SurfaceVisual.fromJson(map['visual'] as Map<String, dynamic>);
    }

    return ClusterSurface(
      id: map['id'] as String,
      role: SurfaceRole.values.byName(map['role'] as String),
      size: Size(
        (map['width'] as num).toDouble(),
        (map['height'] as num).toDouble(),
      ),
      anchor: map['anchor'] != null
          ? SurfaceAnchor.fromJson(map['anchor'] as Map<String, dynamic>)
          : null,
      frameless: map['frameless'] as bool? ?? true,
      visual: visual,
      shrinkToContent: map['shrinkToContent'] as bool? ?? false,
      contentAlignment: alignX != null && alignY != null
          ? Alignment(alignX, alignY)
          : null,
      builder: builder,
    );
  }
}
