import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:window_manager/window_manager.dart';

import '../core/cluster_visual_config.dart';
import '../core/surface_role.dart';
import '../core/surface_visual.dart';
import '../layout/surface_anchor.dart';
import 'cluster_surface.dart';

/// Native bridge channel registered in all windows (primary and children).
const _nativeCh = MethodChannel('flutter_cluster_window');

/// Completer that the child boot sequence completes when the parent signals
/// `parentReady`.  Used by [_ShrinkToContentWrapper] to delay its measurement
/// until after the parent has positioned the window via `setWindowPos`.
Completer<void>? _parentReadyCompleter;

/// Maps [BackdropType] to [acrylic.WindowEffect] for the primary window.
acrylic.WindowEffect _mapBackdropToWindowEffect(BackdropType backdrop) {
  switch (backdrop) {
    case BackdropType.acrylic:
      return acrylic.WindowEffect.acrylic;
    case BackdropType.mica:
      return acrylic.WindowEffect.mica;
    case BackdropType.tabbed:
      return acrylic.WindowEffect.tabbed;
    case BackdropType.transparent:
      return acrylic.WindowEffect.transparent;
    case BackdropType.none:
      return acrylic.WindowEffect.disabled;
  }
}

/// Bootstrap entry point that routes `main()` to the correct window.
///
/// Determines whether the current process is the primary window or a child
/// window based on [args], then delegates to the appropriate boot sequence.
class ClusterApp {
  static void run({
    required List<String> args,
    required String clusterId,
    required List<ClusterSurface> surfaces,
    ClusterVisualConfig? visualConfig,
  }) {
    final primaries = surfaces.where((s) => s.isPrimary).toList();
    assert(primaries.length == 1,
        'Exactly one primary surface required. Found ${primaries.length}.');

    final config = visualConfig ??
        ClusterVisualConfig(shadowOwnerId: primaries.first.id);

    if (args.isNotEmpty) {
      _bootChild(args, surfaces);
    } else {
      _bootPrimary(clusterId, surfaces, config);
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
    ClusterVisualConfig config,
  ) async {
    WidgetsFlutterBinding.ensureInitialized();

    final primary = surfaces.firstWhere((s) => s.isPrimary);
    final children = surfaces.where((s) => !s.isPrimary && s.role != SurfaceRole.overlay).toList();
    final overlays = surfaces.where((s) => s.role == SurfaceRole.overlay).toList();

    // Initialise window_manager.
    await windowManager.ensureInitialized();

    // flutter_acrylic initialisation makes the Flutter rendering surface
    // transparent. Without this, the engine paints opaque black under
    // all widgets, hiding any DWM backdrop effect.
    await acrylic.Window.initialize();

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
        await windowManager.setHasShadow(primary.id == config.shadowOwnerId);
        await windowManager.show();
        await windowManager.focus();
      },
    );

    final controllers = <String, WindowController>{};
    final hwnds = <String, int>{};

    // Retrieve the primary window's native handle.
    final primaryHwnd = await _nativeCh.invokeMethod<int>('getWindowHwnd') ?? 0;
    debugPrint('[Cluster] Primary HWND=$primaryHwnd');

    // Apply backdrop effect on primary window via flutter_acrylic.
    // flutter_acrylic handles the full composition pipeline for the
    // primary window's Flutter engine view:
    //   - Makes rendering surface transparent
    //   - Extends DWM frame into client area
    //   - Sets WS_EX_LAYERED for composition
    //   - Applies DWMWA_SYSTEMBACKDROP_TYPE
    // Child windows use our native setDwmEffect instead.
    if (primary.visual.backdrop != BackdropType.none) {
      try {
        final effect = _mapBackdropToWindowEffect(primary.visual.backdrop);
        await acrylic.Window.setEffect(
          effect: effect,
          dark: true,
        );
        debugPrint('[Cluster] Primary backdrop: ${primary.visual.backdrop.name} (via flutter_acrylic)');
      } catch (e) {
        debugPrint('[Cluster] Primary backdrop failed: $e');
      }
    }

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

      // ── Phase 1: Frameless + Owner (structural, before composition) ──
      if (child.frameless) {
        await _nativeCh.invokeMethod('setFrameless', {'handle': hwnd});
      }
      await _nativeCh.invokeMethod('setOwner', {
        'handle': hwnd,
        'ownerHandle': primaryHwnd,
      });

      // ── Phase 2: Position ──
      await _nativeCh.invokeMethod('setWindowPos', {
        'handle': hwnd,
        'frame': {
          'x': bounds.left.toInt(),
          'y': bounds.top.toInt(),
          'w': bounds.width.toInt(),
          'h': bounds.height.toInt(),
        },
      });

      // ── Phase 3: Degrade to flat surface (before show) ──
      // Kills shadow at source, sets tool window, no rounded corners.
      // DWM backdrop (acrylic/mica) is handled by flutter_acrylic's
      // Window.setEffect() called from within each child's engine.
      try {
        await _nativeCh.invokeMethod('prepareChildComposition', {
          'handle': hwnd,
        });
        debugPrint('[Cluster][composition] ${child.id} degraded to flat surface');
      } catch (e) {
        debugPrint('[Cluster][composition] Failed for ${child.id}: $e');
      }

      // ── Phase 4: Show ──
      controllers[child.id]!.show();

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
      // Overlay shadow: controlled by config, not per-surface.
      if (!config.allowOverlayShadow) {
        final hasBackdrop = child.visual.backdrop != BackdropType.none;
        try {
          await _nativeCh.invokeMethod('removeShadow', {
            'handle': hwnd,
            'preserveMargins': hasBackdrop,
          });
        } catch (_) {}
      }
      await _nativeCh.invokeMethod('setToolWindow', {'handle': hwnd});
    }

    // ── Initial cluster reconciliation (boot) ──────────────────
    _clearShadowCache(); // Clear on restart / hot reload.
    final bootV = ++_version;
    await _reconcileZOrder(
      primaryHwnd: primaryHwnd,
      children: children,
      hwnds: hwnds,
      version: bootV,
    );
    await _enforceShadowPolicy(
      config: config,
      primary: primary,
      children: children,
      primaryHwnd: primaryHwnd,
      hwnds: hwnds,
      version: bootV,
    );
    debugPrint('[Cluster][v$bootV][boot] Initial reconcile complete');

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

          if (child.shrinkToContent) {
            // Only update position; preserve the content-driven size.
            final currentRect = await _nativeCh
                .invokeMethod<Map<dynamic, dynamic>>(
                    'getPhysicalRect', {'handle': hwnd});
            final curW = (currentRect?['w'] as int?) ?? bounds.width.toInt();
            final curH = (currentRect?['h'] as int?) ?? bounds.height.toInt();

            // Apply content alignment offset relative to primary.
            int finalY = bounds.top.toInt();
            if (child.contentAlignment != null) {
              final alignFactor = (child.contentAlignment!.y + 1) / 2;
              finalY = (newBounds.top + (newBounds.height - curH) * alignFactor).toInt();
            }

            await _nativeCh.invokeMethod('setWindowPos', {
              'handle': hwnd,
              'frame': {
                'x': bounds.left.toInt(),
                'y': finalY,
                'w': curW,
                'h': curH,
              },
            });
          } else {
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

        // Pipeline: Position (above) → Z-order → Shadow enforce.
        _requestClusterReconcile(
          primaryHwnd: primaryHwnd,
          children: children,
          hwnds: hwnds,
          config: config,
          primary: primary,
        );
      }

      // When any cluster window gains focus (taskbar click, Alt+Tab,
      // child window click), reassert the z-order stack so children
      // stay above primary and nothing drops behind.
      if (type == 'WINDOW_FOCUSED') {
        _requestClusterReconcile(
          primaryHwnd: primaryHwnd,
          children: children,
          hwnds: hwnds,
          config: config,
          primary: primary,
        );
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
      // Overlay shadow policy (independent).
      _requestOverlayReconcile(
        overlays: overlays,
        hwnds: hwnds,
        config: config,
      );
      // Cluster z-order may be corrupted after minimize/restore cycle.
      _requestClusterReconcile(
        primaryHwnd: primaryHwnd,
        children: children,
        hwnds: hwnds,
        config: config,
        primary: primary,
      );
    }

    Future<void> doDrag(Map<dynamic, dynamic>? args) async {
      await _nativeCh.invokeMethod('dragPrimaryWindow', args);
      // OS reorders windows during drag. Reassert z-order immediately.
      _requestClusterReconcile(
        primaryHwnd: primaryHwnd,
        children: children,
        hwnds: hwnds,
        config: config,
        primary: primary,
      );
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
        case 'navigate':
          final index = call.arguments as int? ?? 0;
          ClusterScope.onNavigate?.call(index);
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

    // Make the child's rendering surface transparent for DWM backdrop.
    try {
      await acrylic.Window.initialize();
    } catch (_) {}

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

    // Expose the completer to the shrink-to-content wrapper.
    if (surface.shrinkToContent) {
      _parentReadyCompleter = readyCompleter;
    }

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

    // Apply acrylic effect from within the child's engine context.
    // Each child window has its own Flutter engine — flutter_acrylic's
    // Window.setEffect() must be called here (not from the parent) to
    // make THIS engine's rendering surface transparent.
    if (surface.visual.backdrop != BackdropType.none) {
      try {
        final effect = _mapBackdropToWindowEffect(surface.visual.backdrop);
        await acrylic.Window.setEffect(
          effect: effect,
          dark: true,
        );
        debugPrint('[Cluster] Child ${surface.id} backdrop: ${surface.visual.backdrop.name} (via flutter_acrylic)');
      } catch (e) {
        debugPrint('[Cluster] Child ${surface.id} backdrop failed: $e');
      }
    }

    // Build the widget tree, optionally wrapping with shrink-to-content.
    Widget app = surface.builder();
    if (surface.shrinkToContent) {
      app = _ShrinkToContentWrapper(
        maxSize: surface.size,
        contentAlignment: surface.contentAlignment,
        child: app,
      );
    }
    runApp(app);
  }

  // ---------------------------------------------------------------------------
  // Orchestrator — single pipeline, serialized, debounced
  // ---------------------------------------------------------------------------

  /// Pipeline version counter for structured log tracing.
  static int _version = 0;

  /// Serialization lock. Only one reconcile pipeline runs at a time.
  static Future<void> _pipelineLock = Future.value();

  /// Debounce timer. Collapses event bursts into one execution.
  /// scheduleMicrotask is too eager — platform channel messages arrive
  /// on separate event loop ticks. A 16ms timer (~1 frame) properly
  /// coalesces drag events (60 events/sec → 1 reconcile).
  static Timer? _reconcileTimer;

  /// Idempotent shadow cache keyed by HWND (not surface ID).
  /// Tracks actual OS state. Cleared on window recreate / cluster restart.
  static final Set<int> _shadowDisabledHandles = {};

  /// Clears the shadow cache. Call on window recreate or cluster restart.
  static void _clearShadowCache() => _shadowDisabledHandles.clear();

  /// Schedules a cluster reconciliation (debounced, serialized).
  ///
  /// Call from any cluster trigger (move, resize, focus).
  /// Never call [_reconcileZOrder] or [_enforceShadowPolicy] directly.
  /// Overlays do NOT trigger this — they use [_requestOverlayReconcile].
  static void _requestClusterReconcile({
    required int primaryHwnd,
    required List<ClusterSurface> children,
    required Map<String, int> hwnds,
    required ClusterVisualConfig config,
    required ClusterSurface primary,
  }) {
    _reconcileTimer?.cancel();
    _reconcileTimer = Timer(const Duration(milliseconds: 16), () {
      _pipelineLock = _pipelineLock.then((_) async {
        final v = ++_version;
        try {
          await _reconcileZOrder(
            primaryHwnd: primaryHwnd,
            children: children,
            hwnds: hwnds,
            version: v,
          );
          await _enforceShadowPolicy(
            config: config,
            primary: primary,
            children: children,
            primaryHwnd: primaryHwnd,
            hwnds: hwnds,
            version: v,
          );
          debugPrint('[Cluster][v$v][reconcile] Complete');
        } catch (e) {
          debugPrint('[Cluster][v$v][ERROR] Reconcile failed: $e');
        }
      });
    });
  }

  /// Overlay-specific reconciliation. Independent from cluster z-order.
  static void _requestOverlayReconcile({
    required List<ClusterSurface> overlays,
    required Map<String, int> hwnds,
    required ClusterVisualConfig config,
  }) {
    _pipelineLock = _pipelineLock.then((_) async {
      final v = ++_version;
      if (!config.allowOverlayShadow) {
        for (final overlay in overlays) {
          final hwnd = hwnds[overlay.id];
          if (hwnd == null || _shadowDisabledHandles.contains(hwnd)) continue;
          try {
            final hasBackdrop = overlay.visual.backdrop != BackdropType.none;
            await _nativeCh.invokeMethod('removeShadow', {
              'handle': hwnd,
              'preserveMargins': hasBackdrop,
            });
            _shadowDisabledHandles.add(hwnd);
            debugPrint('[Cluster][v$v][shadow] Overlay ${overlay.id} removed');
          } catch (e) {
            debugPrint('[Cluster][v$v][ERROR] Overlay shadow: $e');
          }
        }
      }
    });
  }

  /// Rebuilds the cluster z-order stack relative to the primary window.
  ///
  /// PURE — only setZOrder calls. No side effects.
  /// Does NOT touch the primary's global z-position (that's OS-managed).
  /// Children are stacked above primary in layer order.
  static Future<void> _reconcileZOrder({
    required int primaryHwnd,
    required List<ClusterSurface> children,
    required Map<String, int> hwnds,
    required int version,
  }) async {
    // Sort by layer ascending: base → panel → chrome.
    final ordered = children
        .where((c) => hwnds.containsKey(c.id))
        .toList()
      ..sort((a, b) => a.visual.layer.compareTo(b.visual.layer));

    // Stack each child above the previous one, starting from primary.
    // Primary keeps its global z-position — we only control relative
    // ordering within the cluster.
    for (int i = 0; i < ordered.length; i++) {
      final hwnd = hwnds[ordered[i].id];
      if (hwnd == null) continue;

      final insertAfter = i == 0
          ? primaryHwnd
          : hwnds[ordered[i - 1].id] ?? primaryHwnd;

      try {
        await _nativeCh.invokeMethod('setZOrder', {
          'handle': hwnd,
          'insertAfter': insertAfter,
        });
        debugPrint('[Cluster][v$version][zorder] ${ordered[i].id} → ${ordered[i].visual.layer.name}');
      } catch (e) {
        debugPrint('[Cluster][v$version][zorder] Failed ${ordered[i].id}: $e');
      }
    }
  }

  /// Enforces shadow ownership. Idempotent — keyed by HWND.
  /// Only touches cluster surfaces. Overlays handled separately.
  static Future<void> _enforceShadowPolicy({
    required ClusterVisualConfig config,
    required ClusterSurface primary,
    required List<ClusterSurface> children,
    required int primaryHwnd,
    required Map<String, int> hwnds,
    required int version,
  }) async {
    if (primary.id != config.shadowOwnerId &&
        !_shadowDisabledHandles.contains(primaryHwnd)) {
      try {
        await windowManager.setHasShadow(false);
        _shadowDisabledHandles.add(primaryHwnd);
        debugPrint('[Cluster][v$version][shadow] Primary disabled');
      } catch (_) {}
    }

    for (final child in children) {
      if (child.id == config.shadowOwnerId) continue;
      final hwnd = hwnds[child.id];
      if (hwnd == null || _shadowDisabledHandles.contains(hwnd)) continue;

      // Shadow was already killed at source by prepareChildComposition.
      // Just mark as disabled in cache — no native call needed.
      _shadowDisabledHandles.add(hwnd);
      debugPrint('[Cluster][v$version][shadow] Cached ${child.id}');
    }
  }
}

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

  /// Callback for navigation commands from child windows.
  static void Function(int index)? onNavigate;

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
  final Alignment? contentAlignment;
  final Widget child;

  const _ShrinkToContentWrapper({
    required this.maxSize,
    this.contentAlignment,
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
    // Wait for the parent to position us via setWindowPos, then shrink.
    if (_parentReadyCompleter != null) {
      _parentReadyCompleter!.future.then((_) {
        // Small delay so the parent's setWindowPos settles.
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _measureAndShrink());
          }
        });
      }).timeout(const Duration(seconds: 5), onTimeout: () {
        // Fallback: shrink even if parentReady never arrived.
        if (mounted && !_didShrink) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _measureAndShrink());
        }
      });
    } else {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _measureAndShrink());
    }
  }

  Future<void> _measureAndShrink() async {
    if (_didShrink) return;
    _didShrink = true;

    final renderBox =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final contentSize = renderBox.size;

    // Add a small buffer to prevent sub-pixel overflow from DPI rounding.
    final bufferedWidth = contentSize.width + 2;
    final bufferedHeight = contentSize.height + 2;

    // Clamp to maxSize.
    final newWidth = widget.maxSize.width > 0
        ? bufferedWidth.clamp(0.0, widget.maxSize.width)
        : bufferedWidth;
    final newHeight = widget.maxSize.height > 0
        ? bufferedHeight.clamp(0.0, widget.maxSize.height)
        : bufferedHeight;

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

      // Reposition based on contentAlignment if specified.
      if (widget.contentAlignment != null) {
        try {
          // Get the primary window's HWND by finding the runner window.
          final currentRect = await _nativeCh
              .invokeMethod<Map<dynamic, dynamic>>(
                  'getPhysicalRect', {'handle': hwnd});
          if (currentRect != null) {
            final curX = (currentRect['x'] as int?) ?? 0;
            final curY = (currentRect['y'] as int?) ?? 0;
            // Keep X, apply vertical alignment relative to the window height
            // (the parent will reposition us on subsequent moves).
            await _nativeCh.invokeMethod('setWindowPos', {
              'handle': hwnd,
              'frame': {
                'x': curX,
                'y': curY,
                'w': physW,
                'h': physH,
              },
            });
          }
        } catch (e) {
          debugPrint('[Cluster] Content alignment reposition failed: $e');
        }
      }

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
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: KeyedSubtree(
            key: _contentKey,
            child: widget.child,
          ),
        ),
      ],
    ),
    );
  }
}
