import 'package:flutter/material.dart';
import 'package:flutter_cluster_window/flutter_cluster_window.dart';

/// Toolbar panel with branding, menu items, and cluster action buttons.
class ToolbarPanel extends StatelessWidget {
  final bool isActive;
  final bool sidebarVisible;
  final ClusterState? clusterState;
  final VoidCallback onToggleSidebar;
  final VoidCallback onTap;
  final VoidCallback onSimulateCrash;
  final void Function(Offset delta) onMoveCluster;

  const ToolbarPanel({
    super.key,
    required this.isActive,
    required this.sidebarVisible,
    required this.clusterState,
    required this.onToggleSidebar,
    required this.onTap,
    required this.onMoveCluster,
    required this.onSimulateCrash,
  });

  @override
  Widget build(BuildContext context) {
    final mode = clusterState?.mode ?? ClusterMode.normal;
    final lifecycle = clusterState?.lifecycle ?? ClusterLifecyclePhase.init;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF1C2128)
              : const Color(0xFF161B22),
          border: Border(
            bottom: BorderSide(
              color: isActive
                  ? const Color(0xFF58A6FF)
                  : const Color(0xFF30363D),
              width: isActive ? 2 : 1,
            ),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),

            // Brand logo.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF58A6FF).withValues(alpha: 0.2),
                    const Color(0xFF79C0FF).withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hub, size: 18, color: const Color(0xFF58A6FF)),
                  const SizedBox(width: 8),
                  Text(
                    'CLUSTER IDE',
                    style: TextStyle(
                      color: const Color(0xFF58A6FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            // Menu buttons.
            _ToolbarButton(label: 'File', onTap: () {}),
            _ToolbarButton(label: 'Edit', onTap: () {}),
            _ToolbarButton(label: 'View', onTap: () {}),

            const Spacer(),

            // Action buttons.
            _ActionButton(
              icon: sidebarVisible ? Icons.view_sidebar : Icons.menu,
              tooltip: sidebarVisible ? 'Hide Sidebar' : 'Show Sidebar',
              onTap: onToggleSidebar,
            ),

            _ActionButton(
              icon: Icons.play_arrow_rounded,
              tooltip: 'Run',
              color: const Color(0xFF3FB950),
              onTap: () {},
            ),

            _ActionButton(
              icon: Icons.save_outlined,
              tooltip: 'Save',
              onTap: () {},
            ),

            const SizedBox(width: 8),
            Container(width: 1, height: 24, color: const Color(0xFF30363D)),
            const SizedBox(width: 8),

            // Cluster actions.
            _ActionButton(
              icon: Icons.open_with,
              tooltip: 'Move Cluster (+10, +10)',
              onTap: () => onMoveCluster(const Offset(10, 10)),
            ),

            _ActionButton(
              icon: Icons.warning_amber_rounded,
              tooltip: 'Simulate Crash',
              color: const Color(0xFFF85149),
              onTap: onSimulateCrash,
            ),

            const SizedBox(width: 8),

            // Mode / lifecycle badge.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: lifecycle == ClusterLifecyclePhase.degraded
                    ? const Color(0xFFF85149).withValues(alpha: 0.2)
                    : const Color(0xFF3FB950).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                lifecycle == ClusterLifecyclePhase.degraded
                    ? '⚠ DEGRADED'
                    : mode.name.toUpperCase(),
                style: TextStyle(
                  color: lifecycle == ClusterLifecyclePhase.degraded
                      ? const Color(0xFFF85149)
                      : const Color(0xFF3FB950),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),

            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

/// Menu-style text button with hover effect.
class _ToolbarButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _ToolbarButton({required this.label, required this.onTap});

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovering
                ? const Color(0xFF30363D)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _hovering
                  ? const Color(0xFFE6EDF3)
                  : const Color(0xFF8B949E),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon button with tooltip and hover effect.
class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.color ?? const Color(0xFF8B949E);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _hovering
                  ? baseColor.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: _hovering
                  ? baseColor
                  : baseColor.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}
