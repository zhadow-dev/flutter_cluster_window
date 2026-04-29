import 'package:flutter/material.dart';
import 'package:flutter_cluster_window/flutter_cluster_window.dart';

import 'windows/editor_window.dart';
import 'windows/overlay_window.dart';
import 'windows/sidebar_window.dart';
import 'windows/titlebar_window.dart';

/// Example app demonstrating a detached workspace IDE with real OS windows.
void main(List<String> args) {
  ClusterApp.run(
    args: args,
    clusterId: 'ide',
    visualConfig: const ClusterVisualConfig(
      shadowOwnerId: 'editor', // ONLY editor casts DWM shadow.
      allowOverlayShadow: true,
    ),
    surfaces: [
      // Primary: Main editor area.
      ClusterSurface(
        id: 'editor',
        role: SurfaceRole.primary,
        size: const Size(900, 620),
        frameless: true,
        visual: const SurfaceVisual(
          backdrop: BackdropType.acrylic,
          layer: SurfaceLayer.base,
        ),
        builder: () => const EditorWindowApp(),
      ),

      // Panel: Compact nav bar anchored to the left.
      // Shrinks to fit the 3 icon buttons; centred vertically against
      // the primary window with an 8px gap.
      ClusterSurface(
        id: 'sidebar',
        role: SurfaceRole.panel,
        size: const Size(60, 300),
        anchor: const SurfaceAnchor.left(gap: 8),
        frameless: true,
        visual: const SurfaceVisual(
          backdrop: BackdropType.acrylic,
          layer: SurfaceLayer.panel,
        ),
        shrinkToContent: true,
        contentAlignment: Alignment.center,
        builder: () => const SidebarWindowApp(),
      ),

      // Chrome: Title bar anchored above the cluster with a 4px gap.
      // Only height (40) matters; width auto-spans sidebar + editor.
      ClusterSurface(
        id: 'titlebar',
        role: SurfaceRole.chrome,
        size: const Size(0, 40),
        anchor: const SurfaceAnchor.top(gap: 0, span: SpanMode.primary),
        frameless: true,
        visual: const SurfaceVisual(
          backdrop: BackdropType.acrylic,
          layer: SurfaceLayer.chrome,
        ),
        builder: () => const TitleBarWindowApp(),
      ),

      // Overlay: Floating mini-player (Teams-like).
      // Minimises the cluster when shown.
      ClusterSurface(
        id: 'overlay',
        role: SurfaceRole.overlay,
        size: const Size(320, 200),
        anchor: const SurfaceAnchor.absolute(Offset(100, 100)),
        frameless: true,
        hideClusterOnShow: true,
        visual: const SurfaceVisual(
          backdrop: BackdropType.acrylic,
          layer: SurfaceLayer.overlay,
        ),
        builder: () => const OverlayWindowApp(),
      ),
    ],
  );
}
