import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import '../src/rust/api.dart';
import '../src/rust/error.dart';
import 'constants.dart';

final _rng = Random();
const _systemChannel = MethodChannel('com.jscan.app/system');

String generateId() {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = _rng.nextInt(0xFFFFFF).toRadixString(36).padLeft(5, '0');
  return '${ts}_$rand';
}

String defaultDocumentName([DateTime? now]) {
  final d = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${appName}_${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';
}

String formatDateShort(int epochMs) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year} · ${two(d.hour)}:${two(d.minute)}';
}

String sanitizeFileName(String raw, {String fallback = 'JScan_Dokumen'}) {
  final cleaned = raw
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^\.+|\.+$'), '');
  if (cleaned.isEmpty) return fallback;
  return cleaned.length > 80 ? cleaned.substring(0, 80).trim() : cleaned;
}

String normalizeCategoryName(String raw) =>
    raw.replaceAll(RegExp(r'\s+'), ' ').trim();

bool isDefaultCategory(String name) {
  final lower = normalizeCategoryName(name).toLowerCase();
  return documentTags.any((t) => t.toLowerCase() == lower);
}

String? validateCategoryName(
  String raw,
  Iterable<String> existingCategories, {
  String? ignoreCurrent,
}) {
  final normalized = normalizeCategoryName(raw);
  if (normalized.isEmpty) {
    return 'Nama kelompok tidak boleh kosong.';
  }
  if (normalized.length > maxCategoryNameLength) {
    return 'Maksimal $maxCategoryNameLength karakter.';
  }
  final lower = normalized.toLowerCase();
  if (lower == 'semua' ||
      lower == 'tanpa kelompok' ||
      lower == 'tanpa label') {
    return 'Nama kelompok ini sudah digunakan sistem.';
  }
  final ignoredLower = ignoreCurrent == null
      ? null
      : normalizeCategoryName(ignoreCurrent).toLowerCase();
  for (final existing in existingCategories) {
    final existingLower = normalizeCategoryName(existing).toLowerCase();
    if (existingLower == lower && existingLower != ignoredLower) {
      return 'Kelompok "$normalized" sudah ada.';
    }
  }
  return null;
}

List<String> mergeCategoryNames(
  Iterable<String> defaults,
  Iterable<String> custom, [
  Iterable<String> documentTags = const [],
]) {
  final seen = <String>{};
  final result = <String>[];
  void addAll(Iterable<String> items) {
    for (final item in items) {
      final normalized = normalizeCategoryName(item);
      if (normalized.isEmpty) continue;
      if (seen.add(normalized.toLowerCase())) {
        result.add(normalized);
      }
    }
  }

  addAll(defaults);
  addAll(custom);
  addAll(documentTags);
  return result;
}

String encodeQuadJson(Quad quad) {
  final list = quad.pts.map((p) => [p.$1, p.$2]).toList(growable: false);
  return jsonEncode(list);
}

Quad decodeQuadJson(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List && decoded.length == 4) {
      final pts = <(double, double)>[];
      for (final item in decoded) {
        if (item is List && item.length == 2) {
          final x = (item[0] as num).toDouble().clamp(0.0, 1.0);
          final y = (item[1] as num).toDouble().clamp(0.0, 1.0);
          pts.add((x, y));
        }
      }
      if (pts.length == 4) return Quad(pts: pts);
    }
  } catch (_) {}
  return fallbackInsetQuad;
}

String filterToDb(FilterKind kind) => kind.name;

FilterKind filterFromDb(String raw) {
  for (final k in FilterKind.values) {
    if (k.name == raw) return k;
  }
  return defaultScanFilter;
}

/// Parses human page ranges like "1-3, 5, 7-9" into 1-based inclusive [PageRange]s.
List<PageRange> parsePageRanges(String input, {int? maxPage}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Masukkan rentang halaman, contoh: 1-3, 5');
  }
  final parts = trimmed.split(',');
  final ranges = <PageRange>[];
  for (final part in parts) {
    final token = part.trim();
    if (token.isEmpty) continue;
    if (token.contains('-')) {
      final bounds = token.split('-');
      if (bounds.length != 2) {
        throw FormatException('Format rentang tidak valid: "$token"');
      }
      final start = int.tryParse(bounds[0].trim());
      final end = int.tryParse(bounds[1].trim());
      if (start == null || end == null || start < 1 || end < start) {
        throw FormatException('Rentang tidak valid: "$token"');
      }
      if (maxPage != null && end > maxPage) {
        throw FormatException('Halaman $end melebihi jumlah halaman ($maxPage)');
      }
      ranges.add(PageRange(start: start, end: end));
    } else {
      final page = int.tryParse(token);
      if (page == null || page < 1) {
        throw FormatException('Nomor halaman tidak valid: "$token"');
      }
      if (maxPage != null && page > maxPage) {
        throw FormatException('Halaman $page melebihi jumlah halaman ($maxPage)');
      }
      ranges.add(PageRange(start: page, end: page));
    }
  }
  if (ranges.isEmpty) {
    throw const FormatException('Tidak ada rentang halaman yang valid.');
  }
  return ranges;
}

String formatError(Object err) {
  if (err is ScanError) {
    return err.when(
      io: (msg) {
        final lower = msg.toLowerCase();
        if (lower.contains('space') || lower.contains('enospc')) {
          return 'Penyimpanan penuh. Kosongkan ruang lalu coba lagi.';
        }
        return 'Gagal membaca atau menulis file.';
      },
      image: (_) => 'Gambar rusak atau format tidak didukung.',
      invalidQuad: () => 'Koordinat sudut tidak valid.',
      pdf: (_) => 'File PDF rusak atau tidak didukung.',
      encryptedPdf: () => 'PDF terenkripsi/berkata sandi tidak dapat diproses.',
      zip: (_) => 'Gagal membuat arsip ZIP.',
      invalidArgument: (msg) => msg,
    );
  }
  if (err is FormatException) return err.message;
  final text = err.toString();
  if (text.toLowerCase().contains('no space left')) {
    return 'Penyimpanan penuh. Kosongkan ruang lalu coba lagi.';
  }
  return text.replaceFirst('Exception: ', '');
}

Future<void> openAppSettings() async {
  try {
    await _systemChannel.invokeMethod<void>('openAppSettings');
  } catch (_) {}
}

/// Opens an HTTPS URL in the system browser without requiring INTERNET permission.
Future<bool> openExternalUrl(String url) async {
  try {
    final ok = await _systemChannel.invokeMethod<bool>(
      'openExternalUrl',
      {'url': url},
    );
    return ok == true;
  } catch (_) {
    return false;
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

/// Converts a set of 1-based page numbers like `{1, 2, 3, 5, 7, 8}` into `"1-3, 5, 7-8"`.
String formatPageRangeList(Set<int> pages) {
  if (pages.isEmpty) return '';
  final sorted = pages.toList()..sort();
  final parts = <String>[];
  var start = sorted.first;
  var prev = sorted.first;
  for (var i = 1; i < sorted.length; i++) {
    final cur = sorted[i];
    if (cur == prev + 1) {
      prev = cur;
    } else {
      parts.add(start == prev ? '$start' : '$start-$prev');
      start = cur;
      prev = cur;
    }
  }
  parts.add(start == prev ? '$start' : '$start-$prev');
  return parts.join(', ');
}
