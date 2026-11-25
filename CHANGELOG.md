# Changelog

## [1.0.1] - 2026-11-26

### Fitur Baru
- **Kelompok (Kategori) Kustom**: buat nama kelompok sendiri untuk mengelompokkan dokumen hasil pindaian, lengkap dengan aksi ubah nama dan hapus kelompok (dokumen di dalamnya tetap aman saat kelompok dihapus).
- **Akses Cepat Pengelompokan**: tambah kelompok langsung dari bilah filter di beranda (`+ Kelompok`), atur dari menu dokumen, kelompokkan beberapa dokumen sekaligus pada mode pilih banyak, atau ubah langsung di layar tinjau dokumen.

### Peningkatan & Penyimpanan
- **Migrasi Database SQLite v4**: penambahan tabel `categories` dengan migrasi otomatis (`onUpgrade`) dan validasi anti-duplikat *case-insensitive*.
- **Tampilan Lencana Aman**: teks nama kelompok panjang kini menggunakan pemotongan (*ellipsis*) agar tidak meluap pada kartu grid maupun daftar.

## [1.0.0] - 2026-11-25

Rilis perdana **JScan** — pemindai dokumen Android 100% offline berbasis Flutter & Rust.

### Fitur Utama
- **Pemindaian Kamera Pintar**: deteksi 4 sudut otomatis (*Gradient-Guided Hough Line + Contour*) secara real-time, mode Dokumen / Multi-Halaman / KTP 2 Sisi, penangkapan otomatis (*auto-capture*) dengan anti-*double capture*, serta dukungan orientasi *portrait* & *landscape*.
- **Pelurusan Perspektif & Pembersihan Bayangan**: proyeksi homografi `f64` bicubic + estimasi latar *morphological closing* di Rust untuk menghilangkan bayangan tangan/ponsel tanpa *halo*.
- **Penyuntingan Halaman**: koreksi 4 sudut dengan kaca pembesar (*loupe*) dan handle titik tengah sisi, putar 90°, filter (*Asli*, *Warna*, *Abu-abu*, *Hitam-Putih*), serta penyesuaian kecerahan & kontras.
- **Alat Konversi Offline**: JPG/PNG ke PDF, PDF ke JPG/PNG (ZIP otomatis untuk multi-halaman), Kompres PDF, Gabung PDF, dan Pisah PDF.
- **Ekspor & Privasi**: ekspor ke PDF (A4/Asli, pilihan margin, watermark) atau JPG/PNG, tanpa izin `INTERNET`, tanpa iklan, tanpa pelacakan.
- **UI/UX Modern**: dukungan penuh Mode Terang & Gelap, tipografi lokal *Plus Jakarta Sans*, ikon adaptif + splash screen Android 12+, serta onboarding 3 halaman saat pertama kali dibuka.
