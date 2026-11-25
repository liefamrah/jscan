import '../src/rust/api.dart';

class ScanDocument {
  const ScanDocument({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.pageCount,
    this.tag = '',
    this.coverThumbPath,
  });

  final String id;
  final String name;
  final int createdAt;
  final int updatedAt;
  final int pageCount;
  final String tag;
  final String? coverThumbPath;

  ScanDocument copyWith({
    String? name,
    int? updatedAt,
    int? pageCount,
    String? tag,
    String? coverThumbPath,
  }) => ScanDocument(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    pageCount: pageCount ?? this.pageCount,
    tag: tag ?? this.tag,
    coverThumbPath: coverThumbPath ?? this.coverThumbPath,
  );
}

class ScanPage {
  const ScanPage({
    required this.id,
    required this.docId,
    required this.idx,
    required this.origPath,
    required this.outPath,
    required this.thumbPath,
    required this.corners,
    required this.filter,
    required this.rotation,
    this.brightness = 0.0,
    this.contrast = 0.0,
  });

  final String id;
  final String docId;
  final int idx;
  final String origPath;
  final String outPath;
  final String thumbPath;
  final Quad corners;
  final FilterKind filter;
  final int rotation;
  final double brightness;
  final double contrast;

  ScanPage copyWith({
    int? idx,
    Quad? corners,
    FilterKind? filter,
    int? rotation,
    double? brightness,
    double? contrast,
  }) => ScanPage(
    id: id,
    docId: docId,
    idx: idx ?? this.idx,
    origPath: origPath,
    outPath: outPath,
    thumbPath: thumbPath,
    corners: corners ?? this.corners,
    filter: filter ?? this.filter,
    rotation: rotation ?? this.rotation,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
  );
}
