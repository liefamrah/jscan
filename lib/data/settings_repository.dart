import 'package:material_ui/material_ui.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../src/rust/api.dart';
import 'db.dart';

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.defaultGridView = true,
    this.defaultFilter = defaultScanFilter,
    this.autoCaptureDefault = true,
    this.showGridDefault = false,
    this.defaultExportQuality = ExportQuality.medium,
    this.defaultPdfFit = PdfFit.a4,
    this.onboardingDone = false,
  });

  final ThemeMode themeMode;
  final bool defaultGridView;
  final FilterKind defaultFilter;
  final bool autoCaptureDefault;
  final bool showGridDefault;
  final ExportQuality defaultExportQuality;
  final PdfFit defaultPdfFit;
  final bool onboardingDone;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? defaultGridView,
    FilterKind? defaultFilter,
    bool? autoCaptureDefault,
    bool? showGridDefault,
    ExportQuality? defaultExportQuality,
    PdfFit? defaultPdfFit,
    bool? onboardingDone,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    defaultGridView: defaultGridView ?? this.defaultGridView,
    defaultFilter: defaultFilter ?? this.defaultFilter,
    autoCaptureDefault: autoCaptureDefault ?? this.autoCaptureDefault,
    showGridDefault: showGridDefault ?? this.showGridDefault,
    defaultExportQuality: defaultExportQuality ?? this.defaultExportQuality,
    defaultPdfFit: defaultPdfFit ?? this.defaultPdfFit,
    onboardingDone: onboardingDone ?? this.onboardingDone,
  );

  Map<String, String> toMap() => {
    'theme_mode': themeMode.name,
    'default_grid_view': defaultGridView ? '1' : '0',
    'default_filter': defaultFilter.name,
    'auto_capture_default': autoCaptureDefault ? '1' : '0',
    'show_grid_default': showGridDefault ? '1' : '0',
    'default_export_quality': defaultExportQuality.name,
    'default_pdf_fit': defaultPdfFit.name,
    'onboarding_done': onboardingDone ? '1' : '0',
  };

  factory AppSettings.fromMap(Map<String, String> map) {
    ThemeMode parseTheme(String? raw) => switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    FilterKind parseFilter(String? raw) {
      for (final f in FilterKind.values) {
        if (f.name == raw) return f;
      }
      return defaultScanFilter;
    }
    ExportQuality parseQuality(String? raw) {
      for (final q in ExportQuality.values) {
        if (q.name == raw) return q;
      }
      return ExportQuality.medium;
    }
    PdfFit parsePdfFit(String? raw) =>
        raw == PdfFit.original.name ? PdfFit.original : PdfFit.a4;

    return AppSettings(
      themeMode: parseTheme(map['theme_mode']),
      defaultGridView: (map['default_grid_view'] ?? '1') != '0',
      defaultFilter: parseFilter(map['default_filter']),
      autoCaptureDefault: (map['auto_capture_default'] ?? '1') != '0',
      showGridDefault: (map['show_grid_default'] ?? '0') == '1',
      defaultExportQuality: parseQuality(map['default_export_quality']),
      defaultPdfFit: parsePdfFit(map['default_pdf_fit']),
      onboardingDone: (map['onboarding_done'] ?? '0') == '1',
    );
  }
}

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<AppSettings> load() async {
    try {
      final db = await _db.database;
      final rows = await db.query('settings');
      final map = <String, String>{
        for (final r in rows) r['key'] as String: r['value'] as String,
      };
      return AppSettings.fromMap(map);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    final db = await _db.database;
    final entries = settings.toMap();
    await db.transaction((txn) async {
      for (final e in entries.entries) {
        await txn.insert(
          'settings',
          {'key': e.key, 'value': e.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}
