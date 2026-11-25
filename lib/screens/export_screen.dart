import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../src/rust/api.dart';
import '../state/providers.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key, required this.docId});

  final String docId;

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  final _nameController = TextEditingController();
  final _watermarkCtrl = TextEditingController(text: 'HANYA UNTUK VERIFIKASI');
  ExportFormat _format = ExportFormat.pdf;
  ExportQuality _quality = ExportQuality.medium;
  PdfFit _pdfFit = PdfFit.a4;
  PdfMargin _pdfMargin = PdfMargin.none;
  bool _enableWatermark = false;

  ScanDocument? _doc;
  List<ScanPage> _pages = [];
  bool _loading = true;
  bool _exporting = false;
  String _progressText = '';

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appSettingsProvider);
    _quality = settings.defaultExportQuality;
    _pdfFit = settings.defaultPdfFit;
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _watermarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    final doc = await repo.getDocument(widget.docId);
    final pages = await repo.getPages(widget.docId);
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _pages = pages;
      _nameController.text = doc?.name ?? defaultDocumentName();
      _loading = false;
    });
  }

  String? get _activeWatermark {
    if (!_enableWatermark) return null;
    final t = _watermarkCtrl.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<({String path, String fileName, String mimeType})> _buildArtifact(
    Directory workDir,
  ) async {
    final baseName = sanitizeFileName(_nameController.text);
    final total = _pages.length;
    final watermark = _activeWatermark;

    if (_format == ExportFormat.pdf) {
      final prepared = <String>[];
      for (var i = 0; i < total; i++) {
        if (mounted) {
          setState(
            () => _progressText = 'Menyiapkan halaman ${i + 1} dari $total...',
          );
        }
        final page = _pages[i];
        final tmpImg = p.join(workDir.path, 'pdf_p_${i + 1}.jpg');
        if (_quality == ExportQuality.high) {
          await processPage(
            src: page.origPath,
            dst: tmpImg,
            quad: page.corners,
            filter: page.filter,
            rotationDeg: page.rotation,
            maxLongSide: _quality.maxLongSide,
            jpegQuality: _quality.jpegQuality,
            brightness: page.brightness,
            contrast: page.contrast,
          );
        } else {
          await exportImage(
            src: page.outPath,
            dst: tmpImg,
            format: ExportImageFormat.jpeg,
            maxLongSide: _quality.maxLongSide,
            jpegQuality: _quality.jpegQuality,
          );
        }
        prepared.add(tmpImg);
      }

      if (mounted) setState(() => _progressText = 'Menyusun file PDF...');
      final fileName = '$baseName.pdf';
      final outPdf = p.join(workDir.path, fileName);
      await imagesToPdf(
        pages: prepared,
        out: outPdf,
        opts: PdfOpts(
          fit: _pdfFit,
          jpegQuality: _quality.jpegQuality,
          marginPt: _pdfFit == PdfFit.a4 ? _pdfMargin.points : 0.0,
          watermarkText: watermark,
        ),
      );
      return (path: outPdf, fileName: fileName, mimeType: 'application/pdf');
    }

    // JPG or PNG export.
    final rustFormat = _format == ExportFormat.png
        ? ExportImageFormat.png
        : ExportImageFormat.jpeg;
    final ext = _format.ext;
    final mime = _format == ExportFormat.png ? 'image/png' : 'image/jpeg';

    final outImages = <({String path, String entryName})>[];
    for (var i = 0; i < total; i++) {
      if (mounted) {
        setState(
          () => _progressText = 'Mengekspor gambar ${i + 1} dari $total...',
        );
      }
      final page = _pages[i];
      final entryName =
          total == 1 ? '$baseName.$ext' : '${baseName}_${i + 1}.$ext';
      final dst = p.join(workDir.path, entryName);

      if (_quality == ExportQuality.high) {
        final highJpg = p.join(workDir.path, 'hi_${i + 1}.jpg');
        await processPage(
          src: page.origPath,
          dst: highJpg,
          quad: page.corners,
          filter: page.filter,
          rotationDeg: page.rotation,
          maxLongSide: _quality.maxLongSide,
          jpegQuality: _quality.jpegQuality,
          brightness: page.brightness,
          contrast: page.contrast,
        );
        if (rustFormat == ExportImageFormat.png || watermark != null) {
          await exportImage(
            src: highJpg,
            dst: dst,
            format: rustFormat,
            maxLongSide: _quality.maxLongSide,
            jpegQuality: _quality.jpegQuality,
            watermarkText: watermark,
          );
        } else {
          await File(highJpg).rename(dst);
        }
      } else {
        await exportImage(
          src: page.outPath,
          dst: dst,
          format: rustFormat,
          maxLongSide: _quality.maxLongSide,
          jpegQuality: _quality.jpegQuality,
          watermarkText: watermark,
        );
      }
      outImages.add((path: dst, entryName: entryName));
    }

    if (outImages.length == 1) {
      return (
        path: outImages.first.path,
        fileName: outImages.first.entryName,
        mimeType: mime,
      );
    }

    if (mounted) setState(() => _progressText = 'Mengemas arsip ZIP...');
    final zipName = '$baseName.zip';
    final zipPath = p.join(workDir.path, zipName);
    await zipFiles(
      entries: outImages
          .map((e) => ZipEntry(srcPath: e.path, nameInZip: e.entryName))
          .toList(),
      outZip: zipPath,
    );
    return (path: zipPath, fileName: zipName, mimeType: 'application/zip');
  }

  Future<void> _executeExport({required bool share}) async {
    if (_exporting || _pages.isEmpty) return;
    setState(() {
      _exporting = true;
      _progressText = 'Memulai ekspor...';
    });

    final fileStore = ref.read(fileStoreProvider);
    Directory? workDir;
    try {
      workDir = await fileStore.createTempWorkDir('export');
      final artifact = await _buildArtifact(workDir);

      if (share) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(artifact.path, mimeType: artifact.mimeType)],
            subject: artifact.fileName,
          ),
        );
      } else {
        final bytes = await File(artifact.path).readAsBytes();
        final savedUri = await FilePicker.saveFile(
          dialogTitle: 'Simpan dokumen',
          fileName: artifact.fileName,
          bytes: bytes,
          mimeType: artifact.mimeType,
        );
        if (mounted && savedUri != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tersimpan: ${artifact.fileName}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatError(e))),
        );
      }
    } finally {
      if (workDir != null && !share) {
        try {
          await workDir.delete(recursive: true);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _exporting = false;
          _progressText = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pageCount = _pages.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Ekspor Dokumen')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _doc == null || _pages.isEmpty
          ? const Center(child: Text('Tidak ada halaman untuk diekspor.'))
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Compact document preview summary banner.
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 48,
                                height: 60,
                                color: scheme.surfaceContainerHighest,
                                child: _pages.isNotEmpty &&
                                        File(_pages.first.thumbPath).existsSync()
                                    ? Image.file(
                                        File(_pages.first.thumbPath),
                                        fit: BoxFit.cover,
                                        cacheWidth: 160,
                                      )
                                    : Icon(
                                        Icons.description_outlined,
                                        color: scheme.onSurfaceVariant,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _doc!.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$pageCount halaman siap diekspor offline',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.yellow,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _format == ExportFormat.pdf
                                    ? 'PDF'
                                    : (pageCount > 1
                                          ? 'ZIP'
                                          : _format.label),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.charcoal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    Text(
                      'Nama File',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'Masukkan nama file',
                        suffixText: _format == ExportFormat.pdf
                            ? '.pdf'
                            : (pageCount > 1 ? '.zip' : '.${_format.ext}'),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'Format',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<ExportFormat>(
                      segments: ExportFormat.values
                          .map((f) => ButtonSegment(value: f, label: Text(f.label)))
                          .toList(),
                      selected: {_format},
                      onSelectionChanged: (s) =>
                          setState(() => _format = s.first),
                    ),
                    if (_format != ExportFormat.pdf && pageCount > 1) ...[
                      const SizedBox(height: 8),
                      Text(
                        '$pageCount halaman akan dikemas ke dalam arsip ZIP.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    Text(
                      'Kualitas',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<ExportQuality>(
                      segments: ExportQuality.values
                          .map((q) => ButtonSegment(value: q, label: Text(q.label)))
                          .toList(),
                      selected: {_quality},
                      onSelectionChanged: (s) =>
                          setState(() => _quality = s.first),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Maks. sisi panjang ${_quality.maxLongSide} px · Kompresi ${_quality.jpegQuality}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),

                    if (_format == ExportFormat.pdf) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Ukuran Halaman PDF',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<PdfFit>(
                        segments: const [
                          ButtonSegment(value: PdfFit.a4, label: Text('A4')),
                          ButtonSegment(
                            value: PdfFit.original,
                            label: Text('Asli'),
                          ),
                        ],
                        selected: {_pdfFit},
                        onSelectionChanged: (s) =>
                            setState(() => _pdfFit = s.first),
                      ),
                      if (_pdfFit == PdfFit.a4) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Margin A4',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<PdfMargin>(
                          segments: PdfMargin.values
                              .map(
                                (m) => ButtonSegment(
                                  value: m,
                                  label: Text(m.label),
                                ),
                              )
                              .toList(),
                          selected: {_pdfMargin},
                          onSelectionChanged: (s) =>
                              setState(() => _pdfMargin = s.first),
                        ),
                      ],
                    ],

                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Watermark Teks',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: const Text(
                                'Tambahkan teks pengaman diagonal (cocok untuk KTP/berkas)',
                                style: TextStyle(fontSize: 12),
                              ),
                              value: _enableWatermark,
                              onChanged: (v) =>
                                  setState(() => _enableWatermark = v),
                            ),
                            if (_enableWatermark) ...[
                              TextField(
                                controller: _watermarkCtrl,
                                maxLength: 40,
                                decoration: const InputDecoration(
                                  hintText: 'Contoh: HANYA UNTUK VERIFIKASI',
                                  counterText: '',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: watermarkPresets
                                    .map(
                                      (preset) => ActionChip(
                                        label: Text(
                                          preset,
                                          style: const TextStyle(fontSize: 11.5),
                                        ),
                                        onPressed: () => setState(
                                          () => _watermarkCtrl.text = preset,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _exporting
                                ? null
                                : () => _executeExport(share: false),
                            icon: const Icon(Icons.save_alt_rounded),
                            label: const Text('Simpan'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _exporting
                                ? null
                                : () => _executeExport(share: true),
                            icon: const Icon(Icons.share_rounded),
                            label: const Text('Bagikan'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
                if (_exporting)
                  Container(
                    color: Colors.black45,
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(_progressText),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
