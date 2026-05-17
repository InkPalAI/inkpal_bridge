import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../bridge/inkpal_run_app.dart' show inkpalRootRepaintKey;

/// The result of attempting a screenshot. Either [bytes] is non-null OR
/// [error] explains why capture failed — never both, never neither.
///
/// Surfacing the underlying error string (instead of swallowing exceptions
/// behind a generic message) lets the VM-extension caller log a real cause
/// for "Screenshot capture failed" failures encountered in the field.
class ScreenshotResult {
  /// PNG-encoded bytes when capture succeeded.
  final Uint8List? bytes;

  /// Human-readable failure cause when [bytes] is null. Truncated to a few
  /// hundred chars so it round-trips through service-extension JSON safely.
  final String? error;

  const ScreenshotResult.success(Uint8List this.bytes) : error = null;
  const ScreenshotResult.failure(String this.error) : bytes = null;

  bool get ok => bytes != null;
}

/// Captures screenshots of the app content for visual LLM context.
///
/// Uses a [RepaintBoundary] key to capture only the app content,
/// then downscales to [targetWidth] to keep the payload manageable
/// for LLM APIs (~100-200KB PNG).
class ScreenshotCapture {
  /// Key of the [RepaintBoundary] wrapping the app content.
  final GlobalKey appContentKey;

  /// Target width in pixels. Height is scaled proportionally.
  final int targetWidth;

  const ScreenshotCapture({
    required this.appContentKey,
    this.targetWidth = 720,
  });

  /// Capture the app content as PNG bytes.
  ///
  /// Returns null if capture fails (e.g. widget not mounted, no render
  /// object). Prefer [captureWithDiagnostics] when you need to surface the
  /// underlying error to a tooling caller.
  Future<Uint8List?> capture() async {
    final result = await captureWithDiagnostics();
    return result.bytes;
  }

  /// Capture the app content with a structured success/error result.
  ///
  /// Tries the configured [appContentKey] first, then falls back to the
  /// package-wide [inkpalRootRepaintKey] (installed by `inkpalRunApp`) so
  /// apps that wrap their root via the convenience runner always have a
  /// boundary to capture from.
  Future<ScreenshotResult> captureWithDiagnostics() async {
    try {
      return await _captureImpl().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('[InkPal] Screenshot capture timed out after 5s');
          return const ScreenshotResult.failure(
            'Screenshot capture timed out after 5s',
          );
        },
      );
    } catch (e, stackTrace) {
      debugPrint('[InkPal] Screenshot capture failed: $e');
      // Truncate to keep the JSON payload bounded — the first ~800 chars
      // of stack are enough to identify the offending frame.
      final detail = '$e\n$stackTrace';
      return ScreenshotResult.failure(
        detail.length > 800 ? detail.substring(0, 800) : detail,
      );
    }
  }

  Future<ScreenshotResult> _captureImpl() async {
    // 1. Try the explicitly-configured key (the bridge's own key by default).
    var boundary = _resolveBoundary(appContentKey);

    // 2. Fall back to the global key installed by `inkpalRunApp` — apps that
    //    use the convenience runner always have this wired even if they
    //    don't pass the bridge's repaintBoundaryKey to their root manually.
    if (boundary == null && !identical(appContentKey, inkpalRootRepaintKey)) {
      boundary = _resolveBoundary(inkpalRootRepaintKey);
      if (boundary != null) {
        debugPrint('[InkPal] Screenshot: using inkpalRunApp root boundary');
      }
    }

    if (boundary == null) {
      // Zero-config fallback — composite the live layer tree of the first
      // RenderView into a new Scene. Works on any running Flutter app
      // regardless of whether the caller used `inkpalRunApp` or wired a
      // RepaintBoundary manually. Slightly more expensive than the
      // repaint-boundary path but the API shape is identical so callers
      // never need to know which path ran.
      debugPrint(
        '[InkPal] Screenshot: no RenderRepaintBoundary — '
        'falling back to RenderView layer composite',
      );
      final layerShot = await _captureFromRenderView();
      if (layerShot != null) return ScreenshotResult.success(layerShot);
      return const ScreenshotResult.failure(
        'No RenderRepaintBoundary found and RenderView layer composite '
        'produced no bytes. Wrap your root via `inkpalRunApp(...)` '
        'or `RepaintBoundary(key: inkpalRootRepaintKey, child: ...)` '
        'if the fallback is not picking up your content.',
      );
    }

    final logicalWidth = boundary.size.width;
    if (logicalWidth <= 0) {
      return const ScreenshotResult.failure(
        'RepaintBoundary has zero logical width — first frame may not have '
        'rendered yet. Try again after the first paint.',
      );
    }

    final pixelRatio = targetWidth / logicalWidth;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final imageWidth = image.width;
    final imageHeight = image.height;
    image.dispose();

    if (byteData == null) {
      return const ScreenshotResult.failure(
        'toByteData returned null — image encoding failed.',
      );
    }

    final bytes = byteData.buffer.asUint8List();
    debugPrint(
      '[InkPal] Screenshot captured: ${bytes.length} bytes '
      '(${imageWidth}x$imageHeight)',
    );
    return ScreenshotResult.success(bytes);
  }

  RenderRepaintBoundary? _resolveBoundary(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is RenderRepaintBoundary) return renderObject;
    return null;
  }

  /// Fallback capture path — composites the current RenderView layer tree
  /// into a new Scene and renders it to an image, without relying on any
  /// app-side RepaintBoundary. Covers apps that initialise the bridge
  /// manually (skipping `inkpalRunApp`) and multi-view apps where the
  /// configured key lives on a non-primary view.
  Future<Uint8List?> _captureFromRenderView() async {
    final views = WidgetsBinding.instance.renderViews;
    if (views.isEmpty) {
      debugPrint('[InkPal] Screenshot fallback: no renderViews');
      return null;
    }
    final view = views.first;
    final rootLayer = view.debugLayer;
    if (rootLayer is! ContainerLayer) {
      debugPrint(
        '[InkPal] Screenshot fallback: RenderView has no root container layer',
      );
      return null;
    }

    final logicalSize = view.size;
    if (logicalSize.width <= 0 || logicalSize.height <= 0) {
      debugPrint('[InkPal] Screenshot fallback: RenderView logical size is zero');
      return null;
    }

    final devicePixelRatio = view.configuration.devicePixelRatio;
    final pixelRatio = (targetWidth / logicalSize.width).clamp(
      0.1,
      devicePixelRatio,
    );
    final pixelWidth = (logicalSize.width * pixelRatio).round();
    final pixelHeight = (logicalSize.height * pixelRatio).round();
    if (pixelWidth <= 0 || pixelHeight <= 0) return null;

    // Build a scene from the live layer tree. toImage composites offscreen
    // — nothing is pushed to the on-screen rasterizer.
    final scene = rootLayer.buildScene(ui.SceneBuilder());
    try {
      final image = await scene.toImage(pixelWidth, pixelHeight);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return byteData?.buffer.asUint8List();
    } finally {
      scene.dispose();
    }
  }
}
