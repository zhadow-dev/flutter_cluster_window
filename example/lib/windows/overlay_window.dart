import 'package:flutter/material.dart';
import 'package:flutter_cluster_window/flutter_cluster_window.dart';

/// Overlay window — Teams-like floating mini window with a dismiss button.
class OverlayWindowApp extends StatelessWidget {
  const OverlayWindowApp({super.key});

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
          child: Column(
            children: [
              // Top bar with title and close button.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.picture_in_picture_alt, size: 14, color: Color(0xFF58A6FF)),
                    const SizedBox(width: 6),
                    const Text(
                      'Overlay',
                      style: TextStyle(
                        color: Color(0xFF8B949E),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const ClusterOverlayDismiss(),
                  ],
                ),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    'Floating Window',
                    style: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
