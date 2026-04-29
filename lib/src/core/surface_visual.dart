import 'surface_role.dart';

/// Rendering contract for a single surface.
///
/// Defines how a surface appears visually — its backdrop effect, stacking
/// layer, and corner style.
///
/// **Shadow is NOT here.** Shadow is a cluster-level decision managed by
/// [ClusterVisualConfig]. Putting it per-surface would allow illegal states
/// (e.g. two surfaces both claiming shadow ownership).
class SurfaceVisual {
  /// DWM backdrop effect applied to this surface's HWND.
  final BackdropType backdrop;

  /// Stacking layer within the cluster.
  /// Maps deterministically to OS z-order.
  final SurfaceLayer layer;

  /// DWM corner rounding style.
  final CornerStyle cornerStyle;

  const SurfaceVisual({
    this.backdrop = BackdropType.none,
    this.layer = SurfaceLayer.base,
    this.cornerStyle = CornerStyle.round,
  });

  /// Sensible defaults per role.
  factory SurfaceVisual.forRole(SurfaceRole role) => switch (role) {
        SurfaceRole.primary => const SurfaceVisual(layer: SurfaceLayer.base),
        SurfaceRole.panel => const SurfaceVisual(layer: SurfaceLayer.panel),
        SurfaceRole.chrome => const SurfaceVisual(layer: SurfaceLayer.chrome),
        SurfaceRole.overlay => const SurfaceVisual(layer: SurfaceLayer.overlay),
      };

  /// Serialises this visual to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'backdrop': backdrop.name,
        'layer': layer.name,
        'cornerStyle': cornerStyle.name,
      };

  /// Deserialises a [SurfaceVisual] from a JSON map.
  factory SurfaceVisual.fromJson(Map<String, dynamic> json) {
    return SurfaceVisual(
      backdrop: BackdropType.values.byName(
          json['backdrop'] as String? ?? 'none'),
      layer: SurfaceLayer.values.byName(
          json['layer'] as String? ?? 'base'),
      cornerStyle: CornerStyle.values.byName(
          json['cornerStyle'] as String? ?? 'round'),
    );
  }
}

/// DWM backdrop type applied at the OS level.
enum BackdropType {
  /// No backdrop effect.
  none,

  /// Windows Acrylic blur (blurs content behind the window).
  acrylic,

  /// Windows Mica effect (subtle, performance-friendly).
  mica,

  /// Windows Tabbed effect (Mica variant for tabbed interfaces).
  tabbed,

  /// Fully transparent window (no blur, no tint).
  transparent,
}

/// DWM window corner rounding style.
enum CornerStyle {
  /// No rounding (sharp corners).
  none,

  /// Standard rounded corners.
  round,

  /// Smaller rounded corners.
  roundSmall,
}

/// Stacking layer within a cluster.
///
/// Determines OS z-order position. Chrome sits ABOVE panels because
/// the titlebar must always be above the sidebar.
///
/// Overlay has the highest z-order but is independent from the cluster
/// z-order stack (managed separately).
enum SurfaceLayer implements Comparable<SurfaceLayer> {
  /// Primary content window. Always at the bottom of the stack.
  base(0),

  /// Side panels (sidebar, file tree). Above base.
  panel(1),

  /// Window chrome (title bar, toolbar). Above panels.
  chrome(2),

  /// Free-floating overlay. Independent lifecycle. Highest z-order.
  overlay(10);

  /// Numeric z-order value used for deterministic sorting.
  final int zOrder;
  const SurfaceLayer(this.zOrder);

  @override
  int compareTo(SurfaceLayer other) => zOrder.compareTo(other.zOrder);
}
