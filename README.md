<p align="center">
  <img src="assets/jscan_app_icon.svg" width="96" height="96" alt="JScan Logo" />
</p>

<h1 align="center">JScan</h1>

<p align="center">
  <strong>Pemindai dokumen Android 100% offline — cepat, tajam, tanpa iklan, dan tanpa izin internet.</strong>
</p>

<p align="center">
  <a href="https://github.com/liefamrah/jscan/releases/latest">
    <img src="https://img.shields.io/github/v/release/liefamrah/jscan?label=Rilis%20Terbaru&color=F7D568&labelColor=1D1D1C&style=for-the-badge" alt="Rilis Terbaru" />
  </a>
  <img src="https://img.shields.io/badge/Android-7.0%2B%20(API%2024)-1D1D1C?style=for-the-badge&logo=android&logoColor=F7D568" alt="Android 7.0+" />
  <img src="https://img.shields.io/badge/Offline-100%25%20Tanpa%20Internet-1D1D1C?style=for-the-badge" alt="100% Offline" />
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/Lisensi-MIT-1D1D1C?style=for-the-badge" alt="Lisensi MIT" />
  </a>
</p>

---

## Unduh APK

Unduh langsung file APK rilis terbaru melalui halaman **GitHub Releases**:

| Varian APK | Rekomendasi Perangkat | Tautan Unduh Langsung |
| --- | --- | --- |
| **ARM64 (`arm64-v8a`)** *(Disarankan)* | Hampir semua ponsel Android modern (ukuran paling kecil) | [**Unduh JScan-v1.0.0-arm64.apk**](https://github.com/liefamrah/jscan/releases/latest/download/JScan-v1.0.0-arm64.apk) |
| **ARMv7 (`armeabi-v7a`)** | Ponsel Android 32-bit lama | [**Unduh JScan-v1.0.0-armeabi-v7a.apk**](https://github.com/liefamrah/jscan/releases/latest/download/JScan-v1.0.0-armeabi-v7a.apk) |
| **Universal** | Semua arsitektur Android dalam satu file | [**Unduh JScan-v1.0.0-universal.apk**](https://github.com/liefamrah/jscan/releases/latest/download/JScan-v1.0.0-universal.apk) |

> Lihat semua rilis & checksum `SHA256SUMS.txt` di **[Halaman Releases](https://github.com/liefamrah/jscan/releases/latest)**.

### Cara Memasang APK
1. Unduh varian APK yang sesuai (disarankan **`JScan-v1.0.0-arm64.apk`**).
2. Buka file APK dari pengelola berkas Android.
3. Jika diminta, izinkan **Pasang aplikasi dari sumber ini**, lalu ketuk **Pasang**.

---

## Fitur Utama

- **Deteksi 4 Sudut Otomatis (Real-time)**: Algoritma *Gradient-Guided Hough Line + Contour* di Rust mengunci keempat tepi kertas dengan presisi tinggi meski ada bayangan atau klip di pinggir halaman.
- **Pelurusan Perspektif & Hapus Bayangan**: Meluruskan foto dokumen miring (*bicubic homography `f64`*) dan meratakan pencahayaan untuk menghilangkan bayangan tangan/HP tanpa *halo*.
- **Mode Pindai Lengkap**: Mendukung **Dokumen Tunggal**, **Multi-Halaman**, **KTP / Kartu 2 Sisi**, *auto-capture*, serta orientasi kamera *portrait* & *landscape*.
- **Editor Halaman Presisi**: Geser sudut dengan kaca pembesar (*loupe*), putar 90°, atur kecerahan/kontras, dan 4 filter (*Asli*, *Warna*, *Abu-abu*, *Hitam-Putih*).
- **Alat PDF & Gambar Offline**:
  - JPG / PNG ke PDF
  - PDF ke JPG / PNG (otomatis dikemas ZIP jika > 1 halaman)
  - Kompres PDF
  - Gabung PDF & Pisah PDF
- **Ekspor Fleksibel**: Simpan atau bagikan sebagai PDF (A4 / Asli, margin, watermark teks) maupun JPG/PNG.
- **Privasi Total (100% Offline)**: `AndroidManifest.xml` **tidak meminta izin `INTERNET`**. Semua gambar, database SQLite, font, dan pemrosesan berjalan penuh di perangkat Anda.

---

## Arsitektur & Teknologi

| Lapisan | Teknologi |
| --- | --- |
| **UI & State** | Flutter (Material 3, Mode Terang & Gelap), Riverpod, *Plus Jakarta Sans* (bundel lokal) |
| **Pemrosesan Citra & PDF** | Rust (`flutter_rust_bridge`, `image`, `imageproc`, `lopdf`, `zip`) |
| **Penyimpanan Lokal** | SQLite (`sqflite`) & penyimpanan internal aplikasi |
| **Kamera & Berkas** | `camera`, `image_picker`, `file_picker`, `pdfx`, `share_plus` |

---

## Build dari Source

### Prasyarat
- Flutter SDK (Dart `^3.14.0`) & Android SDK (API 24+)
- *(Opsional — hanya jika mengubah kode Rust di `rust/`)* Rust toolchain + [`cargo-ndk`](https://github.com/bbqsrc/cargo-ndk) dengan target `aarch64-linux-android` dan `armv7-linux-androideabi`. Library `.so` siap pakai sudah disertakan di `android/app/src/main/jniLibs/`.

### Menjalankan Secara Lokal
```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

### Membangun Ulang Native Library Rust *(Opsional)*
```bash
cd rust
cargo test
cargo ndk -t arm64-v8a -t armeabi-v7a -o ../android/app/src/main/jniLibs build --release
```

### Build APK Rilis (Signed)
1. Buat keystore rilis Anda (sekali saja):
   ```bash
   keytool -genkey -v -keystore android/app/upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias jscan
   ```
2. Salin [`android/key.properties.example`](android/key.properties.example) menjadi `android/key.properties` dan isi kredensial keystore Anda *(file ini sudah ada di `.gitignore` — jangan pernah commit ke Git)*.
3. Bangun APK rilis dengan obfuscation & arsipkan simbol debug (`build/symbols`):
   ```bash
   flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
   flutter build apk --release --obfuscate --split-debug-info=build/symbols
   ```

---

## Dukungan & Pengembang

Dibuat oleh **[Muhammad Alief Amrah (@liefamrah)](https://github.com/liefamrah)**.

Jika JScan membantu pekerjaan atau kuliah Anda, dukung pengembangan aplikasi gratis & bebas iklan ini melalui Saweria:

[![Traktir Kopi di Saweria](https://img.shields.io/badge/Dukung%20via-Saweria%20(saweria.co%2Faliefa)-F7D568?style=for-the-badge&labelColor=1D1D1C)](https://saweria.co/aliefa)

---

## Lisensi

Proyek ini dirilis di bawah lisensi [MIT](LICENSE).
