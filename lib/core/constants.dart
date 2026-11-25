import '../src/rust/api.dart';

const String appName = 'JScan';
const String appVersion = '1.0.1';
const String developerUrl = 'https://github.com/liefamrah';
const String developerLabel = 'github.com/liefamrah';
const String donationUrl = 'https://saweria.co/aliefa';
const String donationLabel = 'saweria.co/aliefa';

const FilterKind defaultScanFilter = FilterKind.color;
const int workingMaxLongSide = 2000;
const int workingJpegQuality = 88;
const int thumbnailMaxSide = 360;

const Quad fallbackInsetQuad = Quad(
  pts: [(0.03, 0.03), (0.97, 0.03), (0.97, 0.97), (0.03, 0.97)],
);

const Quad fullFrameQuad = Quad(
  pts: [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)],
);

const List<String> documentTags = ['Identitas', 'Struk', 'Kerja', 'Pribadi'];
const int maxCategoryNameLength = 32;

const List<String> watermarkPresets = [
  'HANYA UNTUK VERIFIKASI',
  'RAHASIA',
  'SALINAN',
];

enum DocSort {
  newest('Terbaru'),
  oldest('Terlama'),
  nameAsc('Nama A–Z');

  const DocSort(this.label);
  final String label;
}

enum ExportFormat {
  pdf('PDF', 'pdf'),
  jpg('JPG', 'jpg'),
  png('PNG', 'png');

  const ExportFormat(this.label, this.ext);
  final String label;
  final String ext;
}

enum ExportQuality {
  high('Tinggi', 2400, 90),
  medium('Sedang', 1800, 80),
  low('Kecil', 1200, 65);

  const ExportQuality(this.label, this.maxLongSide, this.jpegQuality);
  final String label;
  final int maxLongSide;
  final int jpegQuality;
}

enum PdfMargin {
  none('Tanpa margin', 0.0),
  thin('Tipis', 24.0);

  const PdfMargin(this.label, this.points);
  final String label;
  final double points;
}

enum PdfCompressLevel {
  light('Ringan', 1.6, 75),
  medium('Sedang', 1.25, 58),
  strong('Maksimal', 0.95, 42);

  const PdfCompressLevel(this.label, this.renderScale, this.jpegQuality);
  final String label;
  final double renderScale;
  final int jpegQuality;
}

String filterLabel(FilterKind filter) => switch (filter) {
  FilterKind.original => 'Asli',
  FilterKind.color => 'Warna',
  FilterKind.grayscale => 'Abu-abu',
  FilterKind.documentBw => 'Hitam-Putih',
};
