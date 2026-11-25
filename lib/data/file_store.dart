import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/utils.dart';

/// Manages private app storage (`docs/<docId>/`) and temporary caches.
class FileStore {
  Directory? _docsRoot;
  Directory? _tempRoot;

  Future<Directory> _ensureDocsRoot() async {
    if (_docsRoot != null) return _docsRoot!;
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'docs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _docsRoot = dir;
    return dir;
  }

  Future<Directory> _ensureTempRoot() async {
    if (_tempRoot != null) return _tempRoot!;
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'jscan_tmp'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _tempRoot = dir;
    return dir;
  }

  Future<Directory> ensureDocDir(String docId) async {
    final root = await _ensureDocsRoot();
    final dir = Directory(p.join(root.path, docId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Allocates paths following `docs/<docId>/p<tag>_orig.jpg`, `p<tag>.jpg`, `p<tag>_thumb.jpg`.
  Future<({String origPath, String outPath, String thumbPath})> allocatePagePaths(
    String docId,
    String pageTag,
  ) async {
    final dir = await ensureDocDir(docId);
    return (
      origPath: p.join(dir.path, 'p${pageTag}_orig.jpg'),
      outPath: p.join(dir.path, 'p$pageTag.jpg'),
      thumbPath: p.join(dir.path, 'p${pageTag}_thumb.jpg'),
    );
  }

  Future<void> deleteDocDir(String docId) async {
    final root = await _ensureDocsRoot();
    final dir = Directory(p.join(root.path, docId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> safeDeleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }

  Future<Directory> createTempWorkDir(String prefix) async {
    final root = await _ensureTempRoot();
    final dir = Directory(p.join(root.path, '${prefix}_${generateId()}'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Removes temporary export/conversion files on app startup.
  Future<void> cleanupTempCache() async {
    await clearTempCacheAndReportBytes();
  }

  /// Clears temporary export/conversion files and returns total freed bytes.
  Future<int> clearTempCacheAndReportBytes() async {
    var freed = 0;
    try {
      final root = await _ensureTempRoot();
      if (await root.exists()) {
        freed = await _dirSize(root);
        await for (final entity in root.list()) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
    return freed;
  }

  /// Calculates total private storage used by saved documents and temporary cache.
  Future<({int docsBytes, int cacheBytes})> computeStorageUsage() async {
    final docsDir = await _ensureDocsRoot();
    final tempDir = await _ensureTempRoot();
    final docsBytes = await _dirSize(docsDir);
    final cacheBytes = await _dirSize(tempDir);
    return (docsBytes: docsBytes, cacheBytes: cacheBytes);
  }

  Future<int> _dirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// Evicts modified image paths (including ResizeImage cacheWidth variants)
  /// from Flutter's in-memory image cache so overwritten files immediately refresh.
  Future<void> evictImagePaths(Iterable<String> paths) async {
    for (final path in paths) {
      final provider = FileImage(File(path));
      await provider.evict();
      for (final w in const [140, 160, 200, 420, 1600]) {
        await ResizeImage(provider, width: w).evict();
      }
    }
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}
