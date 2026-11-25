import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../src/rust/api.dart';
import '../state/providers.dart';
import '../widgets/category_sheet.dart';
import 'camera_screen.dart';
import 'corner_edit_screen.dart';
import 'export_screen.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.docId});

  final String docId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _pageController = PageController();
  int _currentIndex = 0;
  int _imageRev = 0;
  bool _showFilters = false;
  String? _busyMessage;

  // Local slider values synced to active page.
  double _draftBrightness = 0.0;
  double _draftContrast = 0.0;

  ScanDocument? _doc;
  List<ScanPage> _pages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
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
      _loading = false;
      if (_pages.isNotEmpty && _currentIndex >= _pages.length) {
        _currentIndex = _pages.length - 1;
      }
      _syncSlidersToActive();
    });
  }

  void _syncSlidersToActive() {
    final p = _activePage;
    if (p != null) {
      _draftBrightness = p.brightness;
      _draftContrast = p.contrast;
    }
  }

  ScanPage? get _activePage =>
      _pages.isNotEmpty && _currentIndex < _pages.length
          ? _pages[_currentIndex]
          : null;

  Future<void> _runBusy(String message, Future<void> Function() task) async {
    setState(() => _busyMessage = message);
    try {
      await task();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busyMessage = null);
    }
  }

  Future<void> _renameDocument() async {
    final doc = _doc;
    if (doc == null) return;
    final ctrl = TextEditingController(text: doc.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ganti nama dokumen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(repositoryProvider).renameDocument(doc.id, name);
      await _load();
      await ref.read(documentsProvider.notifier).refresh();
    }
  }

  Future<void> _editCategory() async {
    final doc = _doc;
    if (doc == null) return;
    final picked = await showCategoryPickerSheet(
      context,
      currentTag: doc.tag,
    );
    if (picked == null || !mounted) return;
    await ref.read(documentsProvider.notifier).setTag(doc.id, picked);
    await _load();
  }

  Future<void> _rotateActivePage() async {
    final page = _activePage;
    if (page == null) return;
    await _runBusy('Memutar halaman...', () async {
      final updated = await ref
          .read(repositoryProvider)
          .reprocessPage(page, rotation: (page.rotation + 90) % 360);
      if (mounted) {
        setState(() {
          _pages[_currentIndex] = updated;
          _imageRev++;
        });
      }
    });
  }

  Future<void> _applyFilter(FilterKind filter) async {
    final page = _activePage;
    if (page == null || page.filter == filter) return;
    await _runBusy('Menerapkan filter ${filterLabel(filter)}...', () async {
      final updated = await ref
          .read(repositoryProvider)
          .reprocessPage(page, filter: filter);
      if (mounted) {
        setState(() {
          _pages[_currentIndex] = updated;
          _imageRev++;
        });
      }
    });
  }

  Future<void> _commitAdjustments({double? brightness, double? contrast}) async {
    final page = _activePage;
    if (page == null) return;
    final b = brightness ?? _draftBrightness;
    final c = contrast ?? _draftContrast;
    await _runBusy('Menyesuaikan kecerahan & kontras...', () async {
      final updated = await ref
          .read(repositoryProvider)
          .reprocessPage(page, brightness: b, contrast: c);
      if (mounted) {
        setState(() {
          _pages[_currentIndex] = updated;
          _draftBrightness = updated.brightness;
          _draftContrast = updated.contrast;
          _imageRev++;
        });
      }
    });
  }

  Future<void> _applyFilterToAll() async {
    final page = _activePage;
    if (page == null || _pages.length <= 1) return;
    final filter = page.filter;
    await _runBusy(
      'Menerapkan ${filterLabel(filter)} ke ${_pages.length} halaman...',
      () async {
        await ref.read(repositoryProvider).applyFilterToAllPages(
          widget.docId,
          filter,
          brightness: page.brightness,
          contrast: page.contrast,
        );
        await _load();
        if (mounted) setState(() => _imageRev++);
      },
    );
  }

  Future<void> _editCorners() async {
    final page = _activePage;
    if (page == null) return;
    final newQuad = await Navigator.of(context).push<Quad>(
      MaterialPageRoute(
        builder: (_) => CornerEditScreen.single(
          imagePath: page.origPath,
          initialQuad: page.corners,
        ),
      ),
    );
    if (newQuad == null || !mounted) return;
    await _runBusy('Memproses ulang sudut...', () async {
      final updated = await ref
          .read(repositoryProvider)
          .reprocessPage(page, corners: newQuad);
      if (mounted) {
        setState(() {
          _pages[_currentIndex] = updated;
          _imageRev++;
        });
      }
    });
  }

  Future<void> _addPagesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Pindai dengan Kamera'),
              onTap: () async {
                Navigator.pop(ctx);
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CameraScreen(existingDocId: widget.docId),
                  ),
                );
                await _load();
                await ref.read(documentsProvider.notifier).refresh();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Impor dari Galeri'),
              onTap: () {
                Navigator.pop(ctx);
                _importMoreFromGallery();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _importMoreFromGallery() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty || !mounted) return;

    final items = <CornerBatchItem>[];
    await _runBusy('Mendeteksi sudut gambar...', () async {
      for (final xfile in picked) {
        Quad quad;
        try {
          quad = await detectCornersFromFile(path: xfile.path);
        } catch (_) {
          quad = fallbackInsetQuad;
        }
        items.add(CornerBatchItem(imagePath: xfile.path, quad: quad));
      }
    });
    if (!mounted) return;

    final edited = await Navigator.of(context).push<List<CornerBatchItem>>(
      MaterialPageRoute(builder: (_) => CornerEditScreen.batch(items: items)),
    );
    if (edited == null || edited.isEmpty || !mounted) return;

    await _runBusy('Menambahkan ${edited.length} halaman...', () async {
      final repo = ref.read(repositoryProvider);
      final preferredFilter = ref.read(appSettingsProvider).defaultFilter;
      for (final item in edited) {
        await repo.addPageFromSource(
          docId: widget.docId,
          sourcePath: item.imagePath,
          quad: item.quad,
          filter: preferredFilter,
        );
      }
      await _load();
      await ref.read(documentsProvider.notifier).refresh();
    });
  }

  Future<void> _deleteActivePage() async {
    final page = _activePage;
    if (page == null) return;
    final lastPage = _pages.length == 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lastPage ? 'Hapus dokumen?' : 'Hapus halaman?'),
        content: Text(
          lastPage
              ? 'Ini adalah satu-satunya halaman. Menghapusnya akan menghapus seluruh dokumen.'
              : 'Halaman ${_currentIndex + 1} akan dihapus dari dokumen ini.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final remaining = await ref.read(repositoryProvider).deletePage(page);
    await ref.read(documentsProvider.notifier).refresh();
    if (!mounted) return;
    if (remaining == 0) {
      Navigator.of(context).pop();
    } else {
      await _load();
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentIndex);
      }
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final activeId = _activePage?.id;
    setState(() {
      final moved = _pages.removeAt(oldIndex);
      _pages.insert(newIndex, moved);
      if (activeId != null) {
        _currentIndex = _pages.indexWhere((p) => p.id == activeId);
      }
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(_currentIndex);
    }
    await ref
        .read(repositoryProvider)
        .reorderPages(widget.docId, _pages.map((p) => p.id).toList());
    await ref.read(documentsProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_doc == null || _pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dokumen')),
        body: const Center(child: Text('Dokumen tidak ditemukan.')),
      );
    }

    final active = _activePage!;
    final hasAdjust =
        _draftBrightness.abs() > 0.01 || _draftContrast.abs() > 0.01;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _renameDocument,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _doc!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.edit_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: _doc!.tag.isEmpty
                ? 'Atur kelompok'
                : 'Kelompok: ${_doc!.tag}',
            onPressed: _busyMessage != null ? null : _editCategory,
            icon: Icon(
              _doc!.tag.isEmpty
                  ? Icons.label_outline_rounded
                  : Icons.label_rounded,
              color: _doc!.tag.isEmpty
                  ? scheme.onSurface
                  : (Theme.of(context).brightness == Brightness.dark
                      ? AppColors.yellow
                      : AppColors.yellowDeep),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.yellow,
                foregroundColor: AppColors.charcoal,
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: _busyMessage != null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ExportScreen(docId: widget.docId),
                      ),
                    ),
              icon: const Icon(Icons.ios_share_rounded, size: 17),
              label: const Text('Ekspor'),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Container(
                  color: scheme.surfaceContainerHighest,
                  child: Stack(
                    children: [
                      PageView.builder(
                        controller: _pageController,
                        itemCount: _pages.length,
                        onPageChanged: (i) => setState(() {
                          _currentIndex = i;
                          _syncSlidersToActive();
                        }),
                        itemBuilder: (context, index) {
                          final page = _pages[index];
                          return InteractiveViewer(
                            minScale: 1.0,
                            maxScale: 4.0,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Image.file(
                                  File(page.outPath),
                                  key: ValueKey('${page.id}_$_imageRev'),
                                  fit: BoxFit.contain,
                                  cacheWidth: 1600,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      if (_doc!.tag.isNotEmpty)
                        Positioned(
                          top: 10,
                          left: 12,
                          right: 92,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              color: AppColors.yellow,
                              shape: const StadiumBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: _busyMessage != null
                                    ? null
                                    : _editCategory,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.label_rounded,
                                        size: 13,
                                        color: AppColors.charcoal,
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          _doc!.tag,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.charcoal,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 10,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.charcoal.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppColors.yellow,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_currentIndex + 1} / ${_pages.length}',
                                style: const TextStyle(
                                  color: AppColors.bgLight,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Filter & fine brightness/contrast adjustment panel.
              if (_showFilters)
                Container(
                  color: scheme.surface,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: FilterKind.values.map((f) {
                            final selected = active.filter == f;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                showCheckmark: false,
                                selectedColor: AppColors.yellow,
                                labelStyle: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: selected
                                      ? AppColors.charcoal
                                      : scheme.onSurface,
                                ),
                                label: Text(filterLabel(f)),
                                selected: selected,
                                onSelected: (_) => _applyFilter(f),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          SizedBox(
                            width: 78,
                            child: Text(
                              'Kecerahan',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: _draftBrightness.clamp(-1.0, 1.0),
                              min: -1.0,
                              max: 1.0,
                              onChanged: (v) =>
                                  setState(() => _draftBrightness = v),
                              onChangeEnd: (v) =>
                                  _commitAdjustments(brightness: v),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          SizedBox(
                            width: 78,
                            child: Text(
                              'Kontras',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: _draftContrast.clamp(-1.0, 1.0),
                              min: -1.0,
                              max: 1.0,
                              onChanged: (v) =>
                                  setState(() => _draftContrast = v),
                              onChangeEnd: (v) =>
                                  _commitAdjustments(contrast: v),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (hasAdjust)
                            TextButton(
                              onPressed: () => _commitAdjustments(
                                brightness: 0.0,
                                contrast: 0.0,
                              ),
                              child: const Text('Reset'),
                            ),
                          if (_pages.length > 1)
                            TextButton.icon(
                              onPressed: _applyFilterToAll,
                              icon: const Icon(Icons.done_all_rounded, size: 16),
                              label: const Text('Terapkan ke semua'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

              // Reorderable horizontal page strip.
              Container(
                height: 92,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(top: BorderSide(color: scheme.outline)),
                ),
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  itemCount: _pages.length,
                  onReorderItem: _onReorder,
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    final selected = index == _currentIndex;
                    return GestureDetector(
                      key: ValueKey(page.id),
                      onTap: () {
                        setState(() {
                          _currentIndex = index;
                          _syncSlidersToActive();
                        });
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Container(
                        width: 56,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected ? AppColors.yellow : scheme.outline,
                            width: selected ? 2.5 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              File(page.thumbPath),
                              key: ValueKey('thumb_${page.id}_$_imageRev'),
                              fit: BoxFit.cover,
                              cacheWidth: 160,
                            ),
                            Positioned(
                              right: 3,
                              bottom: 3,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.yellow
                                      : AppColors.charcoal.withValues(
                                          alpha: 0.78,
                                        ),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: selected
                                        ? AppColors.charcoal
                                        : AppColors.bgLight,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
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

              // Bottom tool actions.
              Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(top: BorderSide(color: scheme.outline)),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _ToolAction(
                        icon: Icons.tune_rounded,
                        label: 'Filter',
                        active: _showFilters,
                        onTap: () =>
                            setState(() => _showFilters = !_showFilters),
                      ),
                      _ToolAction(
                        icon: Icons.crop_rounded,
                        label: 'Sudut',
                        onTap: _editCorners,
                      ),
                      _ToolAction(
                        icon: Icons.rotate_right_rounded,
                        label: 'Putar',
                        onTap: _rotateActivePage,
                      ),
                      _ToolAction(
                        icon: Icons.add_photo_alternate_outlined,
                        label: 'Tambah',
                        onTap: _addPagesSheet,
                      ),
                      _ToolAction(
                        icon: Icons.delete_outline_rounded,
                        label: 'Hapus',
                        color: scheme.error,
                        onTap: _deleteActivePage,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          if (_busyMessage != null)
            Container(
              color: Colors.black45,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(width: 14),
                        Text(_busyMessage!),
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

class _ToolAction extends StatelessWidget {
  const _ToolAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeFg = isDark ? AppColors.yellow : AppColors.charcoal;
    final activeBg = isDark
        ? AppColors.yellowContainerDark
        : AppColors.yellowSoftLight;
    final fg = color ?? (active ? activeFg : scheme.onSurface);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: active ? activeBg : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(icon, size: 21, color: fg),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
