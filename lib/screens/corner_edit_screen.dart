import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../src/rust/api.dart';

class CornerBatchItem {
  CornerBatchItem({required this.imagePath, required this.quad});

  final String imagePath;
  Quad quad;
}

class CornerEditScreen extends StatefulWidget {
  const CornerEditScreen._({
    required this.items,
    required this.isBatch,
  });

  factory CornerEditScreen.single({
    required String imagePath,
    required Quad initialQuad,
  }) => CornerEditScreen._(
    items: [CornerBatchItem(imagePath: imagePath, quad: initialQuad)],
    isBatch: false,
  );

  factory CornerEditScreen.batch({required List<CornerBatchItem> items}) =>
      CornerEditScreen._(
        items: items
            .map((e) => CornerBatchItem(imagePath: e.imagePath, quad: e.quad))
            .toList(),
        isBatch: true,
      );

  final List<CornerBatchItem> items;
  final bool isBatch;

  @override
  State<CornerEditScreen> createState() => _CornerEditScreenState();
}

class _CornerEditScreenState extends State<CornerEditScreen> {
  int _index = 0;
  // 0..3 = corner handles [TL, TR, BR, BL], 4..7 = edge midpoint handles [Top, Right, Bottom, Left].
  int? _draggingHandle;
  bool _redetecting = false;
  ui.Image? _decodedImage;

  CornerBatchItem get _current => widget.items[_index];

  @override
  void initState() {
    super.initState();
    _loadCurrentImage();
  }

  @override
  void dispose() {
    _decodedImage?.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentImage() async {
    final path = _current.imagePath;
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1400);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || _current.imagePath != path) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _decodedImage?.dispose();
        _decodedImage = frame.image;
      });
    } catch (_) {}
  }

  Future<void> _redetect() async {
    setState(() => _redetecting = true);
    try {
      final quad = await detectCornersFromFile(path: _current.imagePath);
      if (mounted) {
        setState(() => _current.quad = quad);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _redetecting = false);
    }
  }

  void _setFullImage() {
    setState(() => _current.quad = fullFrameQuad);
  }

  void _goTo(int nextIndex) {
    if (nextIndex < 0 || nextIndex >= widget.items.length) return;
    setState(() {
      _index = nextIndex;
      _draggingHandle = null;
      _decodedImage?.dispose();
      _decodedImage = null;
    });
    _loadCurrentImage();
  }

  void _confirm() {
    if (widget.isBatch) {
      Navigator.of(context).pop(widget.items);
    } else {
      Navigator.of(context).pop(_current.quad);
    }
  }

  Rect _computeImageRect(Size boxSize, ui.Image img) {
    final imgAspect = img.width / img.height;
    final boxAspect = boxSize.width / boxSize.height;
    double w, h;
    if (imgAspect > boxAspect) {
      w = boxSize.width;
      h = w / imgAspect;
    } else {
      h = boxSize.height;
      w = h * imgAspect;
    }
    return Rect.fromLTWH(
      (boxSize.width - w) / 2,
      (boxSize.height - h) / 2,
      w,
      h,
    );
  }

  /// Ensures all 4 corners remain strictly clockwise-convex with non-degenerate edge lengths.
  bool _isValidConvexQuad(List<(double, double)> pts) {
    if (pts.length != 4) return false;
    for (var i = 0; i < 4; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % 4];
      final c = pts[(i + 2) % 4];
      final edgeLen = hypot(b.$1 - a.$1, b.$2 - a.$2);
      if (edgeLen < 0.05) return false;
      final cross = (b.$1 - a.$1) * (c.$2 - b.$2) - (b.$2 - a.$2) * (c.$1 - b.$1);
      if (cross <= 1e-4) return false;
    }
    return true;
  }

  double hypot(double dx, double dy) => sqrt(dx * dx + dy * dy);

  Offset? _activeFocusNorm() {
    final idx = _draggingHandle;
    if (idx == null || _current.quad.pts.length != 4) return null;
    if (idx < 4) {
      final p = _current.quad.pts[idx];
      return Offset(p.$1, p.$2);
    }
    final i = idx - 4;
    final j = (i + 1) % 4;
    final a = _current.quad.pts[i];
    final b = _current.quad.pts[j];
    return Offset((a.$1 + b.$1) * 0.5, (a.$2 + b.$2) * 0.5);
  }

  void _onPanStart(DragStartDetails details, Rect imgRect) {
    final local = details.localPosition;
    var bestIdx = -1;
    var bestDist = 48.0;

    // Corner handles take priority over edge midpoints.
    for (var i = 0; i < 4; i++) {
      final p = _current.quad.pts[i];
      final screenPt = Offset(
        imgRect.left + p.$1 * imgRect.width,
        imgRect.top + p.$2 * imgRect.height,
      );
      final d = (screenPt - local).distance;
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }

    if (bestIdx == -1) {
      bestDist = 36.0;
      for (var i = 0; i < 4; i++) {
        final a = _current.quad.pts[i];
        final b = _current.quad.pts[(i + 1) % 4];
        final mid = Offset(
          imgRect.left + (a.$1 + b.$1) * 0.5 * imgRect.width,
          imgRect.top + (a.$2 + b.$2) * 0.5 * imgRect.height,
        );
        final d = (mid - local).distance;
        if (d < bestDist) {
          bestDist = d;
          bestIdx = 4 + i;
        }
      }
    }

    if (bestIdx != -1) {
      HapticFeedback.selectionClick();
      setState(() => _draggingHandle = bestIdx);
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Rect imgRect) {
    final idx = _draggingHandle;
    if (idx == null) return;
    final updated = List<(double, double)>.from(_current.quad.pts);

    if (idx < 4) {
      final nx = ((details.localPosition.dx - imgRect.left) / imgRect.width)
          .clamp(0.0, 1.0);
      final ny = ((details.localPosition.dy - imgRect.top) / imgRect.height)
          .clamp(0.0, 1.0);
      updated[idx] = (nx, ny);
    } else {
      final edgeIdx = idx - 4;
      final i = edgeIdx;
      final j = (edgeIdx + 1) % 4;
      final dx = details.delta.dx / imgRect.width;
      final dy = details.delta.dy / imgRect.height;
      updated[i] = (
        (updated[i].$1 + dx).clamp(0.0, 1.0),
        (updated[i].$2 + dy).clamp(0.0, 1.0),
      );
      updated[j] = (
        (updated[j].$1 + dx).clamp(0.0, 1.0),
        (updated[j].$2 + dy).clamp(0.0, 1.0),
      );
    }

    if (_isValidConvexQuad(updated)) {
      setState(() => _current.quad = Quad(pts: updated));
    }
  }

  void _onPanEnd(DragEndDetails _) {
    if (_draggingHandle != null) {
      setState(() => _draggingHandle = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final title = widget.isBatch && total > 1
        ? 'Edit Sudut (${_index + 1}/$total)'
        : 'Edit Sudut';

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        foregroundColor: AppColors.textPrimaryDark,
        title: Text(
          title,
          style: const TextStyle(color: AppColors.textPrimaryDark),
        ),
        actions: [
          if (widget.isBatch && total > 1) ...[
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _index < total - 1 ? () => _goTo(_index + 1) : null,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final img = _decodedImage;
                  if (img == null) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }
                  final boxSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final imgRect = _computeImageRect(boxSize, img);
                  final dragIdx = _draggingHandle;
                  final activeFocus = _activeFocusNorm();

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (d) => _onPanStart(d, imgRect),
                    onPanUpdate: (d) => _onPanUpdate(d, imgRect),
                    onPanEnd: _onPanEnd,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: _CornerEditorPainter(
                            image: img,
                            imageRect: imgRect,
                            quad: _current.quad,
                            activeHandle: dragIdx,
                          ),
                        ),
                        // Loupe magnifier rendered opposite the active handle while dragging.
                        if (activeFocus != null)
                          Positioned(
                            top: 8,
                            left: activeFocus.dx > 0.5 ? 8 : null,
                            right: activeFocus.dx <= 0.5 ? 8 : null,
                            child: Container(
                              width: 116,
                              height: 116,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.cameraQuad,
                                  width: 2.5,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black54,
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: CustomPaint(
                                  painter: _LoupePainter(
                                    image: img,
                                    quad: _current.quad,
                                    normalizedFocus: activeFocus,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          Container(
            color: AppColors.surfaceDark,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimaryDark,
                      side: const BorderSide(color: AppColors.borderDark),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: _redetecting ? null : _redetect,
                    icon: _redetecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.yellow,
                            ),
                          )
                        : const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: const Text('Deteksi ulang'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimaryDark,
                      side: const BorderSide(color: AppColors.borderDark),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: _setFullImage,
                    child: const Text('Seluruh'),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.yellow,
                      foregroundColor: AppColors.charcoal,
                    ),
                    onPressed: _confirm,
                    child: Text(
                      widget.isBatch && total > 1 ? 'Terapkan' : 'Simpan',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerEditorPainter extends CustomPainter {
  const _CornerEditorPainter({
    required this.image,
    required this.imageRect,
    required this.quad,
    required this.activeHandle,
  });

  final ui.Image image;
  final Rect imageRect;
  final Quad quad;
  final int? activeHandle;

  @override
  void paint(Canvas canvas, Size size) {
    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      srcRect,
      imageRect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    if (quad.pts.length != 4) return;
    final pts = quad.pts
        .map(
          (p) => Offset(
            imageRect.left + p.$1 * imageRect.width,
            imageRect.top + p.$2 * imageRect.height,
          ),
        )
        .toList(growable: false);

    final quadPath = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();

    // Dim outside area subtly.
    final overlayPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(imageRect),
      quadPath,
    );
    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    canvas.drawPath(
      quadPath,
      Paint()
        ..color = AppColors.cameraQuad
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );

    // Edge midpoint handles for parallel side adjustment.
    for (var i = 0; i < 4; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % 4];
      final mid = Offset((a.dx + b.dx) * 0.5, (a.dy + b.dy) * 0.5);
      final isSelected = activeHandle == 4 + i;
      final r = isSelected ? 8.5 : 6.0;
      canvas.drawCircle(
        mid,
        r,
        Paint()
          ..color = isSelected
              ? AppColors.stableGreen
              : AppColors.cameraQuad.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        mid,
        r,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    }

    // Corner handles.
    for (var i = 0; i < 4; i++) {
      final isSelected = activeHandle == i;
      final r = isSelected ? 14.0 : 11.0;
      canvas.drawCircle(
        pts[i],
        r,
        Paint()
          ..color = isSelected ? AppColors.stableGreen : AppColors.yellow,
      );
      canvas.drawCircle(
        pts[i],
        r,
        Paint()
          ..color = AppColors.charcoal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CornerEditorPainter oldDelegate) => true;
}

class _LoupePainter extends CustomPainter {
  const _LoupePainter({
    required this.image,
    required this.quad,
    required this.normalizedFocus,
  });

  final ui.Image image;
  final Quad quad;
  final Offset normalizedFocus;

  @override
  void paint(Canvas canvas, Size size) {
    final fx = normalizedFocus.dx * image.width;
    final fy = normalizedFocus.dy * image.height;
    final sampleSide = min(image.width, image.height) * 0.16;
    final src = Rect.fromCenter(
      center: Offset(fx, fy),
      width: sampleSide,
      height: sampleSide,
    );
    final dst = Offset.zero & size;
    canvas.drawRect(dst, Paint()..color = Colors.black);
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );

    // Draw the quad's actual boundary edges in magnified coordinates for pixel-accurate alignment.
    if (quad.pts.length == 4) {
      final scaleX = size.width / src.width;
      final scaleY = size.height / src.height;
      final mapped = quad.pts
          .map(
            (p) => Offset(
              (p.$1 * image.width - src.left) * scaleX,
              (p.$2 * image.height - src.top) * scaleY,
            ),
          )
          .toList(growable: false);
      final quadPath = Path()
        ..moveTo(mapped[0].dx, mapped[0].dy)
        ..lineTo(mapped[1].dx, mapped[1].dy)
        ..lineTo(mapped[2].dx, mapped[2].dy)
        ..lineTo(mapped[3].dx, mapped[3].dy)
        ..close();
      canvas.drawPath(
        quadPath,
        Paint()
          ..color = AppColors.cameraQuad.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    }

    // Precision crosshair at center.
    final c = size.center(Offset.zero);
    final linePaint = Paint()
      ..color = AppColors.stableGreen
      ..strokeWidth = 1.6;
    canvas.drawLine(Offset(c.dx - 12, c.dy), Offset(c.dx + 12, c.dy), linePaint);
    canvas.drawLine(Offset(c.dx, c.dy - 12), Offset(c.dx, c.dy + 12), linePaint);
  }

  @override
  bool shouldRepaint(covariant _LoupePainter oldDelegate) =>
      oldDelegate.normalizedFocus != normalizedFocus ||
      oldDelegate.quad != quad ||
      oldDelegate.image != image;
}
