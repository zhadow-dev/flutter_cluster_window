import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import '../bootstrap/cluster_app.dart';

/// Draggable area that moves the entire cluster when dragged.
///
/// Place this widget in any window (title bar, sidebar, main content, etc.)
/// to make that region a drag handle for the cluster.
///
/// ```dart
/// ClusterDragArea(child: Container(height: 40))
/// ```
class ClusterDragArea extends StatelessWidget {
  final Widget? child;
  final double? height;

  const ClusterDragArea({super.key, this.child, this.height});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (_) => _startDrag(),
      child: child ?? Container(color: Colors.transparent, height: height ?? 40),
    );
  }

  void _startDrag() async {
    try {
      const ch = WindowMethodChannel('cluster_commands',
          mode: ChannelMode.unidirectional);
      await ch.invokeMethod('clusterDrag');
    } catch (e) {
      debugPrint('[ClusterDragArea] Drag failed: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Window control buttons
// ---------------------------------------------------------------------------

/// Minimises the entire cluster. Can be placed in any window.
///
/// ```dart
/// ClusterMinimizeButton()
/// ClusterMinimizeButton(child: Icon(Icons.minimize))
/// ```
class ClusterMinimizeButton extends StatelessWidget {
  final Widget? child;
  final double iconSize;
  final Color? color;

  const ClusterMinimizeButton({super.key, this.child, this.iconSize = 14, this.color});

  @override
  Widget build(BuildContext context) {
    return _CtrlBtn(
      icon: Icons.minimize,
      color: color ?? const Color(0xFF8B949E),
      size: iconSize,
      customChild: child,
      onTap: () => _sendCmd('clusterMinimize'),
    );
  }
}

/// Maximises or restores the entire cluster.
///
/// ```dart
/// ClusterMaximizeButton()
/// ```
class ClusterMaximizeButton extends StatelessWidget {
  final Widget? child;
  final double iconSize;
  final Color? color;

  const ClusterMaximizeButton({super.key, this.child, this.iconSize = 14, this.color});

  @override
  Widget build(BuildContext context) {
    return _CtrlBtn(
      icon: Icons.crop_square,
      color: color ?? const Color(0xFF8B949E),
      size: iconSize,
      customChild: child,
      onTap: () => _sendCmd('clusterMaximize'),
    );
  }
}

/// Closes the entire cluster. Can be placed in any window.
///
/// ```dart
/// ClusterCloseButton()
/// ```
class ClusterCloseButton extends StatelessWidget {
  final Widget? child;
  final double iconSize;
  final Color? color;

  const ClusterCloseButton({super.key, this.child, this.iconSize = 14, this.color});

  @override
  Widget build(BuildContext context) {
    return _CtrlBtn(
      icon: Icons.close,
      color: color ?? const Color(0xFFF85149),
      size: iconSize,
      isClose: true,
      customChild: child,
      onTap: () => _sendCmd('clusterClose'),
    );
  }
}

/// Convenience widget containing minimise, maximise, and close buttons.
///
/// ```dart
/// ClusterWindowControls()
/// ```
class ClusterWindowControls extends StatelessWidget {
  final double iconSize;
  final Color? color;

  const ClusterWindowControls({super.key, this.iconSize = 14, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClusterMinimizeButton(iconSize: iconSize, color: color),
        ClusterMaximizeButton(iconSize: iconSize, color: color),
        ClusterCloseButton(iconSize: iconSize),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay buttons
// ---------------------------------------------------------------------------

/// Toggles the overlay / floating window visibility.
///
/// Can be placed in any window. Uses [ClusterScope.onToggleOverlay] when
/// available (primary window), otherwise sends a command via the inter-window
/// channel.
///
/// ```dart
/// ClusterOverlayButton()
/// ClusterOverlayButton(child: Text('PiP'))
/// ```
class ClusterOverlayButton extends StatelessWidget {
  final Widget? child;
  final String label;
  final IconData icon;

  const ClusterOverlayButton({
    super.key,
    this.child,
    this.label = 'Show Overlay',
    this.icon = Icons.picture_in_picture_alt,
  });

  @override
  Widget build(BuildContext context) {
    if (child != null) {
      return GestureDetector(onTap: _toggle, child: child);
    }
    return ElevatedButton.icon(
      onPressed: _toggle,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF238636),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  void _toggle() async {
    final toggle = ClusterScope.onToggleOverlay;
    if (toggle != null) {
      await toggle();
    } else {
      try {
        const ch = WindowMethodChannel('cluster_commands',
            mode: ChannelMode.unidirectional);
        await ch.invokeMethod('clusterOverlay');
      } catch (e) {
        debugPrint('[ClusterOverlayButton] Toggle failed: $e');
      }
    }
  }
}

/// Dismisses the overlay window. Use inside the overlay's widget tree.
///
/// ```dart
/// ClusterOverlayDismiss()
/// ClusterOverlayDismiss(child: Text('Back'))
/// ```
class ClusterOverlayDismiss extends StatelessWidget {
  final Widget? child;

  const ClusterOverlayDismiss({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismiss,
      child: child ?? const Icon(Icons.close, size: 14, color: Color(0xFFF85149)),
    );
  }

  void _dismiss() async {
    try {
      const ch = WindowMethodChannel('cluster_commands',
          mode: ChannelMode.unidirectional);
      await ch.invokeMethod('clusterOverlay');
    } catch (e) {
      debugPrint('[ClusterOverlayDismiss] Dismiss failed: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Sends a cluster command via the inter-window method channel.
void _sendCmd(String method) async {
  try {
    const ch = WindowMethodChannel('cluster_commands',
        mode: ChannelMode.unidirectional);
    await ch.invokeMethod(method);
  } catch (e) {
    debugPrint('[ClusterControls] $method failed: $e');
  }
}

/// Internal control button with hover state.
class _CtrlBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  final bool isClose;
  final Widget? customChild;
  final VoidCallback onTap;

  const _CtrlBtn({
    required this.icon,
    required this.color,
    required this.size,
    this.isClose = false,
    this.customChild,
    required this.onTap,
  });

  @override
  State<_CtrlBtn> createState() => _CtrlBtnState();
}

class _CtrlBtnState extends State<_CtrlBtn> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    if (widget.customChild != null) {
      return GestureDetector(onTap: widget.onTap, child: widget.customChild);
    }

    final c = widget.isClose ? const Color(0xFFF85149) : widget.color;
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: _h ? c.withAlpha(40) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(widget.icon, size: widget.size,
              color: _h ? c : c.withAlpha(150)),
        ),
      ),
    );
  }
}
