import 'package:flutter/material.dart';
import 'package:flutter_cluster_window/flutter_cluster_window.dart';

/// Editor (primary) window with an overlay toggle button.
class EditorWindowApp extends StatelessWidget {
  const EditorWindowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0D1117),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Main Editor',
                  style: TextStyle(color: Color(0xFF8B949E), fontSize: 14),
                ),
                const SizedBox(height: 16),
                const ClusterOverlayButton(label: 'Show Overlay'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
