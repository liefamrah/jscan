import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../src/rust/api.dart';
import '../state/providers.dart';
import '../widgets/illustrations.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int? _docsBytes;
  int? _cacheBytes;
  int _docCount = 0;
  int _pageCount = 0;
  bool _clearingCache = false;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
  }

  Future<void> _loadStorageInfo() async {
    try {
      final usage = await ref.read(fileStoreProvider).computeStorageUsage();
      final docs = await ref.read(repositoryProvider).listDocuments();
      var pages = 0;
      for (final d in docs) {
        pages += d.pageCount;
      }
      if (!mounted) return;
      setState(() {
        _docsBytes = usage.docsBytes;
        _cacheBytes = usage.cacheBytes;
        _docCount = docs.length;
        _pageCount = pages;
      });
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    if (_clearingCache) return;
    setState(() => _clearingCache = true);
    try {
      final freed = await ref
          .read(fileStoreProvider)
          .clearTempCacheAndReportBytes();
      await _loadStorageInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              freed > 0
                  ? 'Cache dibersihkan (${formatBytes(freed)} dibebaskan).'
                  : 'Cache sementara sudah bersih.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  Future<void> _openUrlWithFallback(String url, String label) async {
    final opened = await openExternalUrl(url);
    if (!opened && mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Browser tidak tersedia. Tautan $label disalin.'),
        ),
      );
    }
  }

  Future<void> _copyLink(String url, String label) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tautan $label disalin ke papan klip.')),
      );
    }
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Ikuti sistem',
    ThemeMode.light => 'Terang',
    ThemeMode.dark => 'Gelap',
  };

  Future<void> _pickThemeMode(ThemeMode current) async {
    final chosen = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _OptionSheet<ThemeMode>(
        title: 'Tema aplikasi',
        current: current,
        options: [
          (ThemeMode.system, 'Ikuti sistem', 'Sesuaikan dengan pengaturan perangkat'),
          (ThemeMode.light, 'Terang', 'Kertas hangat & kontras tinta tajam'),
          (ThemeMode.dark, 'Gelap', 'Arang hangat dengan aksen kuning lembut'),
        ],
      ),
    );
    if (chosen != null) {
      ref.read(appSettingsProvider.notifier).setThemeMode(chosen);
    }
  }

  Future<void> _pickDefaultFilter(FilterKind current) async {
    final chosen = await showModalBottomSheet<FilterKind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _OptionSheet<FilterKind>(
        title: 'Filter pemindaian bawaan',
        current: current,
        options: [
          (FilterKind.color, 'Warna', 'Hapus bayangan & pertajam teks berwarna'),
          (FilterKind.original, 'Asli', 'Pertahankan warna foto apa adanya'),
          (FilterKind.grayscale, 'Abu-abu', 'Bersih & kontras tinggi untuk cetak'),
          (FilterKind.documentBw, 'Hitam-Putih', 'Teks biner tajam seperti fotokopi'),
        ],
      ),
    );
    if (chosen != null) {
      ref.read(appSettingsProvider.notifier).setDefaultFilter(chosen);
    }
  }

  Future<void> _pickExportQuality(ExportQuality current) async {
    final chosen = await showModalBottomSheet<ExportQuality>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _OptionSheet<ExportQuality>(
        title: 'Kualitas ekspor bawaan',
        current: current,
        options: ExportQuality.values
            .map(
              (q) => (
                q,
                q.label,
                'Maks. ${q.maxLongSide} px · Kompresi ${q.jpegQuality}%',
              ),
            )
            .toList(),
      ),
    );
    if (chosen != null) {
      ref.read(appSettingsProvider.notifier).setDefaultExportQuality(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final storageSubtitle = _docsBytes == null
        ? 'Menghitung ukuran penyimpanan...'
        : '$_docCount dokumen · $_pageCount halaman (${formatBytes(_docsBytes!)})';

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        // 1. Tampilan
        const _SectionHeader(title: 'TAMPILAN'),
        _SettingsGroup(
          children: [
            _SettingsNavTile(
              icon: Icons.palette_outlined,
              title: 'Tema aplikasi',
              subtitle: _themeLabel(settings.themeMode),
              onTap: () => _pickThemeMode(settings.themeMode),
            ),
            const _GroupDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  const _TileIconBox(icon: Icons.grid_view_outlined),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tata letak dokumen',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tampilan awal di tab Dokumen',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(value: true, label: Text('Grid')),
                      ButtonSegment(value: false, label: Text('Daftar')),
                    ],
                    selected: {settings.defaultGridView},
                    onSelectionChanged: (s) =>
                        notifier.setDefaultGridView(s.first),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),

        // 2. Pemindaian & Ekspor
        const _SectionHeader(title: 'PEMINDAIAN & EKSPOR'),
        _SettingsGroup(
          children: [
            _SettingsNavTile(
              icon: Icons.auto_fix_high_outlined,
              title: 'Filter bawaan',
              subtitle: filterLabel(settings.defaultFilter),
              onTap: () => _pickDefaultFilter(settings.defaultFilter),
            ),
            const _GroupDivider(),
            _SettingsSwitchTile(
              icon: Icons.center_focus_strong_outlined,
              title: 'Auto-capture otomatis',
              subtitle: 'Ambil foto otomatis saat 4 sudut dokumen stabil',
              value: settings.autoCaptureDefault,
              onChanged: notifier.setAutoCaptureDefault,
            ),
            const _GroupDivider(),
            _SettingsSwitchTile(
              icon: Icons.grid_on_rounded,
              title: 'Grid 3×3 di kamera',
              subtitle: 'Tampilkan garis bantu komposisi saat membuka kamera',
              value: settings.showGridDefault,
              onChanged: notifier.setShowGridDefault,
            ),
            const _GroupDivider(),
            _SettingsNavTile(
              icon: Icons.high_quality_outlined,
              title: 'Kualitas ekspor bawaan',
              subtitle:
                  '${settings.defaultExportQuality.label} (maks. ${settings.defaultExportQuality.maxLongSide} px)',
              onTap: () => _pickExportQuality(settings.defaultExportQuality),
            ),
            const _GroupDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  const _TileIconBox(icon: Icons.picture_as_pdf_outlined),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ukuran halaman PDF',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Bawaan saat ekspor & konversi',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<PdfFit>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(value: PdfFit.a4, label: Text('A4')),
                      ButtonSegment(value: PdfFit.original, label: Text('Asli')),
                    ],
                    selected: {settings.defaultPdfFit},
                    onSelectionChanged: (s) =>
                        notifier.setDefaultPdfFit(s.first),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),

        // 3. Penyimpanan & Privasi
        const _SectionHeader(title: 'PENYIMPANAN & PRIVASI'),
        _SettingsGroup(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  const _TileIconBox(icon: Icons.folder_outlined),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ruang penyimpanan dokumen',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          storageSubtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const _GroupDivider(),
            InkWell(
              onTap: _clearingCache ? null : _clearCache,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    const _TileIconBox(icon: Icons.cleaning_services_outlined),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Bersihkan cache sementara',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _cacheBytes == null
                                ? 'File sisa ekspor & konversi'
                                : 'Cache saat ini: ${formatBytes(_cacheBytes!)}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_clearingCache)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.yellowContainerDark
                              : AppColors.yellowSoftLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Bersihkan',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.yellow
                                : AppColors.charcoal,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const _GroupDivider(),
            _SettingsNavTile(
              icon: Icons.verified_user_outlined,
              title: 'Izin kamera perangkat',
              subtitle: 'Kelola izin aplikasi di pengaturan Android',
              onTap: openAppSettings,
            ),
          ],
        ),

        const SizedBox(height: 22),

        // 4. Card Gabungan: Tentang & Dukungan (Paling Bawah — Dark Charcoal Signature Card)
        const _SectionHeader(title: 'TENTANG & DUKUNGAN'),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.charcoal,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? AppColors.borderDark : Colors.transparent,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // About Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const JScanLogoMark(size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                appName,
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.bgLight,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.yellow,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'v$appVersion',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.charcoal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _DarkInfoPill(
                                icon: Icons.offline_bolt_outlined,
                                label: '100% Offline',
                              ),
                              _DarkInfoPill(
                                icon: Icons.shield_outlined,
                                label: 'Tanpa izin internet',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Seluruh deteksi 4 sudut, koreksi perspektif, dan penyusunan PDF diproses lokal di perangkat dengan mesin native Rust.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.42,
                              color: AppColors.bgLight.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.10),
              ),

              // Developer link: github.com/liefamrah
              InkWell(
                onTap: () => _openUrlWithFallback(developerUrl, developerLabel),
                onLongPress: () => _copyLink(developerUrl, developerLabel),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.code_rounded,
                          size: 19,
                          color: AppColors.yellow,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pengembang',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.bgLight,
                              ),
                            ),
                            SizedBox(height: 1),
                            Text(
                              developerLabel,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.yellow,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: AppColors.bgLight.withValues(alpha: 0.65),
                      ),
                    ],
                  ),
                ),
              ),

              Divider(
                height: 1,
                indent: 68,
                color: Colors.white.withValues(alpha: 0.08),
              ),

              // Open-source licenses
              InkWell(
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: appName,
                  applicationVersion: 'v$appVersion',
                  applicationIcon: const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: JScanLogoMark(size: 48),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.article_outlined,
                          size: 19,
                          color: AppColors.bgLight.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Lisensi pustaka open-source',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.bgLight,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.bgLight.withValues(alpha: 0.65),
                      ),
                    ],
                  ),
                ),
              ),

              // Embedded Saweria Donation Panel inside the same bottom card
              Container(
                margin: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.charcoalElevated,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.yellow.withValues(alpha: 0.30),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const SaweriaCoffeeIllustration(size: 52),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Dukung pengembangan JScan',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.bgLight,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'JScan gratis, bebas iklan, dan 100% offline. Traktir kopi lewat Saweria jika aplikasi ini membantu.',
                                style: TextStyle(
                                  fontSize: 12.2,
                                  height: 1.38,
                                  color: AppColors.bgLight.withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.yellow,
                              foregroundColor: AppColors.charcoal,
                              minimumSize: const Size(0, 44),
                            ),
                            onPressed: () =>
                                _openUrlWithFallback(donationUrl, donationLabel),
                            icon: const Icon(
                              Icons.favorite_rounded,
                              size: 17,
                            ),
                            label: const Text('Dukung di $donationLabel'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Salin tautan Saweria',
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(44, 44),
                              padding: EdgeInsets.zero,
                              side: BorderSide(
                                color: AppColors.yellow.withValues(alpha: 0.45),
                              ),
                              foregroundColor: AppColors.yellow,
                            ),
                            onPressed: () =>
                                _copyLink(donationUrl, donationLabel),
                            child: const Icon(Icons.copy_rounded, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(title, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 66,
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.7),
    );
  }
}

class _TileIconBox extends StatelessWidget {
  const _TileIconBox({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 19, color: scheme.onSurface),
    );
  }
}

class _SettingsNavTile extends StatelessWidget {
  const _SettingsNavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
        child: Row(
          children: [
            _TileIconBox(icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            _TileIconBox(icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _DarkInfoPill extends StatelessWidget {
  const _DarkInfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.yellow),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.bgLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.current,
    required this.options,
  });

  final String title;
  final T current;
  final List<(T, String, String)> options;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ...options.map((opt) {
              final selected = opt.$1 == current;
              final bg = selected
                  ? (isDark ? AppColors.yellow : AppColors.yellow)
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.65);
              final fg = selected ? AppColors.charcoal : scheme.onSurface;
              final sub = selected
                  ? AppColors.charcoal.withValues(alpha: 0.78)
                  : scheme.onSurfaceVariant;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.pop(context, opt.$1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  opt.$2,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: fg,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  opt.$3,
                                  style: TextStyle(fontSize: 12, color: sub),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.charcoal,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
