import 'package:flutter/material.dart';
import 'package:flutter_cluster_window/flutter_cluster_window.dart';

/// Status bar displaying cluster health, event log, and version info.
class StatusBar extends StatelessWidget {
  final String statusMessage;
  final ClusterState? clusterState;
  final List<String> eventLog;

  const StatusBar({
    super.key,
    required this.statusMessage,
    required this.clusterState,
    required this.eventLog,
  });

  @override
  Widget build(BuildContext context) {
    final isDegraded =
        clusterState?.lifecycle == ClusterLifecyclePhase.degraded;

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: isDegraded
            ? const Color(0xFFF85149).withValues(alpha: 0.15)
            : const Color(0xFF161B22),
        border: Border(
          top: BorderSide(
            color: isDegraded
                ? const Color(0xFFF85149).withValues(alpha: 0.5)
                : const Color(0xFF21262D),
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),

          // Health indicator dot.
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDegraded
                  ? const Color(0xFFF85149)
                  : const Color(0xFF3FB950),
              boxShadow: [
                BoxShadow(
                  color: (isDegraded
                          ? const Color(0xFFF85149)
                          : const Color(0xFF3FB950))
                      .withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Status message.
          Text(
            statusMessage,
            style: TextStyle(
              color: isDegraded
                  ? const Color(0xFFF85149)
                  : const Color(0xFF8B949E),
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),

          const Spacer(),

          // Last event from the event log.
          if (eventLog.isNotEmpty)
            Tooltip(
              message: eventLog.take(10).join('\n'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.terminal,
                    size: 13,
                    color: const Color(0xFF484F58),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    eventLog.first.length > 60
                        ? '${eventLog.first.substring(0, 60)}…'
                        : eventLog.first,
                    style: TextStyle(
                      color: const Color(0xFF484F58),
                      fontSize: 11,
                      fontFamily: 'Consolas',
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(width: 16),

          // Alive surface count.
          if (clusterState != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.window, size: 13, color: const Color(0xFF484F58)),
                const SizedBox(width: 4),
                Text(
                  '${clusterState!.aliveSurfaces.length} surfaces',
                  style: TextStyle(
                    color: const Color(0xFF484F58),
                    fontSize: 11,
                  ),
                ),
              ],
            ),

          const SizedBox(width: 16),

          // State version.
          if (clusterState != null)
            Text(
              'v${clusterState!.version}',
              style: TextStyle(
                color: const Color(0xFF484F58),
                fontSize: 11,
                fontFamily: 'Consolas',
              ),
            ),

          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
