import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../src/rust/api.dart';
import '../state/providers.dart';
import '../widgets/illustrations.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tools = [
      (
        icon: Icons.picture_as_pdf_outlined,
        tag: 'PDF',
        featured: true,
        accent: AppColors.charcoal,
        title: 'JPG / PNG ke PDF',
        subtitle:
            'Pilih banyak gambar, atur urutan, lalu susun menjadi satu PDF.',
        builder: (_) => const _ImagesToPdfToolPage(),
      ),
      (
        icon: Icons.image_outlined,
        tag: 'JPG / PNG',
        featured: false,
        accent: isDark ? AppColors.toolTealDark : AppColors.toolTealLight,
        title: 'PDF ke JPG / PNG',
        subtitle:
            'Ubah tiap halaman PDF menjadi gambar (ZIP otomatis bila > 1 halaman).',
        builder: (_) => const _PdfToImagesToolPage(),
      ),
      (
        icon: Icons.compress_rounded,
        tag: 'HEMAT',
        featured: false,
        accent: isDark ? AppColors.yellow : AppColors.yellowDeep,
        title: 'Kompres PDF',
        subtitle:
            'Perkecil ukuran file PDF untuk unggah formulir/portal secara offline.',
        builder: (_) => const _CompressPdfToolPage(),
      ),
      (
        icon: Icons.merge_type_rounded,
        tag: 'MULTI',
        featured: false,
        accent: isDark ? AppColors.toolSkyDark : AppColors.toolSkyLight,
        title: 'Gabung PDF',
        subtitle:
            'Pilih 2 atau lebih file PDF, urutkan, lalu gabung jadi satu.',
        builder: (_) => const _MergePdfToolPage(),
      ),
      (
        icon: Icons.call_split_rounded,
        tag: 'RENTANG',
        featured: false,
        accent: isDark ? AppColors.toolRoseDark : AppColors.toolRoseLight,
        title: 'Pisah PDF',
        subtitle:
            'Pilih halaman secara visual atau ketik rentang (mis. 1-3, 5, 7-9).',
        builder: (_) => const _SplitPdfToolPage(),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        // Signature dark charcoal hero card with warm yellow accents.
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? AppColors.charcoalElevated : AppColors.charcoal,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? AppColors.borderDark : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              const ToolsHeroIllustration(size: 66),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.yellow,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '100% OFFLINE',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: AppColors.charcoal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Kit PDF & Gambar Lokal',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.bgLight,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Semua konversi diproses cepat di perangkat tanpa unggah ke server.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.38,
                        color: AppColors.bgLight.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Editorial section header with pill count (referensi-ui-ux.jpg motif).
        Row(
          children: [
            Text('ALAT KONVERSI', style: textTheme.labelMedium),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${tools.length}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        ...tools.map((t) {
          final isFeatured = t.featured;
          final cardBg = isFeatured ? AppColors.yellow : scheme.surface;
          final titleColor = isFeatured ? AppColors.charcoal : scheme.onSurface;
          final subColor = isFeatured
              ? AppColors.charcoal.withValues(alpha: 0.78)
              : scheme.onSurfaceVariant;
          final iconBg = isFeatured
              ? AppColors.charcoal.withValues(alpha: 0.12)
              : t.accent.withValues(alpha: isDark ? 0.18 : 0.12);
          final iconFg = isFeatured ? AppColors.charcoal : t.accent;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isFeatured ? Colors.transparent : scheme.outline,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: t.builder),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(t.icon, color: iconFg, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    t.title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: titleColor,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isFeatured
                                        ? AppColors.charcoal
                                        : scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    t.tag,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                      color: isFeatured
                                          ? AppColors.yellow
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              t.subtitle,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: subColor,
                                height: 1.38,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isFeatured
                              ? AppColors.charcoal.withValues(alpha: 0.12)
                              : scheme.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: isFeatured
                              ? AppColors.charcoal
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Shared save/share action sheet after a tool produces a file.
Future<void> _presentOutputActions(
  BuildContext context, {
  required String filePath,
  required String fileName,
  required String mimeType,
  String? subtitle,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        final bytes = await File(filePath).readAsBytes();
                        final uri = await FilePicker.saveFile(
                          dialogTitle: 'Simpan hasil',
                          fileName: fileName,
                          bytes: bytes,
                          mimeType: mimeType,
                        );
                        try {
                          await File(filePath).parent.delete(recursive: true);
                        } catch (_) {}
                        if (context.mounted && uri != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Tersimpan: $fileName')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(formatError(e))),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('Simpan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await SharePlus.instance.share(
                        ShareParams(
                          files: [XFile(filePath, mimeType: mimeType)],
                          subject: fileName,
                        ),
                      );
                    },
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Bagikan'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

// ============================================================================
// 1. JPG/PNG -> PDF
// ============================================================================

class _ImagesToPdfToolPage extends ConsumerStatefulWidget {
  const _ImagesToPdfToolPage();

  @override
  ConsumerState<_ImagesToPdfToolPage> createState() =>
      _ImagesToPdfToolPageState();
}

class _ImagesToPdfToolPageState extends ConsumerState<_ImagesToPdfToolPage> {
  final _nameCtrl = TextEditingController(text: defaultDocumentName());
  final List<String> _imagePaths = [];
  late PdfFit _fit;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _fit = ref.read(appSettingsProvider).defaultPdfFit;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty || !mounted) return;
    setState(() => _imagePaths.addAll(picked.map((x) => x.path)));
  }

  Future<void> _convert() async {
    if (_imagePaths.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final workDir = await ref
          .read(fileStoreProvider)
          .createTempWorkDir('img2pdf');
      final fileName = '${sanitizeFileName(_nameCtrl.text)}.pdf';
      final outPath = p.join(workDir.path, fileName);
      await imagesToPdf(
        pages: _imagePaths,
        out: outPath,
        opts: PdfOpts(fit: _fit, jpegQuality: 85, marginPt: 0.0),
      );
      if (mounted) {
        await _presentOutputActions(
          context,
          filePath: outPath,
          fileName: fileName,
          mimeType: 'application/pdf',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('JPG / PNG ke PDF')),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nama file PDF',
                        suffixText: '.pdf',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<PdfFit>(
                            segments: const [
                              ButtonSegment(
                                value: PdfFit.a4,
                                label: Text('A4'),
                              ),
                              ButtonSegment(
                                value: PdfFit.original,
                                label: Text('Asli'),
                              ),
                            ],
                            selected: {_fit},
                            onSelectionChanged: (s) =>
                                setState(() => _fit = s.first),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _pickImages,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Pilih'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _imagePaths.isEmpty
                    ? Center(
                        child: Text(
                          'Pilih satu atau lebih gambar JPG/PNG.\nGeser item untuk mengatur urutan.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: _imagePaths.length,
                        onReorderItem: (oldIdx, newIdx) {
                          setState(() {
                            final item = _imagePaths.removeAt(oldIdx);
                            _imagePaths.insert(newIdx, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final path = _imagePaths[index];
                          return Card(
                            key: ValueKey('${path}_$index'),
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.file(
                                  File(path),
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  cacheWidth: 140,
                                ),
                              ),
                              title: Text(
                                p.basename(path),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text('Halaman ${index + 1}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () => setState(
                                      () => _imagePaths.removeAt(index),
                                    ),
                                  ),
                                  const Icon(Icons.drag_handle_rounded),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _imagePaths.isEmpty || _busy ? null : _convert,
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: Text('Buat PDF (${_imagePaths.length} gambar)'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_busy) const _BusyOverlay(message: 'Menyusun PDF...'),
        ],
      ),
    );
  }
}

// ============================================================================
// 2. PDF -> JPG/PNG (rendered via pdfx / Android PdfRenderer)
// ============================================================================

class _PdfToImagesToolPage extends ConsumerStatefulWidget {
  const _PdfToImagesToolPage();

  @override
  ConsumerState<_PdfToImagesToolPage> createState() =>
      _PdfToImagesToolPageState();
}

class _PdfToImagesToolPageState extends ConsumerState<_PdfToImagesToolPage> {
  String? _pdfPath;
  String? _pdfBaseName;
  int? _pageCount;
  ExportImageFormat _format = ExportImageFormat.png;
  bool _busy = false;
  String _statusText = '';

  Future<void> _pickPdf() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Pilih file PDF',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (picked == null || picked.path == null || !mounted) return;
    final path = picked.path!;
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(path);
      final count = doc.pagesCount;
      if (mounted) {
        setState(() {
          _pdfPath = path;
          _pdfBaseName = sanitizeFileName(
            p.basenameWithoutExtension(picked.name),
            fallback: 'dokumen',
          );
          _pageCount = count;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PDF tidak dapat dibuka (rusak atau terenkripsi/berkata sandi).',
            ),
          ),
        );
      }
    } finally {
      await doc?.close();
    }
  }

  Future<void> _convert() async {
    final pdfPath = _pdfPath;
    if (pdfPath == null || _busy) return;
    setState(() {
      _busy = true;
      _statusText = 'Membuka PDF...';
    });

    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(pdfPath);
      final total = doc.pagesCount;
      if (total <= 0) {
        throw const FormatException('File PDF tidak memiliki halaman.');
      }

      final workDir = await ref
          .read(fileStoreProvider)
          .createTempWorkDir('pdf2img');
      final base = _pdfBaseName ?? 'dokumen';
      final isPng = _format == ExportImageFormat.png;
      final ext = isPng ? 'png' : 'jpg';
      final pdfxFmt = isPng
          ? PdfPageImageFormat.png
          : PdfPageImageFormat.jpeg;
      final mime = isPng ? 'image/png' : 'image/jpeg';

      final rendered = <({String path, String entryName})>[];

      for (var i = 1; i <= total; i++) {
        if (mounted) {
          setState(
            () => _statusText = 'Merender halaman $i dari $total...',
          );
        }
        final page = await doc.getPage(i);
        try {
          var w = page.width * 2.0;
          var h = page.height * 2.0;
          final longSide = w > h ? w : h;
          if (longSide > 2600) {
            final scale = 2600 / longSide;
            w *= scale;
            h *= scale;
          }
          final pageImg = await page.render(
            width: w,
            height: h,
            format: pdfxFmt,
            backgroundColor: '#FFFFFF',
            quality: 90,
          );
          if (pageImg == null) {
            throw FormatException('Gagal merender halaman $i.');
          }
          final entryName = total == 1 ? '$base.$ext' : '${base}_$i.$ext';
          final outPath = p.join(workDir.path, entryName);
          await File(outPath).writeAsBytes(pageImg.bytes, flush: true);
          rendered.add((path: outPath, entryName: entryName));
        } finally {
          await page.close();
        }
      }

      if (rendered.length == 1) {
        if (mounted) {
          await _presentOutputActions(
            context,
            filePath: rendered.first.path,
            fileName: rendered.first.entryName,
            mimeType: mime,
          );
        }
      } else {
        if (mounted) setState(() => _statusText = 'Mengemas arsip ZIP...');
        final zipName = '$base.zip';
        final zipPath = p.join(workDir.path, zipName);
        await zipFiles(
          entries: rendered
              .map((e) => ZipEntry(srcPath: e.path, nameInZip: e.entryName))
              .toList(),
          outZip: zipPath,
        );
        if (mounted) {
          await _presentOutputActions(
            context,
            filePath: zipPath,
            fileName: zipName,
            mimeType: 'application/zip',
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
      await doc?.close();
      if (mounted) {
        setState(() {
          _busy = false;
          _statusText = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('PDF ke JPG / PNG')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.picture_as_pdf_outlined,
                    color: scheme.primary,
                  ),
                  title: Text(
                    _pdfBaseName != null
                        ? '$_pdfBaseName.pdf'
                        : 'Belum ada PDF dipilih',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _pageCount != null
                        ? '$_pageCount halaman'
                        : 'Ketuk tombol di kanan untuk memilih file PDF',
                  ),
                  trailing: OutlinedButton(
                    onPressed: _pickPdf,
                    child: const Text('Pilih'),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Format Gambar',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<ExportImageFormat>(
                segments: const [
                  ButtonSegment(
                    value: ExportImageFormat.png,
                    label: Text('PNG'),
                  ),
                  ButtonSegment(
                    value: ExportImageFormat.jpeg,
                    label: Text('JPG'),
                  ),
                ],
                selected: {_format},
                onSelectionChanged: (s) => setState(() => _format = s.first),
              ),
              const SizedBox(height: 10),
              Text(
                _pageCount != null && _pageCount! > 1
                    ? 'Hasil $_pageCount halaman akan dikemas otomatis ke $_pdfBaseName.zip.'
                    : 'Jika PDF berisi 1 halaman, hasil berupa satu file gambar langsung.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _pdfPath == null || _busy ? null : _convert,
                icon: const Icon(Icons.image_rounded),
                label: const Text('Konversi Sekarang'),
              ),
            ],
          ),
          if (_busy) _BusyOverlay(message: _statusText),
        ],
      ),
    );
  }
}

// ============================================================================
// 3. Compress PDF (rasterize via pdfx + compact DCTDecode PDF in Rust)
// ============================================================================

class _CompressPdfToolPage extends ConsumerStatefulWidget {
  const _CompressPdfToolPage();

  @override
  ConsumerState<_CompressPdfToolPage> createState() =>
      _CompressPdfToolPageState();
}

class _CompressPdfToolPageState extends ConsumerState<_CompressPdfToolPage> {
  String? _pdfPath;
  String? _pdfBaseName;
  int? _pageCount;
  int? _origBytes;
  PdfCompressLevel _level = PdfCompressLevel.medium;
  bool _busy = false;
  String _statusText = '';

  Future<void> _pickPdf() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Pilih file PDF',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (picked == null || picked.path == null || !mounted) return;
    final path = picked.path!;
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(path);
      final count = doc.pagesCount;
      final size = await File(path).length();
      if (mounted) {
        setState(() {
          _pdfPath = path;
          _pdfBaseName = sanitizeFileName(
            p.basenameWithoutExtension(picked.name),
            fallback: 'dokumen',
          );
          _pageCount = count;
          _origBytes = size;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PDF tidak dapat dibuka (rusak atau terenkripsi/berkata sandi).',
            ),
          ),
        );
      }
    } finally {
      await doc?.close();
    }
  }

  Future<void> _compress() async {
    final pdfPath = _pdfPath;
    if (pdfPath == null || _busy) return;
    setState(() {
      _busy = true;
      _statusText = 'Membuka PDF...';
    });

    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(pdfPath);
      final total = doc.pagesCount;
      if (total <= 0) {
        throw const FormatException('File PDF tidak memiliki halaman.');
      }

      final workDir = await ref
          .read(fileStoreProvider)
          .createTempWorkDir('compress');
      final pagePaths = <String>[];

      for (var i = 1; i <= total; i++) {
        if (mounted) {
          setState(
            () => _statusText = 'Mengompres halaman $i dari $total...',
          );
        }
        final page = await doc.getPage(i);
        try {
          var w = page.width * _level.renderScale;
          var h = page.height * _level.renderScale;
          final longSide = w > h ? w : h;
          if (longSide > 1800) {
            final s = 1800 / longSide;
            w *= s;
            h *= s;
          }
          final rendered = await page.render(
            width: w,
            height: h,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
            quality: _level.jpegQuality,
          );
          if (rendered == null) {
            throw FormatException('Gagal memproses halaman $i.');
          }
          final jpgPath = p.join(workDir.path, 'c_$i.jpg');
          await File(jpgPath).writeAsBytes(rendered.bytes, flush: true);
          pagePaths.add(jpgPath);
        } finally {
          await page.close();
        }
      }

      if (mounted) setState(() => _statusText = 'Menyusun PDF terkompresi...');
      final outName = '${_pdfBaseName ?? 'dokumen'}_kompres.pdf';
      final outPdf = p.join(workDir.path, outName);
      await imagesToPdf(
        pages: pagePaths,
        out: outPdf,
        opts: PdfOpts(
          fit: PdfFit.a4,
          jpegQuality: _level.jpegQuality,
          marginPt: 0.0,
        ),
      );

      final newSize = await File(outPdf).length();
      final beforeStr = _origBytes != null ? formatBytes(_origBytes!) : '-';
      final afterStr = formatBytes(newSize);

      if (mounted) {
        await _presentOutputActions(
          context,
          filePath: outPdf,
          fileName: outName,
          mimeType: 'application/pdf',
          subtitle: 'Ukuran: $beforeStr → $afterStr',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatError(e))),
        );
      }
    } finally {
      await doc?.close();
      if (mounted) {
        setState(() {
          _busy = false;
          _statusText = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Kompres PDF')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.compress_rounded,
                    color: scheme.primary,
                  ),
                  title: Text(
                    _pdfBaseName != null
                        ? '$_pdfBaseName.pdf'
                        : 'Belum ada PDF dipilih',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _pageCount != null && _origBytes != null
                        ? '$_pageCount halaman · ${formatBytes(_origBytes!)}'
                        : 'Pilih PDF yang ingin diperkecil ukurannya',
                  ),
                  trailing: OutlinedButton(
                    onPressed: _pickPdf,
                    child: const Text('Pilih'),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Tingkat Kompresi',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<PdfCompressLevel>(
                segments: PdfCompressLevel.values
                    .map(
                      (lvl) => ButtonSegment(
                        value: lvl,
                        label: Text(lvl.label),
                      ),
                    )
                    .toList(),
                selected: {_level},
                onSelectionChanged: (s) => setState(() => _level = s.first),
              ),
              const SizedBox(height: 8),
              Text(
                switch (_level) {
                  PdfCompressLevel.light =>
                    'Kualitas teks tinggi, pengurangan ukuran moderat.',
                  PdfCompressLevel.medium =>
                    'Seimbang antara keterbacaan dan ukuran kecil (disarankan).',
                  PdfCompressLevel.strong =>
                    'Ukuran terkecil untuk batas unggah ketat (< 1 MB).',
                },
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _pdfPath == null || _busy ? null : _compress,
                icon: const Icon(Icons.compress_rounded),
                label: const Text('Kompres Sekarang'),
              ),
            ],
          ),
          if (_busy) _BusyOverlay(message: _statusText),
        ],
      ),
    );
  }
}

// ============================================================================
// 4. Merge PDFs
// ============================================================================

class _MergePdfToolPage extends ConsumerStatefulWidget {
  const _MergePdfToolPage();

  @override
  ConsumerState<_MergePdfToolPage> createState() => _MergePdfToolPageState();
}

class _MergePdfToolPageState extends ConsumerState<_MergePdfToolPage> {
  final _nameCtrl = TextEditingController(
    text: '${defaultDocumentName()}_gabung',
  );
  final List<({String path, String name})> _pdfs = [];
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPdfs() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Pilih file PDF',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (f.path != null) {
          _pdfs.add((path: f.path!, name: f.name));
        }
      }
    });
  }

  Future<void> _merge() async {
    if (_pdfs.length < 2 || _busy) return;
    setState(() => _busy = true);
    try {
      final workDir = await ref
          .read(fileStoreProvider)
          .createTempWorkDir('merge');
      final fileName = '${sanitizeFileName(_nameCtrl.text)}.pdf';
      final outPath = p.join(workDir.path, fileName);
      await mergePdfs(
        inputs: _pdfs.map((e) => e.path).toList(),
        out: outPath,
      );
      if (mounted) {
        await _presentOutputActions(
          context,
          filePath: outPath,
          fileName: fileName,
          mimeType: 'application/pdf',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gabung PDF')),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nama file hasil',
                          suffixText: '.pdf',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _pickPdfs,
                      icon: const Icon(Icons.add),
                      label: const Text('PDF'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _pdfs.isEmpty
                    ? Center(
                        child: Text(
                          'Pilih minimal 2 file PDF.\nGeser untuk mengubah urutan penggabungan.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: _pdfs.length,
                        onReorderItem: (oldIdx, newIdx) {
                          setState(() {
                            final item = _pdfs.removeAt(oldIdx);
                            _pdfs.insert(newIdx, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final item = _pdfs[index];
                          return Card(
                            key: ValueKey('${item.path}_$index'),
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 16,
                                child: Text('${index + 1}'),
                              ),
                              title: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () =>
                                        setState(() => _pdfs.removeAt(index)),
                                  ),
                                  const Icon(Icons.drag_handle_rounded),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _pdfs.length < 2 || _busy ? null : _merge,
                      icon: const Icon(Icons.merge_type_rounded),
                      label: Text('Gabung ${_pdfs.length} PDF'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_busy) const _BusyOverlay(message: 'Menggabungkan PDF...'),
        ],
      ),
    );
  }
}

// ============================================================================
// 5. Split PDF (visual page thumbnails + manual range input)
// ============================================================================

class _SplitPdfToolPage extends ConsumerStatefulWidget {
  const _SplitPdfToolPage();

  @override
  ConsumerState<_SplitPdfToolPage> createState() => _SplitPdfToolPageState();
}

class _SplitPdfToolPageState extends ConsumerState<_SplitPdfToolPage> {
  final _rangeCtrl = TextEditingController();
  String? _pdfPath;
  String? _pdfName;
  int? _pageCount;
  bool _busy = false;
  bool _loadingThumbs = false;
  final List<Uint8List?> _thumbs = [];
  final Set<int> _selectedPages = {};

  @override
  void dispose() {
    _rangeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Pilih file PDF',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (picked == null || picked.path == null || !mounted) return;
    final path = picked.path!;
    PdfDocument? doc;
    int? count;
    final loadedThumbs = <Uint8List?>[];

    setState(() {
      _pdfPath = path;
      _pdfName = picked.name;
      _pageCount = null;
      _thumbs.clear();
      _selectedPages.clear();
      _rangeCtrl.clear();
      _loadingThumbs = true;
    });

    try {
      doc = await PdfDocument.openFile(path);
      count = doc.pagesCount;
      // Render lightweight visual thumbnails (cap at 30 pages to keep memory small).
      final previewLimit = count > 30 ? 30 : count;
      for (var i = 1; i <= previewLimit; i++) {
        final page = await doc.getPage(i);
        try {
          final aspect = page.width / (page.height == 0 ? 1 : page.height);
          const thumbH = 160.0;
          final thumbW = (thumbH * aspect).clamp(60.0, 200.0);
          final img = await page.render(
            width: thumbW,
            height: thumbH,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
            quality: 60,
          );
          loadedThumbs.add(img?.bytes);
        } finally {
          await page.close();
        }
      }
    } catch (_) {
      // Allow Rust lopdf to report exact encryption/corruption error on split.
    } finally {
      await doc?.close();
    }

    if (mounted) {
      setState(() {
        _pageCount = count;
        _thumbs
          ..clear()
          ..addAll(loadedThumbs);
        _loadingThumbs = false;
      });
    }
  }

  void _togglePageThumb(int pageNum) {
    setState(() {
      if (_selectedPages.contains(pageNum)) {
        _selectedPages.remove(pageNum);
      } else {
        _selectedPages.add(pageNum);
      }
      _rangeCtrl.text = formatPageRangeList(_selectedPages);
    });
  }

  Future<void> _split() async {
    final pdfPath = _pdfPath;
    if (pdfPath == null || _busy) return;
    setState(() => _busy = true);
    try {
      final ranges = parsePageRanges(_rangeCtrl.text, maxPage: _pageCount);
      final workDir = await ref
          .read(fileStoreProvider)
          .createTempWorkDir('split');
      final outFiles = await splitPdf(
        input: pdfPath,
        outDir: workDir.path,
        ranges: ranges,
      );
      if (outFiles.isEmpty) {
        throw const FormatException('Tidak ada file hasil pemisahan.');
      }

      if (outFiles.length == 1) {
        final f = outFiles.first;
        if (mounted) {
          await _presentOutputActions(
            context,
            filePath: f,
            fileName: p.basename(f),
            mimeType: 'application/pdf',
          );
        }
      } else {
        final stem = sanitizeFileName(
          p.basenameWithoutExtension(_pdfName ?? 'dokumen'),
          fallback: 'dokumen',
        );
        final zipName = '${stem}_pisah.zip';
        final zipPath = p.join(workDir.path, zipName);
        await zipFiles(
          entries: outFiles
              .map((f) => ZipEntry(srcPath: f, nameInZip: p.basename(f)))
              .toList(),
          outZip: zipPath,
        );
        if (mounted) {
          await _presentOutputActions(
            context,
            filePath: zipPath,
            fileName: zipName,
            mimeType: 'application/zip',
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pisah PDF')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.picture_as_pdf_outlined,
                    color: scheme.primary,
                  ),
                  title: Text(
                    _pdfName ?? 'Belum ada PDF dipilih',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _pageCount != null
                        ? 'Total $_pageCount halaman'
                        : 'Pilih file PDF yang ingin dipisahkan',
                  ),
                  trailing: OutlinedButton(
                    onPressed: _pickPdf,
                    child: const Text('Pilih'),
                  ),
                ),
              ),
              if (_loadingThumbs) ...[
                const SizedBox(height: 16),
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              ] else if (_thumbs.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Ketuk halaman untuk memilih (${_selectedPages.length} dipilih)',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 132,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _thumbs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final pageNum = index + 1;
                      final selected = _selectedPages.contains(pageNum);
                      final bytes = _thumbs[index];
                      return GestureDetector(
                        onTap: () => _togglePageThumb(pageNum),
                        child: Container(
                          width: 86,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected ? scheme.primary : scheme.outline,
                              width: selected ? 2.5 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (bytes != null)
                                Image.memory(bytes, fit: BoxFit.cover)
                              else
                                Container(color: scheme.surfaceContainerHighest),
                              if (selected)
                                Container(
                                  color: scheme.primary.withValues(alpha: 0.18),
                                ),
                              Positioned(
                                right: 4,
                                bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? scheme.primary
                                        : Colors.black.withValues(alpha: 0.68),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$pageNum',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_pageCount != null && _pageCount! > _thumbs.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Menampilkan pratinjau ${_thumbs.length} halaman pertama; ketik rentang di bawah untuk halaman lainnya.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 18),
              TextField(
                controller: _rangeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Rentang halaman',
                  hintText: 'Contoh: 1-3, 5, 7-9',
                  helperText:
                      'Pisahkan tiap bagian dengan koma. Lebih dari 1 bagian otomatis dibungkus ZIP.',
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _pdfPath == null || _busy ? null : _split,
                icon: const Icon(Icons.call_split_rounded),
                label: const Text('Pisahkan PDF'),
              ),
            ],
          ),
          if (_busy) const _BusyOverlay(message: 'Memisahkan PDF...'),
        ],
      ),
    );
  }
}

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black45,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 14),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
