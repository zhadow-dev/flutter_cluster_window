# flutter_cluster_window

[![pub package](https://img.shields.io/pub/v/flutter_cluster_window.svg)](https://pub.dev/packages/flutter_cluster_window)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)

**Deterministic multi-window cluster runtime for Flutter Desktop (Windows).**

Treat multiple OS windows as a single, synchronized application — sidebars, title bars, floating overlays — all moving, minimizing, and restoring together with native DWM acrylic/mica effects.

<p align="center">
  <img src="https://raw.githubusercontent.com/user/flutter_cluster_window/main/doc/images/cluster_hero.png" alt="Cluster layout example" width="720" />
</p>

---

## ✨ Features

- **Declarative surface definitions** — describe your windows in a single `ClusterApp.run()` call
- **Anchor-based layout** — position panels relative to the primary window (`left`, `right`, `top`, `bottom`) with configurable gaps
- **Synchronized lifecycle** — minimize, restore, close, and drag the entire cluster as one unit
- **Floating overlays** — Teams-like mini windows that optionally hide the cluster when shown
- **Native DWM effects** — acrylic, mica, and transparent backdrop effects per window
- **Frameless windows** — borderless OS windows with rounded corners
- **Pre-built widgets** — drop-in `ClusterDragArea`, `ClusterWindowControls`, `ClusterOverlayButton` widgets
- **Shrink to content** — optional per-window auto-sizing that measures widget content and shrinks the OS window to fit
- **DPI-aware** — correct physical-pixel positioning across high-DPI displays

---

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_cluster_window: ^0.0.1
```

Then run:

```bash
flutter pub get
```

> **Platform support:** Windows only. macOS and Linux support is planned for future releases.

---

## 🚀 Quick Start

### 1. Define your cluster

Each window in the cluster is a **surface** with a role, size, anchor position, and builder function.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_cluster_window/flutter_cluster_window.dart';

void main(List<String> args) {
  ClusterApp.run(
    args: args,   // Required — passes child window arguments
    clusterId: 'my_app',
    surfaces: [
      // Primary window (required, exactly one)
      ClusterSurface(
        id: 'main',
        role: SurfaceRole.primary,
        size: const Size(900, 620),
        frameless: true,
        acrylicEffect: AcrylicEffect.acrylic,
        builder: () => const MainWindowApp(),
      ),

      // Sidebar anchored to the left
      ClusterSurface(
        id: 'sidebar',
        role: SurfaceRole.panel,
        size: const Size(220, 0),  // Only width matters; height auto-matches
        anchor: const SurfaceAnchor.left(gap: 8),
        frameless: true,
        acrylicEffect: AcrylicEffect.acrylic,
        builder: () => const SidebarApp(),
      ),

      // Title bar spanning the full cluster width
      ClusterSurface(
        id: 'titlebar',
        role: SurfaceRole.chrome,
        size: const Size(0, 40),  // Only height matters; width auto-spans
        anchor: const SurfaceAnchor.top(gap: 4, span: SpanMode.full),
        frameless: true,
        acrylicEffect: AcrylicEffect.acrylic,
        builder: () => const TitleBarApp(),
      ),
    ],
  );
}
```

### 2. Add drag & window controls

Use the built-in widgets in any window to control the entire cluster:

```dart
// In your title bar window:
Row(
  children: [
    const Text('My App'),
    const Expanded(child: ClusterDragArea(height: 40)),
    const ClusterWindowControls(),  // minimize + maximize + close
  ],
)
```

### 3. Add a floating overlay (optional)

Create a Teams-like floating window that hides the cluster when shown:

```dart
// In your surface definitions:
ClusterSurface(
  id: 'overlay',
  role: SurfaceRole.overlay,
  size: const Size(320, 200),
  anchor: const SurfaceAnchor.absolute(Offset(100, 100)),
  frameless: true,
  hideClusterOnShow: true,
  builder: () => const FloatingTimerApp(),
),

// In any window — toggle button:
const ClusterOverlayButton(label: 'Show Timer')

// Inside the overlay — dismiss button:
const ClusterOverlayDismiss()
```

---

## 🧩 Surface Roles

| Role | Description | Focus | Anchor |
|------|-------------|-------|--------|
| `primary` | Main content window. Source of truth for layout. | Receives keyboard input | N/A (origin) |
| `panel` | Side panels (sidebar, file tree, properties). | Mouse input; keyboard stays with primary | `left`, `right` |
| `chrome` | Window chrome (title bar, toolbar, status bar). | No focus; clicks forward to primary | `top`, `bottom` |
| `overlay` | Floating mini-window (timer, PiP, HUD). | Independent lifecycle | `absolute` |

---

## ⚓ Anchor System

Surfaces are positioned relative to the primary window using anchors. The gap creates real transparent space between windows — your desktop wallpaper is visible through it.

```dart
// Left of primary, 8px gap
SurfaceAnchor.left(gap: 8)

// Right of primary, 12px gap
SurfaceAnchor.right(gap: 12)

// Above entire cluster (full span)
SurfaceAnchor.top(gap: 4, span: SpanMode.full)

// Below primary only
SurfaceAnchor.bottom(gap: 4, span: SpanMode.primary)

// Fixed screen position (for overlays)
SurfaceAnchor.absolute(Offset(100, 100))
```

### Span modes

- **`SpanMode.primary`** — width/height matches only the primary window
- **`SpanMode.full`** — spans the entire cluster including all panels and gaps

### Auto-sizing

For anchored surfaces, only the **fixed dimension** matters:

| Anchor | You specify | Auto-computed |
|--------|-------------|---------------|
| `left` / `right` | Width | Height (matches primary) |
| `top` / `bottom` | Height | Width (matches span) |

### Shrink to content

When `shrinkToContent: true` is set on a surface, the window measures its widget content after the first frame and resizes the OS window to fit. The `size` field acts as the **maximum constraint** — the window will never exceed it but can shrink smaller.

```dart
// A toolbar that shrinks to its actual button height:
ClusterSurface(
  id: 'toolbar',
  role: SurfaceRole.chrome,
  size: const Size(0, 60),       // max height = 60px
  anchor: const SurfaceAnchor.top(gap: 2, span: SpanMode.full),
  shrinkToContent: true,          // ← shrinks height to content
  frameless: true,
  builder: () => const ToolbarApp(),
),

// An overlay that wraps to its content size:
ClusterSurface(
  id: 'hud',
  role: SurfaceRole.overlay,
  size: const Size(400, 300),    // max size = 400×300
  anchor: const SurfaceAnchor.absolute(Offset(50, 50)),
  shrinkToContent: true,          // ← shrinks both dimensions
  frameless: true,
  builder: () => const HudApp(),
),
```

> **How it works:** After the first frame, the wrapper measures the child `RenderBox` size, clamps it against `size`, and calls native `SetWindowPos` to resize the OS window. This happens once on initial render.

---

## 🎨 Visual Effects

Each window supports independent DWM backdrop effects:

```dart
ClusterSurface(
  acrylicEffect: AcrylicEffect.acrylic,     // Frosted glass
  // AcrylicEffect.mica,                     // Windows 11 Mica
  // AcrylicEffect.transparent,              // Fully transparent
  // AcrylicEffect.solid,                    // Solid dark background
  // AcrylicEffect.none,                     // No effect (default)
)
```

> **Note:** Acrylic and Mica effects require Windows 10 build 1903+ and Windows 11 respectively.

---

## 🔧 Widgets Reference

### ClusterDragArea

Makes a region draggable — dragging moves the entire cluster.

```dart
ClusterDragArea(
  height: 40,
  child: Container(color: Colors.transparent),
)
```

### ClusterWindowControls

Pre-styled minimize, maximize, and close buttons.

```dart
ClusterWindowControls(iconSize: 14, color: Colors.grey)
```

Or use individual buttons:

```dart
ClusterMinimizeButton()
ClusterMaximizeButton()
ClusterCloseButton()
```

### ClusterOverlayButton / ClusterOverlayDismiss

Toggle overlay visibility from any window.

```dart
ClusterOverlayButton(label: 'Show Overlay', icon: Icons.picture_in_picture)
ClusterOverlayDismiss(child: Icon(Icons.close))
```

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────┐
│                  Your App Code                   │
│   ClusterApp.run() → ClusterSurface definitions  │
├──────────────────────────────────────────────────┤
│              flutter_cluster_window              │
│                                                  │
│   ClusterController                              │
│   ├── CommandBus + StateReducer (pure, sync)     │
│   ├── Scheduler (3-tier priority, coalescing)    │
│   ├── EventSequencer (buffered, in-order)        │
│   ├── FocusRouter (debounced)                    │
│   ├── LayoutEngine (anchor → absolute coords)    │
│   ├── ReconciliationEngine (Dart ↔ native sync)  │
│   └── FailureHandler (degraded mode)             │
├──────────────────────────────────────────────────┤
│              Native Bridge (C++)                 │
│   ├── Minimal HWND registry                      │
│   ├── DeferWindowPos batching                    │
│   └── WndProc event forwarding                   │
└──────────────────────────────────────────────────┘
```

### Design principles

- **Dart owns all state** — the native layer is a stateless executor
- **Every mutation is a Command** — dispatched through the `CommandBus`
- **Pure state reducer** — `oldState + command → newState` (no side effects)
- **Failures are commands** — a crashed window produces an `EnterDegradedCommand`, not a side effect
- **Native commands are batched** — moves are coalesced per-surface and executed via `DeferWindowPos`

---

## 📁 Example

The `example/` directory contains a full demo with:

- **Editor window** (primary)
- **Sidebar** (panel)
- **Title bar** (chrome) — drag area + window controls
- **Floating overlay**

Run it:

```bash
cd example
flutter run -d windows
```

---

## ⚙️ Advanced Usage

### Programmatic control

For advanced use cases, use `ClusterController` directly:

```dart
final controller = ClusterController(
  clusterId: 'my_app',
  bridge: WindowsNativeBridge(),
  primarySurfaceId: 'main',
);

await controller.start();

controller.addSurface('main', frame: Rect.fromLTWH(100, 100, 800, 600));
controller.move(Offset(50, 50));

controller.onStateChanged.listen((state) {
  print('Version: ${state.version}, Surfaces: ${state.aliveSurfaces.length}');
});

controller.onFailure.listen((failure) {
  print('Surface lost: ${failure.surfaceId} — ${failure.reason}');
});

await controller.close();
```

### Custom native bridge

Implement `NativeBridge` for testing or other platforms:

```dart
class MockBridge implements NativeBridge {
  @override
  Stream<NativeEvent> get events => _controller.stream;

  @override
  Future<void> executeCommand(NativeCommand cmd) async {
    // Record or simulate
  }

  // ... other methods
}
```

---

## 🤝 Contributing

Contributions are welcome! Please file issues and pull requests on the [GitHub repository](https://github.com/user/flutter_cluster_window).

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
