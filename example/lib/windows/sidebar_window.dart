import 'package:flutter/material.dart';

/// Sidebar window — renders a simple labelled container.
class SidebarWindowApp extends StatelessWidget {
  const SidebarWindowApp({super.key});

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
          child: const Center(
            child: Text(
              'Sidebar',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}
