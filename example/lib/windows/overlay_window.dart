import 'package:flutter/material.dart';
import 'package:flutter_cluster_window/flutter_cluster_window.dart';

/// Overlay window — Teams-like floating mini window with a dismiss button.
///
/// Fully transparent background so DWM acrylic shows through.
class OverlayWindowApp extends StatelessWidget {
  const OverlayWindowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Segoe UI',
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        colorScheme: ColorScheme.dark(surface: Colors.transparent),
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            // Top bar with title and close button.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.picture_in_picture_alt,
                      size: 14, color: Colors.white70),
                  const SizedBox(width: 6),
                  const Text(
                    'Overlay',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
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
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
