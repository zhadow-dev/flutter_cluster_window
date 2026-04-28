import 'package:flutter/material.dart';
import 'package:flutter_cluster_window/flutter_cluster_window.dart';

/// Sidebar panel displaying a file tree and cluster state debug info.
class SidebarPanel extends StatelessWidget {
  final bool isActive;
  final String activeFile;
  final VoidCallback onTap;
  final void Function(String file) onFileSelected;
  final ClusterState? clusterState;

  const SidebarPanel({
    super.key,
    required this.isActive,
    required this.activeFile,
    required this.onTap,
    required this.onFileSelected,
    required this.clusterState,
  });

  static const _fileTree = [
    _FileItem('lib', isDir: true, indent: 0),
    _FileItem('main.dart', indent: 1, icon: Icons.code),
    _FileItem('cluster_controller.dart', indent: 1, icon: Icons.code),
    _FileItem('commands.dart', indent: 1, icon: Icons.code),
    _FileItem('events.dart', indent: 1, icon: Icons.code),
    _FileItem('state_reducer.dart', indent: 1, icon: Icons.code),
    _FileItem('scheduler.dart', indent: 1, icon: Icons.code),
    _FileItem('test', isDir: true, indent: 0),
    _FileItem('chaos_test.dart', indent: 1, icon: Icons.bug_report),
    _FileItem('reducer_test.dart', indent: 1, icon: Icons.bug_report),
    _FileItem('pubspec.yaml', indent: 0, icon: Icons.settings),
    _FileItem('README.md', indent: 0, icon: Icons.description),
  ];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 250,
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF161B22)
              : const Color(0xFF0D1117),
          border: Border(
            right: BorderSide(
              color: isActive
                  ? const Color(0xFF58A6FF).withValues(alpha: 0.5)
                  : const Color(0xFF21262D),
              width: 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFF21262D),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: const Color(0xFF8B949E),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'EXPLORER',
                    style: TextStyle(
                      color: const Color(0xFF8B949E),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  _SurfaceIndicator(
                    surfaceId: 'sidebar',
                    clusterState: clusterState,
                  ),
                ],
              ),
            ),

            // File tree
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _fileTree.length,
                itemBuilder: (context, index) {
                  final item = _fileTree[index];
                  final isSelected = !item.isDir && item.name == activeFile;

                  return _FileTreeRow(
                    item: item,
                    isSelected: isSelected,
                    onTap: item.isDir
                        ? null
                        : () => onFileSelected(item.name),
                  );
                },
              ),
            ),

            // Cluster state debug section
            if (clusterState != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  border: Border(
                    top: BorderSide(color: const Color(0xFF21262D)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CLUSTER STATE',
                      style: TextStyle(
                        color: const Color(0xFF484F58),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _StateRow('Version', 'v${clusterState!.version}'),
                    _StateRow('Surfaces', '${clusterState!.surfaces.length}'),
                    _StateRow('Alive', '${clusterState!.aliveSurfaces.length}'),
                    _StateRow('Mode', clusterState!.mode.name),
                    _StateRow('Phase', clusterState!.lifecycle.name),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single entry in the file tree (file or directory).
class _FileItem {
  final String name;
  final bool isDir;
  final int indent;
  final IconData? icon;

  const _FileItem(this.name, {this.isDir = false, this.indent = 0, this.icon});
}

/// Row widget for a single file tree entry with hover and selection styling.
class _FileTreeRow extends StatefulWidget {
  final _FileItem item;
  final bool isSelected;
  final VoidCallback? onTap;

  const _FileTreeRow({
    required this.item,
    required this.isSelected,
    this.onTap,
  });

  @override
  State<_FileTreeRow> createState() => _FileTreeRowState();
}

class _FileTreeRowState extends State<_FileTreeRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: EdgeInsets.only(
            left: 16 + item.indent * 16.0,
            right: 12,
            top: 4,
            bottom: 4,
          ),
          color: widget.isSelected
              ? const Color(0xFF58A6FF).withValues(alpha: 0.12)
              : _hovering
                  ? const Color(0xFF1C2128)
                  : Colors.transparent,
          child: Row(
            children: [
              Icon(
                item.isDir
                    ? Icons.folder_rounded
                    : item.icon ?? Icons.insert_drive_file_outlined,
                size: 16,
                color: item.isDir
                    ? const Color(0xFF79C0FF)
                    : widget.isSelected
                        ? const Color(0xFFE6EDF3)
                        : const Color(0xFF8B949E),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  style: TextStyle(
                    color: widget.isSelected
                        ? const Color(0xFFE6EDF3)
                        : _hovering
                            ? const Color(0xFFC9D1D9)
                            : const Color(0xFF8B949E),
                    fontSize: 13,
                    fontWeight: item.isDir
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small dot indicator showing whether a surface is alive.
class _SurfaceIndicator extends StatelessWidget {
  final String surfaceId;
  final ClusterState? clusterState;

  const _SurfaceIndicator({
    required this.surfaceId,
    required this.clusterState,
  });

  @override
  Widget build(BuildContext context) {
    final surface = clusterState?.surfaces[surfaceId];
    final isAlive = surface?.isAlive ?? false;

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isAlive
            ? const Color(0xFF3FB950)
            : const Color(0xFFF85149),
        boxShadow: [
          BoxShadow(
            color: (isAlive
                    ? const Color(0xFF3FB950)
                    : const Color(0xFFF85149))
                .withValues(alpha: 0.4),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}

/// Key-value row for the cluster state debug section.
class _StateRow extends StatelessWidget {
  final String label;
  final String value;

  const _StateRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFF484F58),
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: const Color(0xFF8B949E),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
