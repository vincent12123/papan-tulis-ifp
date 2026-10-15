# Whiteboard IFP

Aplikasi papan tulis Android untuk panel interaktif Hisense di sekolah: menulis mulus dengan jari/stylus (beberapa penulis sekaligus), papan multi-halaman, latar PDF/gambar, berbagi PDF lewat kode QR, dan asisten AI (lewat server perantara FastAPI).

---

## 📁 Struktur Dokumentasi

Project ini memakai **Spec-Driven Development** dengan 3 lapisan.

| Lapisan | File | Fungsi |
|---|---|---|
| **1. Spec** | [`SPEC.md`](SPEC.md) | Apa yang dibangun |
| | [`docs/ux-flow.md`](docs/ux-flow.md) | Alur pengguna, layar, dan state |
| **2. Verifier** | [`verification/acceptance-criteria.md`](verification/acceptance-criteria.md) | Kapan dianggap selesai |
| **3. Environment** | [`AGENTS.md`](AGENTS.md) | Aturan kerja AI |
| | [`CLAUDE.md`](CLAUDE.md) | Penghubung agar Claude Code membaca AGENTS.md |
| | [`PROGRESS.md`](PROGRESS.md) | Posisi terakhir pengerjaan antar sesi |
| | [`docs/design-system.md`](docs/design-system.md) | Aturan tampilan |

```
whitebiard/
├── AGENTS.md  CLAUDE.md  PROGRESS.md  README.md  SPEC.md
├── app/                  Aplikasi Flutter (Android)
├── server/               Server perantara FastAPI (lihat server/README.md)
├── docs/                 ux-flow.md, design-system.md
└── verification/         acceptance-criteria.md
```

### Prompt pembuka sesi baru
```
Baca AGENTS.md, PROGRESS.md, SPEC.md, docs/ux-flow.md, dan verification/acceptance-criteria.md.
Lanjutkan checkpoint sesuai PROGRESS.md. Jelaskan rencanamu dulu sebelum menulis kode.
```

### Prompt menutup sesi
```
Sebelum berhenti: jalankan verifikasi checkpoint ini, laporkan pakai format AGENTS.md §7,
lalu perbarui PROGRESS.md dan matriks keterlacakan.
```

---

## ⚙️ Persyaratan

- Flutter 3.47 (Dart 3.13) — di mesin pengembang: `D:\dev\flutter`
- Android SDK (platform 36, build-tools 36.1) — `D:\dev\android-sdk`
- JDK Temurin 17
- Python 3.12 (server, mulai Checkpoint 5)
- Panel Hisense IFP berbasis Android, izin "pasang dari sumber tidak dikenal" aktif

## 🚀 Instalasi & Menjalankan

```bash
cd app
flutter pub get
flutter run            # panel/HP Android terhubung lewat USB (adb)
```

## 🧪 Menjalankan Test

```bash
cd app
flutter analyze
powershell -ExecutionPolicy Bypass -File tool/test.ps1
```

`tool/test.ps1` menjalankan `flutter test` per berkas dan mengulang otomatis bila `flutter_tester` crash (masalah alat di Windows, bukan kegagalan test).

## 📦 Membangun dan Memasang APK

```bash
cd app
flutter build apk --release
```

APK diagnostik dengan alat ukur (fps, "Isi 3000 goresan", "Info panel") — **hanya untuk mengukur kinerja, jangan dipasang untuk guru**:

```bash
flutter build apk --release --dart-define=DIAGNOSTICS=true
```

Hasil: `app/build/app/outputs/flutter-apk/app-release.apk`. Salin ke panel (flashdisk atau adb) lalu pasang langsung di panel.
Dengan kabel USB dan debugging aktif: `adb install -r app/build/app/outputs/flutter-apk/app-release.apk`.

### 🔑 Kunci tanda tangan (WAJIB dicadangkan)

APK rilis ditandatangani dengan:
- `D:\dev\keys\whiteboard-ifp-release.jks` (kunci)
- `app/android/key.properties` (kata sandi; tidak masuk git)

**Cadangkan kedua berkas itu ke tempat aman (mis. flashdisk terpisah atau penyimpanan pribadi).**
Semua pembaruan harus ditandatangani dengan kunci yang sama. Bila kunci hilang, pembaruan tidak bisa dipasang di atas versi lama; aplikasi harus dihapus dulu dan **semua papan di panel ikut hilang**.

## 🌐 Deployment

Lihat `SPEC.md §8A` untuk langkah deploy dan rollback.

---

## 👤 Kontak

- **Pemilik:** Sukardi
- **Status project:** Pengembangan — Checkpoint 5 (server siap dipasang di VPS karyabangsa; menunggu uji di panel)
