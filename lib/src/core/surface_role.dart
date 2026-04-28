/// Role that each surface plays within the cluster.
///
/// Determines focus routing, resize authority, z-order rules,
/// and lifecycle dependencies.
enum SurfaceRole {
  /// Main content window and source of truth for layout.
  /// Receives keyboard input by default.
  primary,

  /// Window chrome (title bar, toolbar). Does not receive keyboard focus;
  /// click events forward focus to the primary surface.
  chrome,

  /// Side panel (sidebar, file tree). Accepts mouse input but keyboard
  /// focus stays with primary unless explicitly requested.
  panel,

  /// Free-floating overlay (e.g. floating timer). Has an independent
  /// lifecycle and always renders on top.
  overlay,
}
