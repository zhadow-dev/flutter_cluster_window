import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../core/surface_role.dart';
import '../layout/surface_anchor.dart';
import 'cluster_app.dart';

/// Declarative definition of a single surface (OS window) in the cluster.
///
/// Each surface describes its layout, visual style, and the widget tree
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

  /// DWM backdrop effect (acrylic, mica, etc.) applied to this window.
  final AcrylicEffect acrylicEffect;

  /// Factory that builds the widget tree rendered inside this window.
  final Widget Function() builder;

  /// When `true`, showing this overlay minimises the rest of the cluster.
  /// When `false`, the overlay appears alongside the cluster.
  final bool hideClusterOnShow;

  const ClusterSurface({
    required this.id,
    required this.role,
    required this.size,
    this.anchor,
    this.frameless = true,
    this.acrylicEffect = AcrylicEffect.none,
    this.hideClusterOnShow = true,
    required this.builder,
  });

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
        'acrylicEffect': acrylicEffect.name,
      };

  /// Encodes this surface's configuration as a JSON string for
  /// inter-window transport.
  String encode() => jsonEncode(toJson());

  /// Decodes a [ClusterSurface] from a JSON string and a [builder] callback.
  static ClusterSurface decode(String json, Widget Function() builder) {
    final map = jsonDecode(json) as Map<String, dynamic>;
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
      acrylicEffect: AcrylicEffect.values.byName(
          map['acrylicEffect'] as String? ?? 'none'),
      builder: builder,
    );
  }
}
