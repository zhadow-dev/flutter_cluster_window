import 'package:flutter/material.dart';
import 'package:flutter_cluster_window/flutter_cluster_window.dart';

/// Title bar window — fully transparent so DWM acrylic shows through.
///
/// Anchored above the primary window. Contains only a drag area
/// and window controls (minimize, maximize, close).
class TitleBarWindowApp extends StatelessWidget {
  const TitleBarWindowApp({super.key});

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
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Drag area fills the remaining space.
              const Expanded(child: ClusterDragArea(height: 40)),
              // Window controls — minimize, maximize/restore, close.
              const ClusterWindowControls(
                color: Color(0xFF4A4A5E),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
