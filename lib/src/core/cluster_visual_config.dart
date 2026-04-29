/// Cluster-wide visual rendering policy.
///
/// Properties that span the entire cluster live here — not on individual
/// surfaces. This makes illegal states unrepresentable.
///
/// Example: shadow ownership. If it were per-surface, two surfaces could
/// both claim `castsShadow: true`, violating the "one shadow" rule.
class ClusterVisualConfig {
  /// The surface ID that is allowed to cast a DWM shadow.
  ///
  /// All other cluster surfaces have shadow forcefully removed.
  /// This is enforced continuously (not just at boot) via
  /// [enforceShadowPolicy].
  final String shadowOwnerId;

  /// Whether overlay windows (independent lifecycle) may cast
  /// their own shadow.
  ///
  /// Overlays are not cluster surfaces, so this does not conflict
  /// with [shadowOwnerId].
  final bool allowOverlayShadow;

  /// Controls how overlay windows interact with the cluster
  /// regarding focus and input routing.
  final OverlayPolicy overlayPolicy;

  const ClusterVisualConfig({
    required this.shadowOwnerId,
    this.allowOverlayShadow = true,
    this.overlayPolicy = const OverlayPolicy(),
  });
}

/// Defines how overlays interact with the cluster.
///
/// Overlays are independent windows (Option B) — they have separate
/// z-order, shadow, and lifecycle. This policy controls the boundary
/// between overlay and cluster.
class OverlayPolicy {
  /// Whether activating the overlay steals OS focus from the cluster.
  ///
  /// When `false`, the overlay is shown with `SWP_NOACTIVATE` /
  /// `SW_SHOWNA` so the cluster retains focus.
  final bool stealsFocus;

  /// Whether the overlay blocks mouse/keyboard interaction with
  /// cluster surfaces while visible.
  final bool blocksClusterInteraction;

  const OverlayPolicy({
    this.stealsFocus = true,
    this.blocksClusterInteraction = true,
  });
}
