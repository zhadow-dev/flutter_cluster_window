import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

/// Nav-bar window — a compact, vertical icon strip with 4 items.
///
/// Designed for use with `shrinkToContent: true` so the OS window
/// collapses to fit exactly these icons. Fully transparent background
/// so the DWM acrylic effect shows through.
class SidebarWindowApp extends StatefulWidget {
  const SidebarWindowApp({super.key});

  @override
  State<SidebarWindowApp> createState() => _SidebarWindowAppState();
}

class _SidebarWindowAppState extends State<SidebarWindowApp> {
  int _selected = 0;

  static const _items = <_NavItem>[
    _NavItem(icon: Icons.home_rounded, label: 'Home'),
    _NavItem(icon: Icons.search_rounded, label: 'Search'),
    _NavItem(icon: Icons.person_rounded, label: 'Profile'),
    _NavItem(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  void _onTap(int index) {
    setState(() => _selected = index);
    // Optionally notify the primary window via inter-window channel.
    try {
      const ch = WindowMethodChannel(
        'cluster_commands',
        mode: ChannelMode.unidirectional,
      );
      ch.invokeMethod('navigate', index);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Segoe UI',
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < _items.length; i++)
                _NavButton(
                  item: _items[i],
                  selected: _selected == i,
                  onTap: () => _onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _NavButton extends StatefulWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.selected;
    final color = isActive
        ? const Color(0xFF1A1A2E)
        : _hovered
            ? const Color(0xFF3A3A4E)
            : const Color(0xFF6E6E82);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.item.label,
          preferBelow: false,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0x1A1A1A2E)
                  : _hovered
                      ? const Color(0x0D000000)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.item.icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }
}
