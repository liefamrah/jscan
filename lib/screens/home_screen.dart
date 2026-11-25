import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../src/rust/api.dart';
import '../state/providers.dart';
import '../widgets/illustrations.dart';
import 'camera_screen.dart';
import 'corner_edit_screen.dart';
import 'export_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';
import 'tools_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchCtrl = TextEditingController();
  int _tabIndex = 0;
  bool _importing = false;
  bool _searching = false;
  final Set<String> _selectedIds = {};

  bool get _inSelectionMode => _selectedIds.isNotEmpty;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSelect(String docId) {
    setState(() {
      if (_selectedIds.contains(docId)) {
        _selectedIds.remove(docId);
      } else {
        _selectedIds.add(docId);
      }
    });
  }

  void _clearSelection() {
    if (_selectedIds.isNotEmpty) {
      setState(() => _selectedIds.clear());
    }
  }

  void _selectTab(int i) {
    _clearSelection();
    if (i != 0 && _searching) {
      _searching = false;
      _searchCtrl.clear();
      ref.read(homeSearchQueryProvider.notifier).setQuery('');
    }
    setState(() => _tabIndex = i);
  }

  Future<void> _openCamera() async {
    final docId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
    await ref.read(documentsProvider.notifier).refresh();
    if (docId != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReviewScreen(docId: docId)),
      );
      await ref.read(documentsProvider.notifier).refresh();
    }
  }

  Future<void> _importImages() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage();
      if (picked.isEmpty || !mounted) return;

      final items = <CornerBatchItem>[];
      await _withProgressDialog('Mendeteksi sudut gambar...', () async {
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
        MaterialPageRoute(
          builder: (_) => CornerEditScreen.batch(items: items),
        ),
      );
      if (edited == null || edited.isEmpty || !mounted) return;

      final repo = ref.read(repositoryProvider);
      final preferredFilter = ref.read(appSettingsProvider).defaultFilter;
      ScanDocument? doc;
      await _withProgressDialog(
        'Memproses ${edited.length} halaman...',
        () async {
          doc = await repo.createDocument();
          try {
            for (final item in edited) {
              await repo.addPageFromSource(
                docId: doc!.id,
                sourcePath: item.imagePath,
                quad: item.quad,
                filter: preferredFilter,
              );
            }
          } catch (_) {
            final current = await repo.getDocument(doc!.id);
            if (current == null || current.pageCount == 0) {
              await repo.deleteDocument(doc!.id);
            }
            rethrow;
          }
        },
      );

      await ref.read(documentsProvider.notifier).refresh();
      if (mounted && doc != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ReviewScreen(docId: doc!.id)),
        );
        await ref.read(documentsProvider.notifier).refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _withProgressDialog(
    String message,
    Future<void> Function() task,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
    try {
      await task();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _bulkDelete() async {
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus $count dokumen?'),
        content: const Text(
          'Semua dokumen terpilih akan dihapus permanen dari perangkat.',
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
    if (ok == true) {
      final ids = _selectedIds.toList();
      _clearSelection();
      await ref.read(documentsProvider.notifier).deleteMany(ids);
    }
  }

  Future<void> _bulkMerge() async {
    if (_selectedIds.length < 2) return;
    final ids = _selectedIds.toList();
    _clearSelection();
    try {
      ScanDocument? merged;
      await _withProgressDialog(
        'Menggabungkan ${ids.length} dokumen...',
        () async {
          merged = await ref.read(documentsProvider.notifier).mergeDocs(ids);
        },
      );
      if (mounted && merged != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Digabung menjadi "${merged!.name}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(formatError(e))),
        );
      }
    }
  }

  Future<void> _showDocActions(ScanDocument doc) async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Ganti nama'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(doc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.label_outline_rounded),
              title: const Text('Atur label'),
              trailing: doc.tag.isNotEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.yellow,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        doc.tag,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.charcoal,
                        ),
                      ),
                    )
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                _showTagDialog(doc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist_rounded),
              title: const Text('Pilih beberapa dokumen'),
              onTap: () {
                Navigator.pop(ctx);
                _toggleSelect(doc.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('Ekspor'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ExportScreen(docId: doc.id)),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
              title: Text('Hapus', style: TextStyle(color: scheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(doc);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showTagDialog(ScanDocument doc) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pilih label dokumen'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Row(
              children: [
                Icon(
                  doc.tag.isEmpty
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20,
                ),
                const SizedBox(width: 12),
                const Text('Tanpa label'),
              ],
            ),
          ),
          ...documentTags.map(
            (tag) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, tag),
              child: Row(
                children: [
                  Icon(
                    doc.tag == tag
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(tag),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (picked != null) {
      await ref.read(documentsProvider.notifier).setTag(doc.id, picked);
    }
  }

  Future<void> _showRenameDialog(ScanDocument doc) async {
    final controller = TextEditingController(text: doc.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ganti nama dokumen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nama dokumen'),
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName != null && newName.trim().isNotEmpty) {
      await ref.read(documentsProvider.notifier).rename(doc.id, newName);
    }
  }

  Future<void> _confirmDelete(ScanDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus dokumen?'),
        content: Text(
          'Dokumen "${doc.name}" (${doc.pageCount} halaman) akan dihapus permanen dari perangkat.',
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
    if (confirmed == true) {
      await ref.read(documentsProvider.notifier).delete(doc.id);
    }
  }

  Future<void> _openReview(ScanDocument doc) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReviewScreen(docId: doc.id)),
    );
    await ref.read(documentsProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isGrid = ref.watch(
      appSettingsProvider.select((s) => s.defaultGridView),
    );
    final selectedTag = ref.watch(homeSelectedTagProvider);
    final currentSort = ref.watch(homeSortProvider);
    final searchQuery = ref.watch(homeSearchQueryProvider);
    final docsAsync = ref.watch(documentsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    // Layered top band palette: Warm Yellow in Light, Warm Charcoal in Dark.
    final headerBg = isDark ? AppColors.surfaceDark : AppColors.yellow;
    final headerInk = isDark ? AppColors.textPrimaryDark : AppColors.charcoal;
    final headerIconBg = isDark
        ? AppColors.charcoalElevated
        : AppColors.charcoal.withValues(alpha: 0.10);

    final docsList = docsAsync.value ?? const <ScanDocument>[];
    final totalPages = docsList.fold<int>(0, (sum, d) => sum + d.pageCount);
    final showOverview =
        _tabIndex == 0 && !_searching && !_inSelectionMode && docsList.isNotEmpty;

    return PopScope(
      canPop: !_inSelectionMode && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_inSelectionMode) {
            _clearSelection();
          } else if (_searching) {
            setState(() => _searching = false);
            _searchCtrl.clear();
            ref.read(homeSearchQueryProvider.notifier).setQuery('');
          }
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: headerBg,
          body: Column(
            children: [
              // Top editorial header band.
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    10,
                    16,
                    showOverview ? 16 : 14,
                  ),
                  child: Column(
                    children: [
                      _buildTopBar(
                        context: context,
                        isDark: isDark,
                        isGrid: isGrid,
                        currentSort: currentSort,
                        headerInk: headerInk,
                        headerIconBg: headerIconBg,
                        scheme: scheme,
                        textTheme: textTheme,
                      ),
                      if (showOverview) ...[
                        const SizedBox(height: 14),
                        _HeaderOverviewCard(
                          docCount: docsList.length,
                          pageCount: totalPages,
                          isDark: isDark,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Main rounded workspace sheet.
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: switch (_tabIndex) {
                    0 => _buildDocsTab(
                        context: context,
                        docsAsync: docsAsync,
                        docsCount: docsList.length,
                        selectedTag: selectedTag,
                        searchQuery: searchQuery,
                        isGrid: isGrid,
                        isDark: isDark,
                        scheme: scheme,
                        textTheme: textTheme,
                      ),
                    1 => const ToolsScreen(),
                    _ => const SettingsScreen(),
                  },
                ),
              ),
            ],
          ),
          bottomNavigationBar: _JScanBottomBar(
            tabIndex: _tabIndex,
            importing: _importing,
            onSelectTab: _selectTab,
            onScan: _openCamera,
            onImport: _importImages,
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar({
    required BuildContext context,
    required bool isDark,
    required bool isGrid,
    required DocSort currentSort,
    required Color headerInk,
    required Color headerIconBg,
    required ColorScheme scheme,
    required TextTheme textTheme,
  }) {
    if (_tabIndex == 0 && _inSelectionMode) {
      return SizedBox(
        height: 44,
        child: Row(
          children: [
            _HeaderCircleButton(
              tooltip: 'Batal pilih',
              icon: Icons.close_rounded,
              bg: headerIconBg,
              fg: headerInk,
              onPressed: _clearSelection,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${_selectedIds.length} dipilih',
                style: textTheme.titleLarge?.copyWith(
                  color: headerInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_selectedIds.length >= 2) ...[
              _HeaderCircleButton(
                tooltip: 'Gabung dokumen',
                icon: Icons.merge_type_rounded,
                bg: headerIconBg,
                fg: headerInk,
                onPressed: _bulkMerge,
              ),
              const SizedBox(width: 8),
            ],
            _HeaderCircleButton(
              tooltip: 'Hapus terpilih',
              icon: Icons.delete_outline_rounded,
              bg: scheme.error.withValues(alpha: isDark ? 0.22 : 0.16),
              fg: scheme.error,
              onPressed: _bulkDelete,
            ),
          ],
        ),
      );
    }

    if (_tabIndex == 0 && _searching) {
      return Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.charcoalElevated : Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Cari nama dokumen...',
                  hintStyle: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (v) =>
                    ref.read(homeSearchQueryProvider.notifier).setQuery(v),
              ),
            ),
            GestureDetector(
              onTap: () {
                setState(() => _searching = false);
                _searchCtrl.clear();
                ref.read(homeSearchQueryProvider.notifier).setQuery('');
              },
              child: Icon(
                Icons.close_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_tabIndex != 0) {
      return SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: Text(
                _tabIndex == 1 ? 'Alat Konversi' : 'Pengaturan',
                style: textTheme.headlineSmall?.copyWith(
                  color: headerInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: headerIconBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: isDark ? AppColors.yellow : AppColors.charcoal,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Offline',
                    style: textTheme.labelSmall?.copyWith(
                      color: headerInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const JScanLogoMark(size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              appName,
              style: textTheme.headlineSmall?.copyWith(
                color: headerInk,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
          ),
          _HeaderCircleButton(
            tooltip: 'Cari dokumen',
            icon: Icons.search_rounded,
            bg: headerIconBg,
            fg: headerInk,
            onPressed: () => setState(() => _searching = true),
          ),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: headerIconBg,
              shape: BoxShape.circle,
            ),
            child: PopupMenuButton<DocSort>(
              tooltip: 'Urutkan',
              padding: EdgeInsets.zero,
              icon: Icon(Icons.sort_rounded, size: 20, color: headerInk),
              initialValue: currentSort,
              onSelected: (s) => ref.read(homeSortProvider.notifier).select(s),
              itemBuilder: (_) => DocSort.values
                  .map(
                    (s) => PopupMenuItem(
                      value: s,
                      child: Text(s.label),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(width: 8),
          _HeaderCircleButton(
            tooltip: isGrid ? 'Tampilan daftar' : 'Tampilan grid',
            icon: isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
            bg: headerIconBg,
            fg: headerInk,
            onPressed: () =>
                ref.read(appSettingsProvider.notifier).toggleGridView(),
          ),
        ],
      ),
    );
  }

  Widget _buildDocsTab({
    required BuildContext context,
    required AsyncValue<List<ScanDocument>> docsAsync,
    required int docsCount,
    required String selectedTag,
    required String searchQuery,
    required bool isGrid,
    required bool isDark,
    required ColorScheme scheme,
    required TextTheme textTheme,
  }) {
    return Column(
      children: [
        // Editorial section header + count pill.
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
          child: Row(
            children: [
              Text(
                'DOKUMEN',
                style: textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.yellowContainerDark
                      : AppColors.yellowSoftLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$docsCount',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.yellow : AppColors.charcoal,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Tag filter strip.
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _TagPillChip(
                  label: 'Semua',
                  selected: selectedTag.isEmpty,
                  onTap: () =>
                      ref.read(homeSelectedTagProvider.notifier).select(''),
                ),
              ),
              ...documentTags.map(
                (tag) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _TagPillChip(
                    label: tag,
                    selected: selectedTag == tag,
                    onTap: () => ref
                        .read(homeSelectedTagProvider.notifier)
                        .select(selectedTag == tag ? '' : tag),
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: docsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  formatError(err),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (docs) {
              if (docs.isEmpty) {
                final filtered =
                    searchQuery.trim().isNotEmpty || selectedTag.isNotEmpty;
                if (filtered) {
                  return _EmptySearchView(
                    onReset: () {
                      setState(() => _searching = false);
                      _searchCtrl.clear();
                      ref.read(homeSearchQueryProvider.notifier).setQuery('');
                      ref.read(homeSelectedTagProvider.notifier).select('');
                    },
                  );
                }
                return _EmptyDocsView(
                  onScan: _openCamera,
                  onImport: _importImages,
                );
              }
              return RefreshIndicator(
                onRefresh: () => ref.read(documentsProvider.notifier).refresh(),
                child: isGrid
                    ? _DocumentsGrid(
                        docs: docs,
                        selectedIds: _selectedIds,
                        onOpen: (d) => _inSelectionMode
                            ? _toggleSelect(d.id)
                            : _openReview(d),
                        onLongPress: (d) => _inSelectionMode
                            ? _toggleSelect(d.id)
                            : _showDocActions(d),
                        onMore: _showDocActions,
                      )
                    : _DocumentsList(
                        docs: docs,
                        selectedIds: _selectedIds,
                        onOpen: (d) => _inSelectionMode
                            ? _toggleSelect(d.id)
                            : _openReview(d),
                        onLongPress: (d) => _inSelectionMode
                            ? _toggleSelect(d.id)
                            : _showDocActions(d),
                        onMore: _showDocActions,
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({
    required this.tooltip,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: fg),
          ),
        ),
      ),
    );
  }
}

class _HeaderOverviewCard extends StatelessWidget {
  const _HeaderOverviewCard({
    required this.docCount,
    required this.pageCount,
    required this.isDark,
  });

  final int docCount;
  final int pageCount;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cardBg = isDark ? AppColors.charcoalElevated : Colors.white;
    final primaryText = isDark ? AppColors.textPrimaryDark : AppColors.charcoal;
    final mutedText = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark
              : AppColors.charcoal.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.yellowContainerDark
                  : AppColors.yellowSoftLight,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.folder_copy_rounded,
              size: 21,
              color: isDark ? AppColors.yellow : AppColors.charcoal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$docCount Dokumen · $pageCount Halaman',
                  style: textTheme.titleSmall?.copyWith(
                    color: primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tersimpan lokal & siap ekspor PDF/JPG',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: mutedText),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? AppColors.yellow : AppColors.charcoal,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 12,
                  color: isDark ? AppColors.charcoal : AppColors.yellow,
                ),
                const SizedBox(width: 4),
                Text(
                  'Offline',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.charcoal : AppColors.bgLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagPillChip extends StatelessWidget {
  const _TagPillChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? AppColors.yellow : scheme.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.yellow : scheme.outline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppColors.charcoal : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JScanBottomBar extends StatelessWidget {
  const _JScanBottomBar({
    required this.tabIndex,
    required this.importing,
    required this.onSelectTab,
    required this.onScan,
    required this.onImport,
  });

  final int tabIndex;
  final bool importing;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onScan;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            children: [
              Expanded(
                child: _BottomNavSlot(
                  icon: Icons.description_outlined,
                  activeIcon: Icons.description_rounded,
                  label: 'Dokumen',
                  active: tabIndex == 0,
                  onTap: () => onSelectTab(0),
                ),
              ),
              Expanded(
                child: _BottomNavSlot(
                  icon: Icons.grid_view_outlined,
                  activeIcon: Icons.grid_view_rounded,
                  label: 'Alat',
                  active: tabIndex == 1,
                  onTap: () => onSelectTab(1),
                ),
              ),
              // Center circular primary Scan action (echoing UI reference).
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Tooltip(
                  message: 'Pindai dokumen',
                  child: Material(
                    color: AppColors.yellow,
                    shape: CircleBorder(
                      side: BorderSide(
                        color: isDark
                            ? AppColors.charcoal
                            : AppColors.charcoal.withValues(alpha: 0.14),
                        width: 1.5,
                      ),
                    ),
                    elevation: 2,
                    shadowColor: Colors.black.withValues(alpha: 0.25),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onScan,
                      child: const SizedBox(
                        width: 54,
                        height: 54,
                        child: Icon(
                          Icons.document_scanner_rounded,
                          color: AppColors.charcoal,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _BottomNavSlot(
                  icon: Icons.photo_library_outlined,
                  activeIcon: Icons.photo_library_rounded,
                  label: 'Impor',
                  active: false,
                  loading: importing,
                  onTap: importing ? () {} : onImport,
                ),
              ),
              Expanded(
                child: _BottomNavSlot(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings_rounded,
                  label: 'Setelan',
                  active: tabIndex == 2,
                  onTap: () => onSelectTab(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavSlot extends StatelessWidget {
  const _BottomNavSlot({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeFg = isDark ? AppColors.yellow : AppColors.charcoal;
    final activeBg = isDark
        ? AppColors.yellowContainerDark
        : AppColors.yellowSoftLight;
    final fg = active ? activeFg : scheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: active ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: activeFg,
                    ),
                  )
                : Icon(
                    active ? activeIcon : icon,
                    size: 22,
                    color: fg,
                  ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDocsView extends StatelessWidget {
  const _EmptyDocsView({required this.onScan, required this.onImport});

  final VoidCallback onScan;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EmptyDocumentsIllustration(size: 168),
            const SizedBox(height: 18),
            Text(
              'Belum ada dokumen',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pindai dokumen atau KTP 2 sisi dengan deteksi 4 sudut otomatis, atau impor foto dari galeri. Semua diproses 100% offline.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.yellow,
                    foregroundColor: AppColors.charcoal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  onPressed: onScan,
                  icon: const Icon(Icons.document_scanner_rounded, size: 19),
                  label: const Text('Mulai Scan'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  onPressed: onImport,
                  icon: const Icon(Icons.photo_library_outlined, size: 19),
                  label: const Text('Impor'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySearchView extends StatelessWidget {
  const _EmptySearchView({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EmptySearchIllustration(size: 126),
            const SizedBox(height: 14),
            Text(
              'Tidak ada dokumen yang cocok',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Coba kata kunci lain atau bersihkan filter label.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reset filter'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentsGrid extends StatelessWidget {
  const _DocumentsGrid({
    required this.docs,
    required this.selectedIds,
    required this.onOpen,
    required this.onLongPress,
    required this.onMore,
  });

  final List<ScanDocument> docs;
  final Set<String> selectedIds;
  final ValueChanged<ScanDocument> onOpen;
  final ValueChanged<ScanDocument> onLongPress;
  final ValueChanged<ScanDocument> onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selecting = selectedIds.isNotEmpty;
    final selectRing = isDark ? AppColors.yellow : AppColors.charcoal;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final isSelected = selectedIds.contains(doc.id);
        return Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isSelected ? selectRing : scheme.outline,
              width: isSelected ? 2.2 : 1,
            ),
          ),
          child: InkWell(
            onTap: () => onOpen(doc),
            onLongPress: () => onLongPress(doc),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _ThumbPreview(
                        key: ValueKey('${doc.coverThumbPath}_${doc.updatedAt}'),
                        path: doc.coverThumbPath,
                        cacheWidth: 420,
                      ),
                      if (doc.tag.isNotEmpty)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.yellow,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              doc.tag,
                              style: const TextStyle(
                                color: AppColors.charcoal,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      if (selecting)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: AppColors.charcoal,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              isSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked,
                              size: 20,
                              color: isSelected
                                  ? AppColors.yellow
                                  : AppColors.bgLight,
                            ),
                          ),
                        ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.charcoal.withValues(alpha: 0.84),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: AppColors.yellow,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${doc.pageCount} hal',
                                style: const TextStyle(
                                  color: AppColors.bgLight,
                                  fontSize: 10.5,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doc.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatDateShort(doc.updatedAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!selecting)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.more_vert_rounded,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                          onPressed: () => onMore(doc),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DocumentsList extends StatelessWidget {
  const _DocumentsList({
    required this.docs,
    required this.selectedIds,
    required this.onOpen,
    required this.onLongPress,
    required this.onMore,
  });

  final List<ScanDocument> docs;
  final Set<String> selectedIds;
  final ValueChanged<ScanDocument> onOpen;
  final ValueChanged<ScanDocument> onLongPress;
  final ValueChanged<ScanDocument> onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selecting = selectedIds.isNotEmpty;
    final selectRing = isDark ? AppColors.yellow : AppColors.charcoal;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      itemCount: docs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final doc = docs[index];
        final isSelected = selectedIds.contains(doc.id);
        return Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isSelected ? selectRing : scheme.outline,
              width: isSelected ? 2.2 : 1,
            ),
          ),
          child: InkWell(
            onTap: () => onOpen(doc),
            onLongPress: () => onLongPress(doc),
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Row(
                children: [
                  if (selecting) ...[
                    Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      color: isSelected ? selectRing : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                  ],
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 56,
                      height: 74,
                      child: _ThumbPreview(
                        key: ValueKey('${doc.coverThumbPath}_${doc.updatedAt}'),
                        path: doc.coverThumbPath,
                        cacheWidth: 200,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${doc.pageCount} halaman · ${formatDateShort(doc.updatedAt)}',
                          style: textTheme.bodySmall,
                        ),
                        if (doc.tag.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.yellow,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              doc.tag,
                              style: const TextStyle(
                                color: AppColors.charcoal,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!selecting)
                    IconButton(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                      onPressed: () => onMore(doc),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ThumbPreview extends StatelessWidget {
  const _ThumbPreview({
    super.key,
    required this.path,
    required this.cacheWidth,
  });

  final String? path;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (path != null && File(path!).existsSync()) {
      return Image.file(
        File(path!),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorBuilder: (_, _, _) => _placeholder(scheme),
      );
    }
    return _placeholder(scheme);
  }

  Widget _placeholder(ColorScheme scheme) => Container(
    color: scheme.surfaceContainerHighest,
    child: Icon(
      Icons.description_outlined,
      color: scheme.onSurfaceVariant,
      size: 32,
    ),
  );
}
