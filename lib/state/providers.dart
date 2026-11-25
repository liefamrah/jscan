import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/constants.dart';
import '../data/db.dart';
import '../data/document_repository.dart';
import '../data/file_store.dart';
import '../data/models.dart';
import '../data/settings_repository.dart';
import '../src/rust/api.dart';

final fileStoreProvider = Provider<FileStore>((ref) => FileStore());

final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

final repositoryProvider = Provider<DocumentRepository>(
  (ref) => DocumentRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(fileStoreProvider),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider)),
);

/// Overridden in `main()` with persisted settings loaded before `runApp`.
final initialSettingsProvider = Provider<AppSettings>(
  (_) => const AppSettings(),
);

class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  void _commit(AppSettings next) {
    state = next;
    unawaited(ref.read(settingsRepositoryProvider).save(next));
  }

  void setThemeMode(ThemeMode mode) => _commit(state.copyWith(themeMode: mode));

  void setDefaultGridView(bool isGrid) =>
      _commit(state.copyWith(defaultGridView: isGrid));

  void toggleGridView() =>
      _commit(state.copyWith(defaultGridView: !state.defaultGridView));

  void setDefaultFilter(FilterKind filter) =>
      _commit(state.copyWith(defaultFilter: filter));

  void setAutoCaptureDefault(bool enabled) =>
      _commit(state.copyWith(autoCaptureDefault: enabled));

  void setShowGridDefault(bool enabled) =>
      _commit(state.copyWith(showGridDefault: enabled));

  void setDefaultExportQuality(ExportQuality quality) =>
      _commit(state.copyWith(defaultExportQuality: quality));

  void setDefaultPdfFit(PdfFit fit) =>
      _commit(state.copyWith(defaultPdfFit: fit));

  void completeOnboarding() => _commit(state.copyWith(onboardingDone: true));
}

final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);

class HomeSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

final homeSearchQueryProvider =
    NotifierProvider<HomeSearchQueryNotifier, String>(
      HomeSearchQueryNotifier.new,
    );

class CategoriesNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() =>
      ref.watch(repositoryProvider).listCategories();

  Future<void> refresh() async {
    final list = await ref.read(repositoryProvider).listCategories();
    if (!ref.mounted) return;
    state = AsyncData(list);
  }

  Future<String> create(String rawName) async {
    final created = await ref.read(repositoryProvider).createCategory(rawName);
    if (!ref.mounted) return created;
    await refresh();
    return created;
  }

  Future<String> rename(String oldName, String rawNewName) async {
    final renamed = await ref
        .read(repositoryProvider)
        .renameCategory(oldName, rawNewName);
    if (!ref.mounted) return renamed;
    if (ref.read(homeSelectedTagProvider).toLowerCase() ==
        oldName.toLowerCase()) {
      ref.read(homeSelectedTagProvider.notifier).select(renamed);
    }
    await refresh();
    if (!ref.mounted) return renamed;
    await ref.read(documentsProvider.notifier).refresh();
    return renamed;
  }

  Future<void> delete(String name) async {
    await ref.read(repositoryProvider).deleteCategory(name);
    if (!ref.mounted) return;
    if (ref.read(homeSelectedTagProvider).toLowerCase() == name.toLowerCase()) {
      ref.read(homeSelectedTagProvider.notifier).select('');
    }
    await refresh();
    if (!ref.mounted) return;
    await ref.read(documentsProvider.notifier).refresh();
  }
}

final categoriesProvider =
    AsyncNotifierProvider<CategoriesNotifier, List<String>>(
      CategoriesNotifier.new,
    );

class HomeSelectedTagNotifier extends Notifier<String> {
  @override
  String build() => '';

  void select(String tag) => state = tag;
}

final homeSelectedTagProvider =
    NotifierProvider<HomeSelectedTagNotifier, String>(
      HomeSelectedTagNotifier.new,
    );

class HomeSortNotifier extends Notifier<DocSort> {
  @override
  DocSort build() => DocSort.newest;

  void select(DocSort sort) => state = sort;
}

final homeSortProvider = NotifierProvider<HomeSortNotifier, DocSort>(
  HomeSortNotifier.new,
);

class DocumentsNotifier extends AsyncNotifier<List<ScanDocument>> {
  @override
  Future<List<ScanDocument>> build() {
    final query = ref.watch(homeSearchQueryProvider);
    final tag = ref.watch(homeSelectedTagProvider);
    final sort = ref.watch(homeSortProvider);
    return ref
        .watch(repositoryProvider)
        .listDocuments(query: query, tag: tag, sort: sort);
  }

  Future<void> refresh() async {
    final query = ref.read(homeSearchQueryProvider);
    final tag = ref.read(homeSelectedTagProvider);
    final sort = ref.read(homeSortProvider);
    state = AsyncData(
      await ref
          .read(repositoryProvider)
          .listDocuments(query: query, tag: tag, sort: sort),
    );
  }

  Future<void> rename(String docId, String newName) async {
    await ref.read(repositoryProvider).renameDocument(docId, newName);
    await refresh();
  }

  Future<void> setTag(String docId, String tag) async {
    await ref.read(repositoryProvider).setDocumentTag(docId, tag);
    await ref.read(categoriesProvider.notifier).refresh();
    await refresh();
  }

  Future<void> setTagMany(Iterable<String> docIds, String tag) async {
    await ref.read(repositoryProvider).setDocumentsTag(docIds, tag);
    await ref.read(categoriesProvider.notifier).refresh();
    await refresh();
  }

  Future<void> delete(String docId) async {
    await ref.read(repositoryProvider).deleteDocument(docId);
    await refresh();
  }

  Future<void> deleteMany(Iterable<String> docIds) async {
    await ref.read(repositoryProvider).deleteDocuments(docIds);
    await refresh();
  }

  Future<ScanDocument> mergeDocs(List<String> docIds) async {
    final merged = await ref.read(repositoryProvider).mergeDocuments(docIds);
    await refresh();
    return merged;
  }
}

final documentsProvider =
    AsyncNotifierProvider<DocumentsNotifier, List<ScanDocument>>(
      DocumentsNotifier.new,
    );

final documentDetailProvider = FutureProvider.family<ScanDocument?, String>((
  ref,
  docId,
) {
  return ref.watch(repositoryProvider).getDocument(docId);
});

final documentPagesProvider = FutureProvider.family<List<ScanPage>, String>((
  ref,
  docId,
) {
  return ref.watch(repositoryProvider).getPages(docId);
});
