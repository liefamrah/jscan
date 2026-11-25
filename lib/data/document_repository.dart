import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import '../src/rust/api.dart';
import 'db.dart';
import 'file_store.dart';
import 'models.dart';

class DocumentRepository {
  DocumentRepository(this._db, this._files);

  final AppDatabase _db;
  final FileStore _files;

  Future<List<ScanDocument>> listDocuments({
    String query = '',
    String tag = '',
    DocSort sort = DocSort.newest,
  }) async {
    final db = await _db.database;
    final whereClauses = <String>[];
    final args = <Object>[];

    final trimmedQuery = query.trim();
    if (trimmedQuery.isNotEmpty) {
      whereClauses.add('LOWER(d.name) LIKE ?');
      args.add('%${trimmedQuery.toLowerCase()}%');
    }
    if (tag.isNotEmpty) {
      whereClauses.add('d.tag = ? COLLATE NOCASE');
      args.add(tag);
    }

    final whereSql =
        whereClauses.isEmpty ? '' : 'WHERE ${whereClauses.join(' AND ')}';
    final orderSql = switch (sort) {
      DocSort.newest => 'd.updated_at DESC',
      DocSort.oldest => 'd.updated_at ASC',
      DocSort.nameAsc => 'LOWER(d.name) ASC',
    };

    final rows = await db.rawQuery('''
      SELECT d.id, d.name, d.created_at, d.updated_at, d.page_count, d.tag,
        (SELECT p.thumb_path FROM pages p WHERE p.doc_id = d.id ORDER BY p.idx ASC LIMIT 1) AS cover_thumb
      FROM documents d
      $whereSql
      ORDER BY $orderSql
    ''', args);

    return rows
        .map(
          (r) => ScanDocument(
            id: r['id'] as String,
            name: r['name'] as String,
            createdAt: r['created_at'] as int,
            updatedAt: r['updated_at'] as int,
            pageCount: r['page_count'] as int,
            tag: (r['tag'] as String?) ?? '',
            coverThumbPath: r['cover_thumb'] as String?,
          ),
        )
        .toList();
  }

  Future<ScanDocument?> getDocument(String docId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT d.id, d.name, d.created_at, d.updated_at, d.page_count, d.tag,
        (SELECT p.thumb_path FROM pages p WHERE p.doc_id = d.id ORDER BY p.idx ASC LIMIT 1) AS cover_thumb
      FROM documents d
      WHERE d.id = ?
      ''',
      [docId],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return ScanDocument(
      id: r['id'] as String,
      name: r['name'] as String,
      createdAt: r['created_at'] as int,
      updatedAt: r['updated_at'] as int,
      pageCount: r['page_count'] as int,
      tag: (r['tag'] as String?) ?? '',
      coverThumbPath: r['cover_thumb'] as String?,
    );
  }

  Future<List<ScanPage>> getPages(String docId) async {
    final db = await _db.database;
    final rows = await db.query(
      'pages',
      where: 'doc_id = ?',
      whereArgs: [docId],
      orderBy: 'idx ASC',
    );
    return rows
        .map(
          (r) => ScanPage(
            id: r['id'] as String,
            docId: r['doc_id'] as String,
            idx: r['idx'] as int,
            origPath: r['orig_path'] as String,
            outPath: r['out_path'] as String,
            thumbPath: r['thumb_path'] as String,
            corners: decodeQuadJson(r['corners_json'] as String),
            filter: filterFromDb(r['filter'] as String),
            rotation: r['rotation'] as int,
            brightness: ((r['brightness'] as num?) ?? 0.0).toDouble(),
            contrast: ((r['contrast'] as num?) ?? 0.0).toDouble(),
          ),
        )
        .toList();
  }

  Future<ScanDocument> createDocument({String? name, String tag = ''}) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = generateId();
    final docName = sanitizeFileName(name ?? defaultDocumentName());
    await _files.ensureDocDir(id);
    await db.insert('documents', {
      'id': id,
      'name': docName,
      'created_at': now,
      'updated_at': now,
      'page_count': 0,
      'tag': tag,
    });
    return ScanDocument(
      id: id,
      name: docName,
      createdAt: now,
      updatedAt: now,
      pageCount: 0,
      tag: tag,
    );
  }

  Future<void> renameDocument(String docId, String newName) async {
    final db = await _db.database;
    final clean = sanitizeFileName(newName);
    await db.update(
      'documents',
      {
        'name': clean,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [docId],
    );
  }

  Future<List<String>> listCategories() async {
    final db = await _db.database;
    final customRows = await db.query(
      'categories',
      columns: ['name'],
      orderBy: 'created_at ASC',
    );
    final docTagRows = await db.rawQuery(
      "SELECT DISTINCT tag FROM documents WHERE tag != '' ORDER BY tag COLLATE NOCASE ASC",
    );
    return mergeCategoryNames(
      documentTags,
      customRows.map((r) => r['name'] as String),
      docTagRows.map((r) => r['tag'] as String),
    );
  }

  Future<String> createCategory(String rawName) async {
    final existing = await listCategories();
    final error = validateCategoryName(rawName, existing);
    if (error != null) throw FormatException(error);

    final name = normalizeCategoryName(rawName);
    final db = await _db.database;
    await db.insert('categories', {
      'name': name,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return name;
  }

  Future<String> renameCategory(String oldName, String rawNewName) async {
    final cleanOld = normalizeCategoryName(oldName);
    if (isDefaultCategory(cleanOld)) {
      throw const FormatException('Kelompok bawaan tidak dapat diubah namanya.');
    }
    final existing = await listCategories();
    final error = validateCategoryName(
      rawNewName,
      existing,
      ignoreCurrent: cleanOld,
    );
    if (error != null) throw FormatException(error);

    final newName = normalizeCategoryName(rawNewName);
    if (newName == cleanOld) return newName;

    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final updated = await txn.update(
        'categories',
        {'name': newName},
        where: 'name = ? COLLATE NOCASE',
        whereArgs: [cleanOld],
      );
      if (updated == 0) {
        await txn.insert('categories', {'name': newName, 'created_at': now});
      }
      await txn.update(
        'documents',
        {'tag': newName, 'updated_at': now},
        where: 'tag = ? COLLATE NOCASE',
        whereArgs: [cleanOld],
      );
    });
    return newName;
  }

  Future<void> deleteCategory(String name) async {
    final clean = normalizeCategoryName(name);
    if (isDefaultCategory(clean)) {
      throw const FormatException('Kelompok bawaan tidak dapat dihapus.');
    }
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete(
        'categories',
        where: 'name = ? COLLATE NOCASE',
        whereArgs: [clean],
      );
      await txn.update(
        'documents',
        {'tag': '', 'updated_at': now},
        where: 'tag = ? COLLATE NOCASE',
        whereArgs: [clean],
      );
    });
  }

  Future<void> setDocumentTag(String docId, String tag) async {
    await setDocumentsTag([docId], tag);
  }

  Future<void> setDocumentsTag(Iterable<String> docIds, String tag) async {
    final ids = docIds.toList();
    if (ids.isEmpty) return;
    final cleanTag = normalizeCategoryName(tag);
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      if (cleanTag.isNotEmpty && !isDefaultCategory(cleanTag)) {
        await txn.insert(
          'categories',
          {'name': cleanTag, 'created_at': now},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final id in ids) {
        await txn.update(
          'documents',
          {'tag': cleanTag, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  Future<void> deleteDocument(String docId) async {
    final db = await _db.database;
    await db.delete('documents', where: 'id = ?', whereArgs: [docId]);
    await _files.deleteDocDir(docId);
  }

  Future<void> deleteDocuments(Iterable<String> docIds) async {
    for (final id in docIds) {
      await deleteDocument(id);
    }
  }

  /// Combines pages from multiple scanned documents into one new document.
  Future<ScanDocument> mergeDocuments(
    List<String> docIds, {
    String? name,
  }) async {
    final mergedDoc = await createDocument(
      name: name ?? '${defaultDocumentName()}_gabung',
    );
    try {
      final db = await _db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      var nextIdx = 0;

      for (final srcDocId in docIds) {
        final srcPages = await getPages(srcDocId);
        for (final srcPage in srcPages) {
          final pageId = generateId();
          final dstPaths = await _files.allocatePagePaths(mergedDoc.id, pageId);
          await File(srcPage.origPath).copy(dstPaths.origPath);
          await File(srcPage.outPath).copy(dstPaths.outPath);
          await File(srcPage.thumbPath).copy(dstPaths.thumbPath);

          await db.insert('pages', {
            'id': pageId,
            'doc_id': mergedDoc.id,
            'idx': nextIdx++,
            'orig_path': dstPaths.origPath,
            'out_path': dstPaths.outPath,
            'thumb_path': dstPaths.thumbPath,
            'corners_json': encodeQuadJson(srcPage.corners),
            'filter': filterToDb(srcPage.filter),
            'rotation': srcPage.rotation,
            'brightness': srcPage.brightness,
            'contrast': srcPage.contrast,
          });
        }
      }

      if (nextIdx == 0) {
        await deleteDocument(mergedDoc.id);
        throw const FormatException('Dokumen terpilih tidak memiliki halaman.');
      }

      await db.update(
        'documents',
        {'page_count': nextIdx, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [mergedDoc.id],
      );
      return (await getDocument(mergedDoc.id)) ?? mergedDoc;
    } catch (_) {
      await deleteDocument(mergedDoc.id);
      rethrow;
    }
  }

  /// Warps front & back ID card captures and composes them onto one A4 sheet.
  Future<ScanDocument> createIdCardDocument({
    required String frontSourcePath,
    required String backSourcePath,
    bool deleteSourcesAfter = true,
  }) async {
    final workDir = await _files.createTempWorkDir('idcard');
    try {
      final frontQuad = await detectCornersFromFile(path: frontSourcePath);
      final backQuad = await detectCornersFromFile(path: backSourcePath);

      final frontWarped = p.join(workDir.path, 'front.jpg');
      final backWarped = p.join(workDir.path, 'back.jpg');
      await processPage(
        src: frontSourcePath,
        dst: frontWarped,
        quad: frontQuad,
        filter: FilterKind.color,
        rotationDeg: 0,
        maxLongSide: 1400,
        jpegQuality: 90,
        brightness: 0.0,
        contrast: 0.0,
      );
      await processPage(
        src: backSourcePath,
        dst: backWarped,
        quad: backQuad,
        filter: FilterKind.color,
        rotationDeg: 0,
        maxLongSide: 1400,
        jpegQuality: 90,
        brightness: 0.0,
        contrast: 0.0,
      );

      final composedPath = p.join(workDir.path, 'composed_a4.jpg');
      await composeIdCard(
        frontSrc: frontWarped,
        backSrc: backWarped,
        dst: composedPath,
        maxLongSide: workingMaxLongSide,
        jpegQuality: 90,
      );

      final doc = await createDocument(
        name: 'KTP_${defaultDocumentName()}',
        tag: 'Identitas',
      );
      await addPageFromSource(
        docId: doc.id,
        sourcePath: composedPath,
        quad: fullFrameQuad,
        filter: FilterKind.original,
      );
      if (deleteSourcesAfter) {
        await _files.safeDeleteFile(frontSourcePath);
        await _files.safeDeleteFile(backSourcePath);
      }
      return (await getDocument(doc.id)) ?? doc;
    } finally {
      try {
        await workDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Stores the original photo inside `docs/<docId>/`, runs perspective warp + filter
  /// + thumbnail generation in Rust, and records the page in SQLite.
  Future<ScanPage> addPageFromSource({
    required String docId,
    required String sourcePath,
    Quad? quad,
    FilterKind filter = defaultScanFilter,
    int rotation = 0,
    double brightness = 0.0,
    double contrast = 0.0,
    bool deleteSourceAfterCopy = false,
  }) async {
    final pageId = generateId();
    final paths = await _files.allocatePagePaths(docId, pageId);

    try {
      final lower = sourcePath.toLowerCase();
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
        await File(sourcePath).copy(paths.origPath);
      } else {
        await exportImage(
          src: sourcePath,
          dst: paths.origPath,
          format: ExportImageFormat.jpeg,
          maxLongSide: 4096,
          jpegQuality: 90,
        );
      }

      if (deleteSourceAfterCopy) {
        await _files.safeDeleteFile(sourcePath);
      }

      final resolvedQuad =
          quad ?? await detectCornersFromFile(path: paths.origPath);
      await processPage(
        src: paths.origPath,
        dst: paths.outPath,
        quad: resolvedQuad,
        filter: filter,
        rotationDeg: rotation,
        maxLongSide: workingMaxLongSide,
        jpegQuality: workingJpegQuality,
        brightness: brightness,
        contrast: contrast,
      );
      await makeThumbnail(
        src: paths.outPath,
        dst: paths.thumbPath,
        maxSide: thumbnailMaxSide,
      );

      final db = await _db.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      late final int nextIdx;
      await db.transaction((txn) async {
        final res = await txn.rawQuery(
          'SELECT COALESCE(MAX(idx), -1) AS max_idx FROM pages WHERE doc_id = ?',
          [docId],
        );
        nextIdx = ((res.first['max_idx'] as int?) ?? -1) + 1;
        await txn.insert('pages', {
          'id': pageId,
          'doc_id': docId,
          'idx': nextIdx,
          'orig_path': paths.origPath,
          'out_path': paths.outPath,
          'thumb_path': paths.thumbPath,
          'corners_json': encodeQuadJson(resolvedQuad),
          'filter': filterToDb(filter),
          'rotation': rotation % 360,
          'brightness': brightness,
          'contrast': contrast,
        });
        await txn.rawUpdate(
          '''
          UPDATE documents
          SET page_count = (SELECT COUNT(*) FROM pages WHERE doc_id = ?),
              updated_at = ?
          WHERE id = ?
          ''',
          [docId, now, docId],
        );
      });

      return ScanPage(
        id: pageId,
        docId: docId,
        idx: nextIdx,
        origPath: paths.origPath,
        outPath: paths.outPath,
        thumbPath: paths.thumbPath,
        corners: resolvedQuad,
        filter: filter,
        rotation: rotation % 360,
        brightness: brightness,
        contrast: contrast,
      );
    } catch (_) {
      await _files.safeDeleteFile(paths.origPath);
      await _files.safeDeleteFile(paths.outPath);
      await _files.safeDeleteFile(paths.thumbPath);
      rethrow;
    }
  }

  /// Re-processes an existing page from its untouched `origPath` without quality loss.
  Future<ScanPage> reprocessPage(
    ScanPage page, {
    Quad? corners,
    FilterKind? filter,
    int? rotation,
    double? brightness,
    double? contrast,
  }) async {
    final nextCorners = corners ?? page.corners;
    final nextFilter = filter ?? page.filter;
    final nextRotation = (rotation ?? page.rotation) % 360;
    final nextBrightness = (brightness ?? page.brightness).clamp(-1.0, 1.0);
    final nextContrast = (contrast ?? page.contrast).clamp(-1.0, 1.0);

    await processPage(
      src: page.origPath,
      dst: page.outPath,
      quad: nextCorners,
      filter: nextFilter,
      rotationDeg: nextRotation,
      maxLongSide: workingMaxLongSide,
      jpegQuality: workingJpegQuality,
      brightness: nextBrightness,
      contrast: nextContrast,
    );
    await makeThumbnail(
      src: page.outPath,
      dst: page.thumbPath,
      maxSide: thumbnailMaxSide,
    );
    await _files.evictImagePaths([page.outPath, page.thumbPath]);

    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'pages',
      {
        'corners_json': encodeQuadJson(nextCorners),
        'filter': filterToDb(nextFilter),
        'rotation': nextRotation,
        'brightness': nextBrightness,
        'contrast': nextContrast,
      },
      where: 'id = ?',
      whereArgs: [page.id],
    );
    await db.update(
      'documents',
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [page.docId],
    );

    return page.copyWith(
      corners: nextCorners,
      filter: nextFilter,
      rotation: nextRotation,
      brightness: nextBrightness,
      contrast: nextContrast,
    );
  }

  Future<void> applyFilterToAllPages(
    String docId,
    FilterKind filter, {
    double? brightness,
    double? contrast,
    void Function(int done, int total)? onProgress,
  }) async {
    final pages = await getPages(docId);
    for (var i = 0; i < pages.length; i++) {
      await reprocessPage(
        pages[i],
        filter: filter,
        brightness: brightness,
        contrast: contrast,
      );
      onProgress?.call(i + 1, pages.length);
    }
  }

  Future<void> reorderPages(String docId, List<String> orderedPageIds) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (var i = 0; i < orderedPageIds.length; i++) {
        await txn.update(
          'pages',
          {'idx': i},
          where: 'id = ? AND doc_id = ?',
          whereArgs: [orderedPageIds[i], docId],
        );
      }
      await txn.update(
        'documents',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [docId],
      );
    });
  }

  Future<int> deletePage(ScanPage page) async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.delete('pages', where: 'id = ?', whereArgs: [page.id]);
    await _files.safeDeleteFile(page.origPath);
    await _files.safeDeleteFile(page.outPath);
    await _files.safeDeleteFile(page.thumbPath);
    await _files.evictImagePaths([page.origPath, page.outPath, page.thumbPath]);

    final remaining = await getPages(page.docId);
    if (remaining.isEmpty) {
      await deleteDocument(page.docId);
      return 0;
    }
    await db.transaction((txn) async {
      for (var i = 0; i < remaining.length; i++) {
        await txn.update(
          'pages',
          {'idx': i},
          where: 'id = ? AND doc_id = ?',
          whereArgs: [remaining[i].id, page.docId],
        );
      }
      await txn.update(
        'documents',
        {'page_count': remaining.length, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [page.docId],
      );
    });
    return remaining.length;
  }
}
