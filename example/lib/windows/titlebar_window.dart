import 'package:flutter/material.dart';
import 'package:flutter_cluster_window/flutter_cluster_window.dart';

/// Title bar window using plugin-provided drag area and window controls.
class TitleBarWindowApp extends StatelessWidget {
  const TitleBarWindowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF161B22),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              const Icon(Icons.code, size: 14, color: Color(0xFF58A6FF)),
              const SizedBox(width: 6),
              const Text(
                'CLUSTER IDE',
                style: TextStyle(
                  color: Color(0xFF58A6FF),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const Expanded(
                child: ClusterDragArea(height: 40),
              ),
              const ClusterWindowControls(),
            ],
          ),
        ),
      ),
    );
  }
}
