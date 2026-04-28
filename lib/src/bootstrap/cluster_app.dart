import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:window_manager/window_manager.dart';

import '../core/surface_role.dart';
import '../layout/surface_anchor.dart';
import 'cluster_surface.dart';

/// Native bridge channel registered in all windows (primary and children).
const _nativeCh = MethodChannel('flutter_cluster_window');

/// Bootstrap entry point that routes `main()` to the correct window.
///
/// Determines whether the current process is the primary window or a child
/// window based on [args], then delegates to the appropriate boot sequence.
class ClusterApp {
  static void run({
    required List<String> args,
    required String clusterId,
    required List<ClusterSurface> surfaces,
  }) {
    final primaries = surfaces.where((s) => s.isPrimary).toList();
    assert(primaries.length == 1,
        'Exactly one primary surface required. Found ${primaries.length}.');

    if (args.isNotEmpty) {
      _bootChild(args, surfaces);
    } else {
      _bootPrimary(clusterId, surfaces);
    }
  }

  // ---------------------------------------------------------------------------
  // Primary window boot sequence
  // ---------------------------------------------------------------------------

  /// Child HWNDs from the previous run, used to clean up orphans on hot restart.
  static final List<int> _previousHwnds = [];

  static void _bootPrimary(
    String clusterId,
    List<ClusterSurface> surfaces,
  ) async {
    WidgetsFlutterBinding.ensureInitialized();

    final primary = surfaces.firstWhere((s) => s.isPrimary);
    final children = surfaces.where((s) => !s.isPrimary && s.role != SurfaceRole.overlay).toList();
    final overlays = surfaces.where((s) => s.role == SurfaceRole.overlay).toList();

    // Initialise window_manager.
    await windowManager.ensureInitialized();
    final isRestart = _previousHwnds.isNotEmpty;
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: primary.size,
        center: !isRestart,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: primary.frameless ? TitleBarStyle.hidden : TitleBarStyle.normal,
      ),
      () async {
        await windowManager.setHasShadow(false);
        await windowManager.show();
        await windowManager.focus();
      },
    );

    // Apply acrylic effect on primary window.
    await _applyEffect(primary.acrylicEffect);

    final controllers = <String, WindowController>{};
    final hwnds = <String, int>{};

    // Retrieve the primary window's native handle.
    final primaryHwnd = await _nativeCh.invokeMethod<int>('getWindowHwnd') ?? 0;
    debugPrint('[Cluster] Primary HWND=$primaryHwnd');

    await windowManager.restore();
    await windowManager.show();
    await Future.delayed(const Duration(milliseconds: 100));

    // Destroy orphan child windows left over from a previous hot restart.
    if (_previousHwnds.isNotEmpty) {
      debugPrint('[Cluster] Cleaning up ${_previousHwnds.length} orphan windows...');
      for (final oldHwnd in _previousHwnds) {
        try {
          await _nativeCh.invokeMethod('destroyWindow', {'handle': oldHwnd});
          debugPrint('[Cluster] Destroyed orphan HWND=$oldHwnd');
        } catch (_) {}
      }
      _previousHwnds.clear();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    final found = await _nativeCh.invokeMethod<List<dynamic>>('findChildHwnds', {
      'handle': primaryHwnd,
    });
    final orphans = (found?.cast<int>() ?? []).toSet();
    if (orphans.isNotEmpty) {
      debugPrint('[Cluster] Destroying ${orphans.length} orphan windows');
      for (final oldHwnd in orphans) {
        try {
          await _nativeCh.invokeMethod('destroyWindow', {'handle': oldHwnd});
        } catch (_) {}
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // Track known HWNDs so new ones can be detected after each spawn.
    Set<int> knownHwnds = {};
    final freshList = await _nativeCh.invokeMethod<List<dynamic>>('findChildHwnds', {
      'handle': primaryHwnd,
    });
    knownHwnds = (freshList?.cast<int>() ?? []).toSet();

    // Spawn each child window sequentially and resolve its HWND.
    for (final child in [...children, ...overlays]) {
      try {
        final ctrl = await WindowController.create(
          WindowConfiguration(
            hiddenAtLaunch: true,
            arguments: child.encode(),
          ),
        );
        controllers[child.id] = ctrl;

        await Future.delayed(const Duration(milliseconds: 500));

        for (int attempt = 0; attempt < 10; attempt++) {
          final result = await _nativeCh.invokeMethod<List<dynamic>>('findChildHwnds', {
            'handle': primaryHwnd,
          });
          final currentHwnds = (result?.cast<int>() ?? []).toSet();
          final newHwnds = currentHwnds.difference(knownHwnds);
          if (newHwnds.isNotEmpty) {
            hwnds[child.id] = newHwnds.first;
            knownHwnds = currentHwnds;
            debugPrint('[Cluster] Spawned ${child.id} → HWND=${newHwnds.first}');
            break;
          }
          await Future.delayed(const Duration(milliseconds: 200));
        }
      } catch (e) {
        debugPrint('[Cluster] Spawn failed: ${child.id}: $e');
      }
    }

    _previousHwnds
      ..clear()
      ..addAll(hwnds.values);

    // Retrieve physical bounds of the primary window for layout calculations.
    final physRect = await _nativeCh.invokeMethod<Map<dynamic, dynamic>>('getPhysicalRect', {
      'handle': primaryHwnd,
    });
    final px = (physRect?['x'] as int?) ?? 0;
    final py = (physRect?['y'] as int?) ?? 0;
    final pw = (physRect?['w'] as int?) ?? 900;
    final ph = (physRect?['h'] as int?) ?? 620;
    final primaryBounds = Rect.fromLTWH(px.toDouble(), py.toDouble(), pw.toDouble(), ph.toDouble());

    // Compute DPI scale: physical / logical.
    final logicalBounds = await windowManager.getBounds();
    final dpiScale = logicalBounds.width > 0
        ? pw / logicalBounds.width
        : 1.0;
    debugPrint('[Cluster] Primary physical=$primaryBounds logical=$logicalBounds dpi=$dpiScale');

    // Sum up edge reservations (in physical pixels) for each anchor direction.
    double leftReservation = 0;
    double rightReservation = 0;
    double topReservation = 0;
    double bottomReservation = 0;
    for (final child in children) {
      if (child.anchor == null) continue;
      if (child.anchor is LeftSurfaceAnchor) {
        final a = child.anchor as LeftSurfaceAnchor;
        leftReservation += child.size.width * dpiScale + a.gap * dpiScale;
      } else if (child.anchor is RightSurfaceAnchor) {
        final a = child.anchor as RightSurfaceAnchor;
        rightReservation += child.size.width * dpiScale + a.gap * dpiScale;
      } else if (child.anchor is TopSurfaceAnchor) {
        final a = child.anchor as TopSurfaceAnchor;
        topReservation += child.size.height * dpiScale + a.gap * dpiScale;
      } else if (child.anchor is BottomSurfaceAnchor) {
        final a = child.anchor as BottomSurfaceAnchor;
        bottomReservation += child.size.height * dpiScale + a.gap * dpiScale;
      }
    }

    // Position, style, and show each child window.
    for (final child in children) {
      final hwnd = hwnds[child.id];
      if (hwnd == null) continue;

      final Rect bounds;
      if (child.anchor is AbsoluteSurfaceAnchor) {
        final a = child.anchor as AbsoluteSurfaceAnchor;
        bounds = Rect.fromLTWH(
          a.position.dx * dpiScale,
          a.position.dy * dpiScale,
          child.size.width * dpiScale,
          child.size.height * dpiScale,
        );
      } else {
        final double fixedDimension;
        if (child.anchor is LeftSurfaceAnchor || child.anchor is RightSurfaceAnchor) {
          fixedDimension = child.size.width * dpiScale;
        } else {
          fixedDimension = child.size.height * dpiScale;
        }
        bounds = child.anchor!.computeBounds(
          primaryBounds, fixedDimension,
          dpiScale: dpiScale,
          leftReservation: leftReservation,
          rightReservation: rightReservation,
          topReservation: topReservation,
          bottomReservation: bottomReservation,
        );
      }
      debugPrint('[Cluster] ${child.id} → HWND=$hwnd bounds=$bounds');

      if (child.frameless) {
        await _nativeCh.invokeMethod('setFrameless', {'handle': hwnd});
      }

      await _nativeCh.invokeMethod('setWindowPos', {
        'handle': hwnd,
        'frame': {
          'x': bounds.left.toInt(),
          'y': bounds.top.toInt(),
          'w': bounds.width.toInt(),
          'h': bounds.height.toInt(),
        },
      });

      // Hide from Alt+Tab.
      await _nativeCh.invokeMethod('setToolWindow', {'handle': hwnd});

      // Owner relationship enables z-order grouping and cascading minimize.
      await _nativeCh.invokeMethod('setOwner', {
        'handle': hwnd,
        'ownerHandle': primaryHwnd,
      });

      controllers[child.id]!.show();

      if (child.acrylicEffect != AcrylicEffect.none) {
        try {
          await _nativeCh.invokeMethod('setDwmEffect', {
            'handle': hwnd,
            'effect': child.acrylicEffect.name,
          });
          debugPrint('[Cluster] DWM effect ${child.acrylicEffect.name} applied to ${child.id}');
        } catch (e) {
          debugPrint('[Cluster] DWM effect failed for ${child.id}: $e');
        }
      }

      try {
        await _nativeCh.invokeMethod('setCornerPreference', {
          'handle': hwnd,
          'preference': 'round',
        });
      } catch (_) {}

      try {
        await controllers[child.id]!.invokeMethod('parentReady');
      } catch (_) {}
    }

    // Prepare overlay windows (spawned hidden, shown on demand).
    for (final child in overlays) {
      final hwnd = hwnds[child.id];
      if (hwnd == null) continue;

      if (child.frameless) {
        await _nativeCh.invokeMethod('setFrameless', {'handle': hwnd});
      }
      await _nativeCh.invokeMethod('setToolWindow', {'handle': hwnd});
    }

    // Install a native move hook so children follow the primary window.
    await _nativeCh.invokeMethod('installMoveHook', {'handle': primaryHwnd});

    const eventChannel = EventChannel('flutter_cluster_window/events');
    eventChannel.receiveBroadcastStream().listen((event) async {
      if (event is! Map) return;
      final type = event['type'] as String?;

      if (type == 'WINDOW_MOVED' || type == 'WINDOW_RESIZED') {
        final rect = await _nativeCh.invokeMethod<Map<dynamic, dynamic>>('getPhysicalRect', {
          'handle': primaryHwnd,
        });
        if (rect == null) return;
        final newBounds = Rect.fromLTWH(
          (rect['x'] as int).toDouble(),
          (rect['y'] as int).toDouble(),
          (rect['w'] as int).toDouble(),
          (rect['h'] as int).toDouble(),
        );
        for (final child in children) {
          final hwnd = hwnds[child.id];
          if (hwnd == null || child.anchor == null) continue;
          if (child.anchor is AbsoluteSurfaceAnchor) continue;

          final double fixedDimension;
          if (child.anchor is LeftSurfaceAnchor || child.anchor is RightSurfaceAnchor) {
            fixedDimension = child.size.width * dpiScale;
          } else {
            fixedDimension = child.size.height * dpiScale;
          }
          final bounds = child.anchor!.computeBounds(
            newBounds, fixedDimension,
            dpiScale: dpiScale,
            leftReservation: leftReservation,
            rightReservation: rightReservation,
            topReservation: topReservation,
            bottomReservation: bottomReservation,
          );
          await _nativeCh.invokeMethod('setWindowPos', {
            'handle': hwnd,
            'frame': {
              'x': bounds.left.toInt(),
              'y': bounds.top.toInt(),
              'w': bounds.width.toInt(),
              'h': bounds.height.toInt(),
            },
          });
        }
      }
    });

    // Register handler for commands sent by child windows.
    const cmdChannel = WindowMethodChannel('cluster_commands',
        mode: ChannelMode.unidirectional);

    final overlayHwnd = overlays.isNotEmpty ? hwnds[overlays.first.id] : null;
    final clusterHwnds = <int>[];
    for (final child in children) {
      final h = hwnds[child.id];
      if (h != null) clusterHwnds.add(h);
    }

    final overlayConfig = overlays.isNotEmpty ? overlays.first : null;

    Future<void> doToggleOverlay() async {
      if (overlayHwnd == null) return;
      await _nativeCh.invokeMethod('toggleOverlay', {
        'overlayHandle': overlayHwnd,
        'primaryHandle': primaryHwnd,
        'clusterHandles': clusterHwnds,
        'hideCluster': overlayConfig?.hideClusterOnShow ?? true,
      });
    }

    Future<void> doDrag(Map<dynamic, dynamic>? args) async {
      await _nativeCh.invokeMethod('dragPrimaryWindow', args);
    }

    await cmdChannel.setMethodCallHandler((call) async {
      debugPrint('[Cluster] Received command: ${call.method}');
      switch (call.method) {
        case 'clusterDrag':
          await doDrag(call.arguments as Map<dynamic, dynamic>?);
          return null;
        case 'clusterMinimize':
          await _nativeCh.invokeMethod('minimizePrimaryWindow');
          return null;
        case 'clusterMaximize':
          await _nativeCh.invokeMethod('maximizePrimaryWindow');
          return null;
        case 'clusterClose':
          await _nativeCh.invokeMethod('closePrimaryWindow');
          return null;
        case 'clusterOverlay':
          await doToggleOverlay();
          return null;
        default:
          return null;
      }
    });

    ClusterScope.onToggleOverlay = doToggleOverlay;

    runApp(
      ClusterScope(
        clusterId: clusterId,
        controllers: controllers,
        hwnds: hwnds,
        surfaces: surfaces,
        child: primary.builder(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Child window boot sequence
  // ---------------------------------------------------------------------------

  static void _bootChild(
    List<String> args,
    List<ClusterSurface> surfaces,
  ) async {
    WidgetsFlutterBinding.ensureInitialized();

    WindowController? controller;
    ClusterSurface? surface;

    try {
      controller = await WindowController.fromCurrentEngine();
      final configJson = controller.arguments;
      if (configJson.isNotEmpty) {
        final map = jsonDecode(configJson) as Map<String, dynamic>;
        final id = map['id'] as String;
        final match = surfaces.where((s) => s.id == id).firstOrNull;
        if (match != null) {
          surface = ClusterSurface.decode(configJson, match.builder);
        }
      }
    } catch (e) {
      debugPrint('[Cluster] Child init failed: $e');
    }

    if (surface == null) {
      runApp(const MaterialApp(
        home: Scaffold(body: Center(child: Text('Surface config not found'))),
      ));
      return;
    }

    debugPrint('[Cluster] Child booting: ${surface.id} (${surface.role.name})');

    final readyCompleter = Completer<void>();
    final surfaceId = surface.id;

    if (controller != null) {
      await controller.setWindowMethodHandler((call) async {
        if (call.method == 'getHwnd') {
          try {
            return await _nativeCh.invokeMethod<int>('getWindowHwnd');
          } catch (e) {
            debugPrint('[Cluster] getHwnd failed in $surfaceId: $e');
            return 0;
          }
        }
        if (call.method == 'parentReady') {
          if (!readyCompleter.isCompleted) readyCompleter.complete();
          return null;
        }
        if (call.method == 'showOverlay') {
          controller?.show();
          return null;
        }
        if (call.method == 'hideOverlay') {
          controller?.hide();
          return null;
        }
        return null;
      });
    }

    // Build the widget tree, optionally wrapping with shrink-to-content.
    Widget app = surface.builder();
    if (surface.shrinkToContent) {
      app = _ShrinkToContentWrapper(
        maxSize: surface.size,
        child: app,
      );
    }
    runApp(app);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Applies a DWM backdrop effect (acrylic, mica, etc.) to the primary window.
  static Future<void> _applyEffect(AcrylicEffect effect) async {
    try {
      await acrylic.Window.initialize();
      await acrylic.Window.setEffect(
        effect: _mapEffect(effect),
        color: effect == AcrylicEffect.solid
            ? const Color(0xFF161B22)
            : Colors.transparent,
        dark: true,
      );
      debugPrint('[Cluster] Effect applied: ${effect.name}');
    } catch (e) {
      debugPrint('[Cluster] Effect failed: $e');
    }
  }

  /// Maps the plugin's [AcrylicEffect] enum to the `flutter_acrylic` enum.
  static acrylic.WindowEffect _mapEffect(AcrylicEffect effect) {
    return switch (effect) {
      AcrylicEffect.acrylic => acrylic.WindowEffect.acrylic,
      AcrylicEffect.mica => acrylic.WindowEffect.mica,
      AcrylicEffect.transparent => acrylic.WindowEffect.transparent,
      AcrylicEffect.solid => acrylic.WindowEffect.solid,
      AcrylicEffect.none => acrylic.WindowEffect.disabled,
    };
  }
}

/// Visual backdrop effect applied to a window via DWM.
enum AcrylicEffect { acrylic, mica, transparent, solid, none }

/// [InheritedWidget] that provides cluster context to descendant widgets.
///
/// Access via `ClusterScope.of(context)` from any widget in the primary
/// window's tree.
class ClusterScope extends InheritedWidget {
  final String clusterId;
  final Map<String, WindowController> controllers;
  final Map<String, int> hwnds;
  final List<ClusterSurface> surfaces;

  /// Callback for toggling the overlay, set during the boot sequence.
  static Future<void> Function()? onToggleOverlay;

  const ClusterScope({
    super.key,
    required this.clusterId,
    required this.controllers,
    required this.hwnds,
    required this.surfaces,
    required super.child,
  });

  /// Returns the nearest [ClusterScope] ancestor, or `null`.
  static ClusterScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ClusterScope>();

  /// Toggles the overlay window visibility.
  Future<void> toggleOverlay() async {
    if (onToggleOverlay != null) {
      await onToggleOverlay!();
    }
  }

  @override
  bool updateShouldNotify(ClusterScope oldWidget) =>
      controllers != oldWidget.controllers;
}

/// Wrapper that measures the child's rendered size after the first frame
/// and resizes the OS window to fit.
///
/// [maxSize] constrains the maximum window dimensions. The child is laid
/// out inside an `Align` so it can report its natural (intrinsic) size
/// instead of being forced to fill the available space.
class _ShrinkToContentWrapper extends StatefulWidget {
  final Size maxSize;
  final Widget child;

  const _ShrinkToContentWrapper({
    required this.maxSize,
    required this.child,
  });

  @override
  State<_ShrinkToContentWrapper> createState() =>
      _ShrinkToContentWrapperState();
}

class _ShrinkToContentWrapperState extends State<_ShrinkToContentWrapper> {
  final GlobalKey _contentKey = GlobalKey();
  bool _didShrink = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndShrink());
  }

  Future<void> _measureAndShrink() async {
    if (_didShrink) return;
    _didShrink = true;

    final renderBox =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final contentSize = renderBox.size;

    // Clamp to maxSize.
    final newWidth = widget.maxSize.width > 0
        ? contentSize.width.clamp(0.0, widget.maxSize.width)
        : contentSize.width;
    final newHeight = widget.maxSize.height > 0
        ? contentSize.height.clamp(0.0, widget.maxSize.height)
        : contentSize.height;

    // Only resize if content is actually smaller than current window.
    try {
      final hwnd = await _nativeCh.invokeMethod<int>('getWindowHwnd') ?? 0;
      if (hwnd == 0) return;

      // Get DPI scale.
      final dpi = await _nativeCh.invokeMethod<double>('getDpiScale') ?? 1.0;
      final physW = (newWidth * dpi).round();
      final physH = (newHeight * dpi).round();

      await _nativeCh.invokeMethod('setWindowSize', {
        'handle': hwnd,
        'width': physW,
        'height': physH,
      });

      debugPrint(
        '[Cluster] Shrink-to-content: '
        '${contentSize.width.round()}×${contentSize.height.round()} → '
        '${physW}×$physH (dpi=$dpi)',
      );
    } catch (e) {
      debugPrint('[Cluster] Shrink-to-content failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: KeyedSubtree(
            key: _contentKey,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
