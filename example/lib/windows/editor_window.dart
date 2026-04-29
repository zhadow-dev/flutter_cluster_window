import 'package:flutter/material.dart';
import 'package:flutter_cluster_window/flutter_cluster_window.dart';

/// Editor (primary) window — fully transparent so DWM acrylic shows through.
class EditorWindowApp extends StatelessWidget {
  const EditorWindowApp({super.key});

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
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Main Window',
                style: TextStyle(
                  color: Color(0xFF1A1A2E),
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 16),
              const ClusterOverlayButton(label: 'Show Overlay'),
            ],
          ),
        ),
      ),
    );
  }
}
