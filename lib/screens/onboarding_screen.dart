import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/illustrations.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  static const _pages = [
    (
      tag: 'Deteksi 4 Sudut',
      title: 'Pindai dokumen\nsepresisi mesin',
      body:
          'Garis tepi 4 sudut otomatis mengunci kertas dan meluruskan perspektif meski difoto dari sudut miring.',
    ),
    (
      tag: 'Bersih & Tajam',
      title: 'Hapus bayangan\ndalam sekejap',
      body:
          'Atur filter Warna, Abu-abu, atau Hitam-Putih, lalu ekspor ke PDF/JPG/PNG maupun gabung, pisah, dan kompres PDF.',
    ),
    (
      tag: '100% Offline',
      title: 'Privat penuh\ndi perangkat Anda',
      body:
          'Tanpa akun, tanpa iklan, dan tanpa izin internet. Seluruh pemrosesan gambar & PDF berjalan lokal dengan Rust.',
    ),
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(appSettingsProvider.notifier).completeOnboarding();
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  Widget _buildIllustration(int index) => switch (index) {
    0 => const OnboardingScanIllustration(size: 220),
    1 => const OnboardingEnhanceIllustration(size: 220),
    _ => const OnboardingOfflineIllustration(size: 220),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.yellow,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top bar: logo mark + skip pill.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  const JScanLogoMark(size: 34),
                  const SizedBox(width: 10),
                  Text(
                    appName,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.charcoal,
                    ),
                  ),
                  const Spacer(),
                  if (!isLast)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.charcoal,
                        backgroundColor: isDark
                            ? AppColors.surfaceVarDark
                            : AppColors.charcoal.withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      onPressed: _finish,
                      child: const Text(
                        'Lewati',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),

            // Upper illustrative carousel stage.
            Expanded(
              flex: 5,
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) => Center(
                  child: _buildIllustration(index),
                ),
              ),
            ),

            // Lower rounded editorial sheet (echoing referensi-ui-ux.jpg).
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? AppColors.borderDark
                        : AppColors.charcoal.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Warm yellow tag pill.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.yellowContainerDark
                              : AppColors.yellowSoftLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _pages[_page].tag,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppColors.yellow
                                : AppColors.charcoal,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Column(
                          key: ValueKey(_page),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _pages[_page].title,
                              style: textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _pages[_page].body,
                              style: textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      Row(
                        children: [
                          // Pill progress indicators.
                          Row(
                            children: List.generate(_pages.length, (i) {
                              final active = i == _page;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                margin: const EdgeInsets.only(right: 6),
                                width: active ? 26 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: active
                                      ? (isDark
                                            ? AppColors.yellow
                                            : AppColors.charcoal)
                                      : scheme.outline,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              );
                            }),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 14,
                              ),
                            ),
                            onPressed: _next,
                            icon: Icon(
                              isLast
                                  ? Icons.document_scanner_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 19,
                            ),
                            label: Text(isLast ? 'Mulai Sekarang' : 'Lanjut'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
