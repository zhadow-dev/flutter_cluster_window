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
    surfaces: [
      // Primary: Main editor area.
      ClusterSurface(
        id: 'editor',
        role: SurfaceRole.primary,
        size: const Size(900, 620),
        frameless: true,
        acrylicEffect: AcrylicEffect.acrylic,
        builder: () => const EditorWindowApp(),
      ),

      // Panel: Sidebar anchored to the left with an 8px gap.
      // Only width (200) matters; height auto-matches the primary.
      ClusterSurface(
        id: 'sidebar',
        role: SurfaceRole.panel,
        size: const Size(200, 0),
        anchor: const SurfaceAnchor.left(gap: 8),
        frameless: true,
        acrylicEffect: AcrylicEffect.acrylic,
        builder: () => const SidebarWindowApp(),
      ),

      // Chrome: Title bar anchored above the cluster with a 4px gap.
      // Only height (40) matters; width auto-spans sidebar + editor.
      ClusterSurface(
        id: 'titlebar',
        role: SurfaceRole.chrome,
        size: const Size(0, 40),
        anchor: const SurfaceAnchor.top(gap: 4, span: SpanMode.full),
        frameless: true,
        acrylicEffect: AcrylicEffect.acrylic,
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
        acrylicEffect: AcrylicEffect.acrylic,
        builder: () => const OverlayWindowApp(),
      ),
    ],
  );
}
