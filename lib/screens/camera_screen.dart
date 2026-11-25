import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../src/rust/api.dart';
import '../state/providers.dart';

enum _CaptureMode { document, idCard }

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key, this.existingDocId});

  /// When non-null, captured pages are appended to this document (document mode only).
  final String? existingDocId;

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initializing = true;
  bool _permissionDenied = false;
  String? _errorMsg;

  bool _flashOn = false;
  bool _autoCapture = true;
  bool _showGrid = false;
  bool _capturing = false;
  bool _shutterLocked = false;
  bool _shutterFlash = false;
  bool _finishing = false;
  Timer? _shutterCooldownTimer;
  Timer? _shutterFlashTimer;

  static const int _detectIntervalMs = 140;
  static const int _shutterCooldownMs = 1000;
  static const int _autoCaptureCooldownMs = 2000;
  static const int _maxMissedFrames = 2;

  // Tap-to-focus & exposure controls.
  Offset? _focusPointNorm;
  Timer? _focusHideTimer;
  bool _showExposure = false;
  double _minExposure = -2.0;
  double _maxExposure = 2.0;
  double _exposure = 0.0;

  // Scan mode: regular document vs 2-sided ID card (KTP -> single A4).
  _CaptureMode _mode = _CaptureMode.document;
  String? _idFrontPath;

  // Live corner detection state (throttled to ~7 fps with EMA smoothing).
  bool _detectingFrame = false;
  DateTime _lastDetectAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCaptureAt = DateTime.fromMillisecondsSinceEpoch(0);
  Quad? _liveQuad;
  int _missedFrames = 0;
  DateTime? _stableSince;
  double _stableProgress = 0.0;

  // Background capture processing queue.
  String? _docId;
  Future<void> _queue = Future.value();
  int _capturedCount = 0;
  int _pendingJobs = 0;
  String? _lastThumbPath;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appSettingsProvider);
    _autoCapture = settings.autoCaptureDefault;
    _showGrid = settings.showGridDefault;
    _docId = widget.existingDocId;
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    _focusHideTimer?.cancel();
    _shutterCooldownTimer?.cancel();
    _shutterFlashTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _disposeController();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;
    if (state == AppLifecycleState.inactive) {
      _disposeController();
    } else if (state == AppLifecycleState.resumed && !_finishing) {
      _initCamera();
    }
  }

  Future<void> _disposeController() async {
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) {
      try {
        if (ctrl.value.isStreamingImages) {
          await ctrl.stopImageStream();
        }
      } catch (_) {}
      await ctrl.dispose();
    }
  }

  Future<void> _initCamera() async {
    if (!mounted) return;
    setState(() {
      _initializing = true;
      _permissionDenied = false;
      _errorMsg = null;
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _initializing = false;
            _errorMsg = 'Tidak ada kamera yang ditemukan pada perangkat ini.';
          });
        }
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      CameraController? ctrl;
      Object? lastInitErr;
      for (final preset in const [
        ResolutionPreset.max,
        ResolutionPreset.veryHigh,
        ResolutionPreset.high,
      ]) {
        final candidate = CameraController(
          back,
          preset,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        try {
          await candidate.initialize();
          ctrl = candidate;
          break;
        } catch (e) {
          lastInitErr = e;
          await candidate.dispose();
        }
      }
      if (ctrl == null) {
        throw lastInitErr ?? CameraException('init_failed', 'Kamera gagal diinisialisasi.');
      }
      if (!mounted) {
        await ctrl.dispose();
        return;
      }

      try {
        _minExposure = await ctrl.getMinExposureOffset();
        _maxExposure = await ctrl.getMaxExposureOffset();
      } catch (_) {
        _minExposure = -2.0;
        _maxExposure = 2.0;
      }

      _controller = ctrl;
      await _startStream();
      setState(() => _initializing = false);
    } on CameraException catch (e) {
      final code = e.code.toLowerCase();
      final denied =
          code.contains('accessdenied') || code.contains('permission');
      if (mounted) {
        setState(() {
          _initializing = false;
          _permissionDenied = denied;
          _errorMsg = denied
              ? null
              : 'Kamera gagal dibuka (${e.description ?? e.code}).';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _errorMsg = formatError(e);
        });
      }
    }
  }

  Future<void> _startStream() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isStreamingImages) return;
    try {
      await ctrl.startImageStream(_onCameraImage);
    } catch (_) {}
  }

  void _onCameraImage(CameraImage image) {
    if (_detectingFrame || _capturing || _finishing) return;
    final now = DateTime.now();
    if (now.difference(_lastDetectAt).inMilliseconds < _detectIntervalMs) return;
    if (image.planes.isEmpty) return;

    _detectingFrame = true;
    _lastDetectAt = now;

    final plane = image.planes.first;
    final yCopy = Uint8List.fromList(plane.bytes);
    final width = image.width;
    final height = image.height;
    final rowStride = plane.bytesPerRow;
    final sensorDeg = _controller?.description.sensorOrientation ?? 90;
    final deviceDeg = switch (_controller?.value.deviceOrientation) {
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
      _ => 0,
    };
    final rotation = (sensorDeg - deviceDeg + 360) % 360;

    unawaited(_runLiveDetection(yCopy, width, height, rowStride, rotation));
  }

  /// Remaps normalized quad coordinates from rotated YUV buffer space into
  /// CameraPreview space when the camera stream and preview have different aspect ratios.
  Quad _mapYuvQuadToPreview(Quad raw, int width, int height, int rotationDeg) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return raw;
    final rot = (rotationDeg % 360) ~/ 90 * 90;
    final yuvW = (rot == 90 || rot == 270) ? height.toDouble() : width.toDouble();
    final yuvH = (rot == 90 || rot == 270) ? width.toDouble() : height.toDouble();
    if (yuvW <= 0 || yuvH <= 0) return raw;

    final yuvAspect = yuvW / yuvH;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final previewAspect =
        isLandscape ? ctrl.value.aspectRatio : (1.0 / ctrl.value.aspectRatio);
    if ((yuvAspect - previewAspect).abs() < 0.02) return raw;

    if (yuvAspect > previewAspect) {
      // YUV stream is wider than preview: center-crop horizontally.
      final visX = previewAspect / yuvAspect;
      final marginX = (1.0 - visX) * 0.5;
      return Quad(
        pts: raw.pts
            .map((p) => (((p.$1 - marginX) / visX).clamp(0.0, 1.0), p.$2))
            .toList(growable: false),
      );
    } else {
      // YUV stream is taller than preview: center-crop vertically.
      final visY = yuvAspect / previewAspect;
      final marginY = (1.0 - visY) * 0.5;
      return Quad(
        pts: raw.pts
            .map((p) => (p.$1, ((p.$2 - marginY) / visY).clamp(0.0, 1.0)))
            .toList(growable: false),
      );
    }
  }

  Quad _lerpQuad(Quad a, Quad b, double alpha) {
    if (a.pts.length != 4 || b.pts.length != 4) return b;
    return Quad(
      pts: List.generate(4, (i) {
        final x = a.pts[i].$1 + (b.pts[i].$1 - a.pts[i].$1) * alpha;
        final y = a.pts[i].$2 + (b.pts[i].$2 - a.pts[i].$2) * alpha;
        return (x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
      }, growable: false),
    );
  }

  Future<void> _runLiveDetection(
    Uint8List yBytes,
    int width,
    int height,
    int rowStride,
    int rotationDeg,
  ) async {
    try {
      final quad = await detectCornersLive(
        y: yBytes,
        width: width,
        height: height,
        rowStride: rowStride,
        rotationDeg: rotationDeg,
      );
      if (!mounted) return;

      final now = DateTime.now();
      if (quad == null) {
        _missedFrames += 1;
        if (_missedFrames > _maxMissedFrames) {
          setState(() {
            _liveQuad = null;
            _stableSince = null;
            _stableProgress = 0.0;
          });
        } else if (_stableSince != null) {
          setState(() {
            _stableSince = null;
            _stableProgress = 0.0;
          });
        }
        return;
      }

      _missedFrames = 0;
      final mapped = _mapYuvQuadToPreview(quad, width, height, rotationDeg);
      final prev = _liveQuad;
      final delta = prev != null ? _quadDelta(prev, mapped) : 1.0;

      // Adaptive EMA: smooth micro-jitter when steady, snap quickly on deliberate motion.
      final smoothed = prev == null
          ? mapped
          : delta < 0.04
          ? _lerpQuad(prev, mapped, 0.35)
          : delta < 0.14
          ? _lerpQuad(prev, mapped, 0.60)
          : mapped;

      final isStable = prev != null && delta < 0.028;
      if (isStable) {
        _stableSince ??= now;
        final elapsed = now.difference(_stableSince!).inMilliseconds;
        final progress = (elapsed / 1000.0).clamp(0.0, 1.0);
        setState(() {
          _liveQuad = smoothed;
          _stableProgress = progress;
        });

        final cooledDown =
            now.difference(_lastCaptureAt).inMilliseconds >
            _autoCaptureCooldownMs;
        if (_autoCapture &&
            _mode == _CaptureMode.document &&
            progress >= 1.0 &&
            cooledDown &&
            !_capturing &&
            !_shutterLocked) {
          _stableSince = null;
          _stableProgress = 0.0;
          unawaited(_capturePage());
        }
      } else {
        setState(() {
          _liveQuad = smoothed;
          _stableSince = now;
          _stableProgress = 0.0;
        });
      }
    } catch (_) {
    } finally {
      _detectingFrame = false;
    }
  }

  double _quadDelta(Quad a, Quad b) {
    if (a.pts.length != 4 || b.pts.length != 4) return 1.0;
    double maxDiff = 0.0;
    for (var i = 0; i < 4; i++) {
      final dx = a.pts[i].$1 - b.pts[i].$1;
      final dy = a.pts[i].$2 - b.pts[i].$2;
      maxDiff = max(maxDiff, sqrt(dx * dx + dy * dy));
    }
    return maxDiff;
  }

  Future<void> _onTapFocus(TapUpDetails details, Size previewSize) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final nx = (details.localPosition.dx / previewSize.width).clamp(0.0, 1.0);
    final ny = (details.localPosition.dy / previewSize.height).clamp(0.0, 1.0);
    final pt = Offset(nx, ny);

    setState(() => _focusPointNorm = pt);
    _focusHideTimer?.cancel();
    _focusHideTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _focusPointNorm = null);
    });

    try {
      await ctrl.setFocusPoint(pt);
      await ctrl.setExposurePoint(pt);
    } catch (_) {}
  }

  Future<void> _setExposure(double value) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    setState(() => _exposure = value);
    try {
      await ctrl.setExposureOffset(value);
    } catch (_) {}
  }

  Future<void> _toggleFlash() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final next = !_flashOn;
    try {
      await ctrl.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _flashOn = next);
    } catch (_) {}
  }

  Future<void> _capturePage() async {
    final ctrl = _controller;
    if (ctrl == null ||
        !ctrl.value.isInitialized ||
        _capturing ||
        _shutterLocked ||
        _finishing) {
      return;
    }
    _shutterCooldownTimer?.cancel();
    _shutterFlashTimer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() {
      _capturing = true;
      _shutterLocked = true;
      _shutterFlash = true;
      _stableSince = null;
      _stableProgress = 0.0;
    });
    _shutterFlashTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _shutterFlash = false);
    });
    _lastCaptureAt = DateTime.now();

    try {
      if (ctrl.value.isStreamingImages) {
        await ctrl.stopImageStream();
      }
      final xfile = await ctrl.takePicture();
      _lastCaptureAt = DateTime.now();
      if (!mounted) return;

      if (_mode == _CaptureMode.idCard) {
        await _handleIdCardShot(xfile.path);
        return;
      }

      setState(() {
        _capturedCount += 1;
        _pendingJobs += 1;
      });

      final repo = ref.read(repositoryProvider);
      final preferredFilter = ref.read(appSettingsProvider).defaultFilter;
      _queue = _queue.then((_) async {
        try {
          _docId ??= (await repo.createDocument()).id;
          final page = await repo.addPageFromSource(
            docId: _docId!,
            sourcePath: xfile.path,
            filter: preferredFilter,
            deleteSourceAfterCopy: true,
          );
          if (mounted) {
            setState(() => _lastThumbPath = page.thumbPath);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gagal memproses halaman: ${formatError(e)}')),
            );
          }
        } finally {
          if (mounted) {
            setState(() => _pendingJobs = max(0, _pendingJobs - 1));
          }
        }
      });

      await _startStream();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil foto: ${formatError(e)}')),
        );
      }
    } finally {
      _lastCaptureAt = DateTime.now();
      if (mounted) {
        setState(() => _capturing = false);
        _shutterCooldownTimer = Timer(
          const Duration(milliseconds: _shutterCooldownMs),
          () {
            if (mounted) setState(() => _shutterLocked = false);
          },
        );
      }
    }
  }

  Future<void> _handleIdCardShot(String path) async {
    if (_idFrontPath == null) {
      setState(() => _idFrontPath = path);
      await _startStream();
      return;
    }

    // Both front and back captured -> compose onto one A4 sheet in Rust.
    final frontPath = _idFrontPath!;
    setState(() {
      _idFrontPath = null;
      _finishing = true;
    });
    try {
      final doc = await ref.read(repositoryProvider).createIdCardDocument(
        frontSourcePath: frontPath,
        backSourcePath: path,
      );
      if (mounted) {
        Navigator.of(context).pop(doc.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyusun KTP: ${formatError(e)}')),
        );
        setState(() => _finishing = false);
        await _startStream();
      }
    }
  }

  Future<void> _finishSession() async {
    if (_finishing || _capturedCount == 0) return;
    setState(() => _finishing = true);
    try {
      await _queue;
      String? resultDocId = _docId;
      if (resultDocId != null && widget.existingDocId == null) {
        final doc = await ref.read(repositoryProvider).getDocument(resultDocId);
        if (doc == null || doc.pageCount == 0) {
          await ref.read(repositoryProvider).deleteDocument(resultDocId);
          resultDocId = null;
        }
      }
      if (mounted) {
        Navigator.of(context).pop(resultDocId);
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _handleBack() async {
    if (_idFrontPath != null) {
      await ref.read(fileStoreProvider).safeDeleteFile(_idFrontPath!);
      _idFrontPath = null;
    }
    if (!mounted) return;
    if (_capturedCount == 0) {
      Navigator.of(context).pop();
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar dari kamera?'),
        content: Text(
          'Anda sudah memindai $_capturedCount halaman. Simpan atau batalkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Lanjut Scan'),
          ),
          if (widget.existingDocId == null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: Text(
                'Buang',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'save') {
      await _finishSession();
    } else if (action == 'discard') {
      setState(() => _finishing = true);
      await _queue;
      if (_docId != null) {
        await ref.read(repositoryProvider).deleteDocument(_docId!);
      }
      if (mounted) Navigator.of(context).pop();
    }
  }

  Widget _buildTopControls({required bool vertical}) {
    final items = <Widget>[
      _CircleChromeButton(
        icon: Icons.close_rounded,
        tooltip: 'Tutup',
        onTap: _handleBack,
      ),
      const Spacer(),
      if (_mode == _CaptureMode.document) ...[
        if (vertical)
          _CircleChromeButton(
            icon: _autoCapture
                ? Icons.auto_awesome
                : Icons.pan_tool_outlined,
            tooltip: _autoCapture ? 'Auto-capture aktif' : 'Mode manual',
            active: _autoCapture,
            onTap: () => setState(() {
              _autoCapture = !_autoCapture;
              _stableSince = null;
              _stableProgress = 0.0;
            }),
          )
        else
          _AutoTogglePill(
            enabled: _autoCapture,
            onTap: () => setState(() {
              _autoCapture = !_autoCapture;
              _stableSince = null;
              _stableProgress = 0.0;
            }),
          ),
        SizedBox(width: vertical ? 0 : 6, height: vertical ? 8 : 0),
      ],
      _CircleChromeButton(
        icon: Icons.grid_on_rounded,
        tooltip: 'Grid 3×3',
        active: _showGrid,
        onTap: () => setState(() => _showGrid = !_showGrid),
      ),
      SizedBox(width: vertical ? 0 : 6, height: vertical ? 8 : 0),
      _CircleChromeButton(
        icon: Icons.exposure_rounded,
        tooltip: 'Eksposur',
        active: _showExposure,
        onTap: () => setState(() => _showExposure = !_showExposure),
      ),
      SizedBox(width: vertical ? 0 : 6, height: vertical ? 8 : 0),
      _CircleChromeButton(
        icon: _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
        tooltip: 'Lampu kilat',
        active: _flashOn,
        onTap: _toggleFlash,
      ),
    ];

    return vertical
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: items,
          )
        : Row(children: items);
  }

  Widget _buildViewfinder(bool isLandscape) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!_initializing &&
            _controller != null &&
            _controller!.value.isInitialized)
          Center(
            child: AspectRatio(
              aspectRatio: isLandscape
                  ? _controller!.value.aspectRatio
                  : 1 / _controller!.value.aspectRatio,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final previewSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _onTapFocus(d, previewSize),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_controller!),
                        if (_showGrid)
                          const CustomPaint(painter: _GridOverlayPainter()),
                        if (_mode == _CaptureMode.idCard)
                          CustomPaint(
                            painter: _IdCardGuidePainter(
                              isBackSide: _idFrontPath != null,
                            ),
                          )
                        else
                          CustomPaint(
                            painter: _LiveQuadPainter(
                              quad: _liveQuad,
                              isStable: _stableProgress > 0.25,
                            ),
                          ),
                        IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _shutterFlash ? 0.45 : 0.0,
                            duration: const Duration(milliseconds: 110),
                            child: const ColoredBox(color: Colors.white),
                          ),
                        ),
                        if (_focusPointNorm != null)
                          Positioned(
                            left: _focusPointNorm!.dx * previewSize.width - 28,
                            top: _focusPointNorm!.dy * previewSize.height - 28,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.cameraQuad,
                                  width: 2,
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
          )
        else
          const Center(child: CircularProgressIndicator(color: Colors.white)),

        // Optional exposure slider bar.
        if (_showExposure && _maxExposure > _minExposure)
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.76),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.brightness_6_outlined,
                    color: Colors.white70,
                    size: 18,
                  ),
                  Expanded(
                    child: Slider(
                      value: _exposure.clamp(_minExposure, _maxExposure),
                      min: _minExposure,
                      max: _maxExposure,
                      onChanged: _setExposure,
                    ),
                  ),
                  Text(
                    _exposure.toStringAsFixed(1),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

        // Contextual status pill (ID card step or live quad stability).
        if (!_showExposure &&
            (_mode == _CaptureMode.idCard || _liveQuad != null))
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _mode == _CaptureMode.idCard
                        ? AppColors.cameraQuad
                        : (_stableProgress > 0.25
                              ? AppColors.stableGreen
                              : AppColors.cameraQuad),
                  ),
                ),
                child: _mode == _CaptureMode.idCard
                    ? Text(
                        _idFrontPath == null
                            ? 'Langkah 1/2: Pindai sisi DEPAN kartu'
                            : 'Langkah 2/2: Pindai sisi BELAKANG kartu',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              value: _autoCapture
                                  ? _stableProgress.clamp(0.08, 1.0)
                                  : 1.0,
                              strokeWidth: 2.2,
                              color: _stableProgress > 0.25
                                  ? AppColors.stableGreen
                                  : AppColors.cameraQuad,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _autoCapture
                                ? 'Tahan stabil...'
                                : 'Dokumen terdeteksi',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildThumbBadge() {
    if (_capturedCount <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 46,
                height: 58,
                color: Colors.white12,
                child: _lastThumbPath != null &&
                        File(_lastThumbPath!).existsSync()
                    ? Image.file(
                        File(_lastThumbPath!),
                        fit: BoxFit.cover,
                        cacheWidth: 160,
                      )
                    : const Icon(
                        Icons.description_outlined,
                        color: Colors.white70,
                      ),
              ),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.cameraQuad,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$_capturedCount',
                  style: const TextStyle(
                    color: Color(0xFF1D1D1C),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_pendingJobs > 0) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white70,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildShutterButton() {
    final disabled = _capturing || _shutterLocked;
    return GestureDetector(
      onTap: disabled ? null : _capturePage,
      child: Container(
        width: 72,
        height: 72,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: disabled ? Colors.white54 : AppColors.cameraQuad,
            width: 3.5,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: disabled ? Colors.white38 : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildDoneButton() {
    if (_capturedCount <= 0) return const SizedBox.shrink();
    return FilledButton(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: const Size(0, 44),
      ),
      onPressed: _finishing ? null : _finishSession,
      child: const Text('Selesai'),
    );
  }

  Widget _buildCaptureControls({
    required bool vertical,
    required bool canSwitchMode,
  }) {
    if (vertical) {
      // Landscape right rail: top mode/done, center shutter, bottom thumbnail.
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_capturedCount > 0)
            _buildDoneButton()
          else if (canSwitchMode)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ModeChip(
                  label: 'Dok',
                  selected: _mode == _CaptureMode.document,
                  onTap: () => setState(() {
                    _mode = _CaptureMode.document;
                    _idFrontPath = null;
                  }),
                ),
                const SizedBox(height: 6),
                _ModeChip(
                  label: 'KTP',
                  selected: _mode == _CaptureMode.idCard,
                  onTap: () => setState(() {
                    _mode = _CaptureMode.idCard;
                    _liveQuad = null;
                  }),
                ),
              ],
            )
          else
            const SizedBox(height: 44),
          _buildShutterButton(),
          SizedBox(
            height: 60,
            child: Center(child: _buildThumbBadge()),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canSwitchMode)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ModeChip(
                  label: 'Dokumen',
                  selected: _mode == _CaptureMode.document,
                  onTap: () => setState(() {
                    _mode = _CaptureMode.document;
                    _idFrontPath = null;
                  }),
                ),
                const SizedBox(width: 8),
                _ModeChip(
                  label: 'KTP (2 Sisi)',
                  selected: _mode == _CaptureMode.idCard,
                  onTap: () => setState(() {
                    _mode = _CaptureMode.idCard;
                    _liveQuad = null;
                  }),
                ),
              ],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(width: 84, child: _buildThumbBadge()),
            _buildShutterButton(),
            SizedBox(
              width: 88,
              child: Align(
                alignment: Alignment.centerRight,
                child: _buildDoneButton(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSwitchMode = widget.existingDocId == null && _capturedCount == 0;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return PopScope(
      canPop: _capturedCount == 0 && _idFrontPath == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _permissionDenied
              ? _PermissionDeniedView(
                  onOpenSettings: openAppSettings,
                  onRetry: _initCamera,
                  onBack: () => Navigator.of(context).pop(),
                )
              : _errorMsg != null
              ? _CameraErrorView(
                  message: _errorMsg!,
                  onRetry: _initCamera,
                  onBack: () => Navigator.of(context).pop(),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (isLandscape)
                      Row(
                        children: [
                          Container(
                            width: 68,
                            color: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: _buildTopControls(vertical: true),
                          ),
                          Expanded(child: _buildViewfinder(true)),
                          Container(
                            width: 108,
                            color: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 8,
                            ),
                            child: _buildCaptureControls(
                              vertical: true,
                              canSwitchMode: canSwitchMode,
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            child: _buildTopControls(vertical: false),
                          ),
                          Expanded(child: _buildViewfinder(false)),
                          Container(
                            color: Colors.black,
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                            child: _buildCaptureControls(
                              vertical: false,
                              canSwitchMode: canSwitchMode,
                            ),
                          ),
                        ],
                      ),

                    if (_finishing)
                      Container(
                        color: Colors.black54,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                color: Colors.white,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _mode == _CaptureMode.idCard
                                    ? 'Menyusun KTP 2 sisi ke halaman A4...'
                                    : 'Menyelesaikan pemrosesan halaman...',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
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

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.yellow
              : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.charcoal : Colors.white,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _GridOverlayPainter extends CustomPainter {
  const _GridOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;
    for (var i = 1; i <= 2; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridOverlayPainter oldDelegate) => false;
}

class _IdCardGuidePainter extends CustomPainter {
  const _IdCardGuidePainter({required this.isBackSide});

  final bool isBackSide;

  @override
  void paint(Canvas canvas, Size size) {
    // Standard ISO/IEC 7810 ID-1 card aspect ratio ~ 1.586.
    final cardW = size.width * 0.82;
    final cardH = cardW / 1.586;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.48),
      width: cardW,
      height: cardH,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rrect),
    );
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = isBackSide ? AppColors.stableGreen : AppColors.cameraQuad
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6,
    );
  }

  @override
  bool shouldRepaint(covariant _IdCardGuidePainter oldDelegate) =>
      oldDelegate.isBackSide != isBackSide;
}

class _LiveQuadPainter extends CustomPainter {
  const _LiveQuadPainter({required this.quad, required this.isStable});

  final Quad? quad;
  final bool isStable;

  @override
  void paint(Canvas canvas, Size size) {
    final q = quad;
    if (q == null || q.pts.length != 4) return;

    final color = isStable ? AppColors.stableGreen : AppColors.cameraQuad;
    final pts = q.pts
        .map((p) => Offset(p.$1 * size.width, p.$2 * size.height))
        .toList(growable: false);
    final path = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.14)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeJoin = StrokeJoin.round,
    );

    final fillPaint = Paint()..color = color;
    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    for (final pt in pts) {
      canvas.drawCircle(pt, 5.5, fillPaint);
      canvas.drawCircle(pt, 5.5, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiveQuadPainter oldDelegate) =>
      oldDelegate.quad != quad || oldDelegate.isStable != isStable;
}

class _CircleChromeButton extends StatelessWidget {
  const _CircleChromeButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? AppColors.yellow
            : Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              color: active ? AppColors.charcoal : Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _AutoTogglePill extends StatelessWidget {
  const _AutoTogglePill({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? AppColors.yellow
          : Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                enabled ? Icons.auto_awesome : Icons.pan_tool_outlined,
                color: enabled ? AppColors.charcoal : Colors.white,
                size: 15,
              ),
              const SizedBox(width: 5),
              Text(
                enabled ? 'Auto' : 'Manual',
                style: TextStyle(
                  color: enabled ? AppColors.charcoal : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionDeniedView extends StatelessWidget {
  const _PermissionDeniedView({
    required this.onOpenSettings,
    required this.onRetry,
    required this.onBack,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: Colors.white70,
            size: 56,
          ),
          const SizedBox(height: 16),
          const Text(
            'Izin kamera diperlukan',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'JScan membutuhkan izin kamera untuk memindai dokumen secara langsung. Anda tetap dapat mengimpor gambar dari galeri di halaman Beranda.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Buka Pengaturan'),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: onRetry,
                child: const Text(
                  'Coba Lagi',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: onBack,
                child: const Text(
                  'Kembali',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 48),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton(onPressed: onRetry, child: const Text('Coba Lagi')),
              const SizedBox(width: 12),
              TextButton(
                onPressed: onBack,
                child: const Text(
                  'Kembali',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
