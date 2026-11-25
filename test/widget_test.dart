import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jscan/core/constants.dart';
import 'package:jscan/core/utils.dart';
import 'package:jscan/data/file_store.dart';
import 'package:jscan/data/settings_repository.dart';
import 'package:jscan/src/rust/api.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('parsePageRanges parses valid ranges and rejects invalid ones', () {
    final ranges = parsePageRanges('1-3, 5, 7-9', maxPage: 10);
    expect(ranges.length, 3);
    expect((ranges[0].start, ranges[0].end), (1, 3));
    expect((ranges[1].start, ranges[1].end), (5, 5));
    expect((ranges[2].start, ranges[2].end), (7, 9));

    expect(() => parsePageRanges('1-12', maxPage: 10), throwsFormatException);
    expect(() => parsePageRanges('5-2', maxPage: 10), throwsFormatException);
  });

  test('formatPageRangeList collapses contiguous pages cleanly', () {
    expect(formatPageRangeList({1, 2, 3, 5, 7, 8}), '1-3, 5, 7-8');
    expect(formatPageRangeList({4}), '4');
    expect(formatPageRangeList({}), '');
  });

  test('sanitizeFileName removes illegal characters', () {
    expect(sanitizeFileName('Faktur/2026:01*?.pdf'), 'Faktur_2026_01__.pdf');
    expect(sanitizeFileName('   ...  '), 'JScan_Dokumen');
  });

  test('formatBytes formats human-readable sizes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(2 * 1024 * 1024), '2.00 MB');
  });

  test('AppSettings serializes and deserializes with safe fallbacks', () {
    const custom = AppSettings(
      themeMode: ThemeMode.dark,
      defaultGridView: false,
      defaultFilter: FilterKind.documentBw,
      autoCaptureDefault: false,
      showGridDefault: true,
      defaultExportQuality: ExportQuality.high,
      defaultPdfFit: PdfFit.original,
      onboardingDone: true,
    );
    final restored = AppSettings.fromMap(custom.toMap());
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.defaultGridView, false);
    expect(restored.defaultFilter, FilterKind.documentBw);
    expect(restored.autoCaptureDefault, false);
    expect(restored.showGridDefault, true);
    expect(restored.defaultExportQuality, ExportQuality.high);
    expect(restored.defaultPdfFit, PdfFit.original);
    expect(restored.onboardingDone, true);

    final fallback = AppSettings.fromMap({'theme_mode': 'invalid', 'default_filter': 'nope'});
    expect(fallback.themeMode, ThemeMode.system);
    expect(fallback.defaultFilter, defaultScanFilter);
    expect(fallback.defaultGridView, true);
    expect(fallback.onboardingDone, false);
  });

  testWidgets('evictImagePaths clears ResizeImage cache entries for overwritten files', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
    final img = await recorder.endRecording().toImage(2, 2);

    final provider = ResizeImage(FileImage(File('dummy_page.jpg')), width: 1600);
    final key = await provider.obtainKey(ImageConfiguration.empty);
    final completer = OneFrameImageStreamCompleter(
      Future.value(ImageInfo(image: img)),
    );
    PaintingBinding.instance.imageCache.putIfAbsent(key, () => completer);
    expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);

    await FileStore().evictImagePaths(['dummy_page.jpg']);
    expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
  });
}
