# AGENTS.md — Instruksi untuk AI

> **Layer 3: Environment.** File ini dibaca AI di awal setiap sesi.
> Tujuannya: AI tidak perlu dijelaskan ulang tentang project, aturan, dan cara kerja.

---

## 1. Konteks Project

- **Nama:** Whiteboard IFP
- **Deskripsi singkat:** Aplikasi papan tulis Android (Flutter) untuk panel interaktif Hisense di sekolah — menulis mulus multi-jari, multi-halaman, PDF + QR, dan asisten AI lewat server perantara FastAPI.
- **Pemilik / pengambil keputusan:** Sukardi (juga admin/operator)
- **Bahasa komunikasi:** Bahasa Indonesia
- **Bahasa kode (nama variabel, komentar):** English untuk kode; semua teks antarmuka Bahasa Indonesia

## 2. Dokumen Acuan (urutan prioritas)

1. `SPEC.md` — apa yang dibangun (sumber kebenaran)
2. `verification/acceptance-criteria.md` — kapan dianggap selesai
3. `docs/ux-flow.md` — alur pengguna, layar, dan teks setiap state
4. `docs/design-system.md` — bagaimana tampilannya
5. `README.md` — cara menjalankan project
6. `PROGRESS.md` — posisi terakhir pengerjaan (bukan sumber requirement)

Jika ada konflik, ikuti dokumen dengan prioritas lebih tinggi, lalu **laporkan konfliknya**.

---

## 3. Cara Kerja

### Sebelum mulai
- Baca `PROGRESS.md` untuk mengetahui posisi terakhir dan langkah berikutnya.
- Baca SPEC.md bagian yang relevan dengan tugas.
- Butir bertanda **(usulan)** di SPEC dipakai sampai pemilik mengubahnya. Pertanyaan terbuka di SPEC §10 **tidak boleh diasumsikan** — tanyakan saat checkpoint-nya.
- Identifikasi checkpoint mana yang sedang dikerjakan (SPEC.md §9).
- Jika requirement ambigu atau tidak ada di SPEC → **tanya dulu, jangan berasumsi.**

### Saat bekerja
- Kerjakan **satu checkpoint** pada satu waktu.
- Perubahan kecil dan bertahap; jelaskan apa yang diubah dan kenapa.
- Jangan menambah fitur di luar SPEC tanpa persetujuan.
- Tulis test untuk kasus negatif (input salah, tanpa akses, data kosong), bukan hanya happy path.
- Kinerja menulis (NFR-30) adalah tolok ukur utama: jangan menambah kerja per-frame di jalur menulis tanpa mengukur.

### Mengubah SPEC
- AI **tidak boleh** mengubah isi SPEC.md secara langsung.
- Jika menemukan requirement yang kurang, salah, atau bertentangan: tulis usulan di SPEC.md §12 dengan status **Diusulkan**, lalu laporkan.
- Setelah pemilik menyetujui: terapkan perubahan, naikkan versi SPEC, catat di §11 Log Keputusan, dan perbarui acceptance criteria terkait.

### Sebelum menyatakan "selesai"
- Jalankan verifikasi sesuai `acceptance-criteria.md`.
- Laporkan hasil tiap kriteria (lolos / gagal) beserta buktinya.
- Kriteria `MANUAL` yang harus dicek di panel dan belum dicek pemilik ditandai ⏳, bukan ✅.
- **Jangan pernah bilang selesai jika belum diverifikasi.**

### Sebelum sesi berakhir
- Perbarui `PROGRESS.md`: checkpoint aktif, yang sudah selesai, yang tertunda, blocker, dan langkah berikutnya.
- Perbarui matriks keterlacakan di acceptance-criteria.md §D5.

---

## 4. Tech Stack & Konvensi

| Hal | Aturan |
|---|---|
| Jenis aplikasi | Aplikasi Android (panel Hisense IFP, lanskap) + API perantara |
| Bahasa & versi runtime | Dart 3 / Flutter 3.47 (aplikasi) · Python 3.12 (server) |
| Framework | Flutter (aplikasi) · FastAPI (server) |
| Frontend / UI | Material 3 bawaan Flutter dengan tema dari `docs/design-system.md`; kanvas `CustomPainter` + `perfect_freehand`; input sentuh lewat `Listener` (multi-pointer) |
| Database & akses data | Aplikasi: SQLite lokal (`sqflite`) mulai Checkpoint 3 · Server: SQLite (`sqlite3`/SQLAlchemy Core) |
| Migrasi skema | Aplikasi: versi skema di `onUpgrade` sqflite (format papan bernomor versi) · Server: skrip migrasi di `server/app/migrations/` |
| Manajer paket | `flutter pub` · `pip` + `requirements.txt` (venv di `server/.venv`) |
| Test | `powershell -ExecutionPolicy Bypass -File tool/test.ps1` (di `app/`; menjalankan `flutter test` per berkas) · `pytest` (di `server/`) |
| Format & lint | `dart format` + `flutter analyze` · `ruff check` + `ruff format` |
| Penamaan | Dart: file `snake_case.dart`, kelas `PascalCase`, anggota `camelCase` · Python: PEP 8 |
| Konfigurasi rahasia | Server: variabel lingkungan / `server/.env` (tidak di-commit). Aplikasi: kunci perangkat di `flutter_secure_storage`. **Tidak ada kunci API di APK.** |

### Perintah penting
| Tujuan | Perintah |
|---|---|
| Instal dependency | `cd app && flutter pub get` · `cd server && python -m venv .venv && .venv/Scripts/pip install -r requirements.txt` |
| Jalankan lokal | `cd app && flutter run` (perangkat/panel terhubung adb) · `cd server && .venv/Scripts/uvicorn app.main:app --reload` |
| Jalankan test | `cd app && powershell -ExecutionPolicy Bypass -File tool/test.ps1` · `cd server && .venv/Scripts/pytest` |
| Format / lint | `cd app && dart format . && flutter analyze` · `cd server && .venv/Scripts/ruff check .` |
| Build produksi | `cd app && flutter build apk --release` → `app/build/app/outputs/flutter-apk/app-release.apk` |

SDK lokal di mesin pengembang: Flutter `D:\dev\flutter`, Android SDK `D:\dev\android-sdk`, JDK Temurin 17.

### Struktur folder penting
```
app/                       Aplikasi Flutter (Android)
  lib/main.dart            Titik masuk
  lib/ui/theme.dart        Token design system (satu-satunya tempat warna/ukuran)
  lib/canvas/              Model goresan, penangkap input multi-jari, painter
  lib/board/               SCR-01 Papan, SCR-03 Panel Halaman, BoardDocument (simpan otomatis), media_import (Gambar, latar PDF)
  lib/boards/              SCR-02 Daftar Papan
  lib/data/                SQLite: skema (app_database), repository, codec objek, media_store (berkas gambar/latar)
  lib/app_shell.dart       Alur buka aplikasi (papan terakhir), memuat, papan rusak
  lib/mandarin/            Kartu pinyin & arti + suara Mandarin (REQ-30)
  lib/table/               Tabel → grafik (REQ-21): data sel, penggambar tabel & grafik data, dialog isi tabel
  lib/diagnostics/         Alat ukur uji panel (hanya di APK uji: --dart-define=DIAGNOSTICS=true)
  test/                    Test per acceptance criteria (nama berisi ID AC)
  test/support/            Repository tiruan di memori untuk test layar
  tool/test.ps1            Penjalan test (mengulang otomatis crash flutter_tester)
server/                    Server perantara FastAPI: app/ (main, ai, config, db, security, cli), tests/, deploy/ (systemd, nginx), README.md
  app/lib/server/          Klien server + penyimpanan pengaturan (PIN di flutter_secure_storage)
  app/lib/settings/        SCR-06 Pengaturan
docs/                      ux-flow.md, design-system.md
verification/              acceptance-criteria.md
```

---

## 4A. Aturan UI/UX

- **Mode desain:** semua layar **Fungsional** (`docs/design-system.md §0`). Tema Material 3 bawaan, ubah sesedikit mungkin, tanpa dekorasi atau animasi yang tidak diminta. Kanvas adalah fokus.
- Layar hanya dibuat bila kartunya di `docs/ux-flow.md` berstatus **Disetujui**.
- Setiap layar wajib mengimplementasikan **4 state** (memuat, kosong, gagal, berhasil) dengan teks **persis** seperti di kartu layar.
- Teks tombol, notifikasi, dan istilah mengikuti `docs/ux-flow.md §7 Daftar Istilah`.
- Batas mutu minimum (layar sentuh besar, dipakai berdiri): tombol utama ≥ 64 dp, tombol lain ≥ 48 dp, teks ≥ 20 sp, kontras ≥ 4.5:1, ikon tanpa teks punya label aksesibel, status tidak dibedakan lewat warna saja.
- Sebelum melaporkan checkpoint UI: screenshot di resolusi panel (lanskap) dan halaman unduh di 360 px, cek 4 state, cocokkan dengan design system.

---

## 5. Larangan

- ❌ Mengubah struktur data tanpa memperbarui SPEC.md §4
- ❌ Mengubah SPEC.md tanpa persetujuan pemilik (usulkan di §12)
- ❌ Mengasumsikan jawaban pertanyaan terbuka SPEC §10
- ❌ Menjalankan migrasi destruktif tanpa persetujuan
- ❌ Menghapus atau melemahkan test agar lolos
- ❌ Menaruh kunci API penyedia AI, kunci perangkat, atau PIN di kode atau APK
- ❌ Menambah dependency baru tanpa menyebut alasannya
- ❌ Memakai warna / ukuran di luar `lib/ui/theme.dart`
- ❌ Membuat layar, menu, atau alur yang tidak ada di `docs/ux-flow.md`
- ❌ Mengarang teks pesan error / state kosong sendiri bila sudah ditulis di kartu layar
- ❌ Menampilkan kode error mentah atau stack trace ke pengguna
- ❌ Gangguan jaringan/server/AI yang mengubah atau menghapus isi papan (REQ-18)
- ❌ Mencatat isi papan atau hasil AI di log server (NFR-21)
- ❌ Mengganti kunci tanda tangan APK rilis (pembaruan tidak bisa dipasang di atas versi lama dan papan hilang)

## 6. Wajib

- ✅ Setiap fitur baru disertai test untuk acceptance criteria-nya
- ✅ Validasi semua input dari pengguna
- ✅ Pesan error dan label UI dalam Bahasa Indonesia
- ✅ Pesan error menyebut apa yang salah dan cara memperbaikinya; papan dan isian pengguna tidak hilang saat gagal
- ✅ Aksi berisiko (hapus papan/halaman) meminta konfirmasi yang menyebut nama/nomor datanya
- ✅ Simpan UTC, tampilkan WIB
- ✅ Fitur yang butuh internet gagal dengan pesan jelas; fitur menulis tetap jalan tanpa internet

---

## 7. Format Laporan Setelah Tugas

```
## Ringkasan
[Apa yang dikerjakan]

## File yang diubah
- path/file — [alasan]

## Verifikasi
- AC-01 (REQ-01): ✅ lolos — [bukti]
- AC-03 (REQ-01): ⏳ menunggu uji di panel

## Usulan perubahan SPEC
- [jika ada — juga dicatat di SPEC.md §12]

## Pertanyaan / Keputusan yang dibutuhkan
- [jika ada]

## PROGRESS.md
- [sudah diperbarui ✅]
```

---

## 8. Pelajaran (diisi seiring waktu)

- 2026-10-14 Shell Bash di mesin ini kadang gagal mem-parse heredoc panjang di satu perintah; tulis skrip ke berkas (Write) lalu jalankan.
- 2026-10-14 `flutter_tester` 3.47.7 di mesin Windows ini crash acak (exit 0xC0000005, "did not complete" / "Connection closed before test suite loaded") bahkan untuk test sepele. Jangan mengejar "bug" itu di kode aplikasi: jalankan test lewat `tool/test.ps1`, yang mengulang crash saja dan tetap menggagalkan test yang benar-benar salah.
- 2026-10-14 `flutter.bat` memotong argumen yang berisi `|` (mis. `--name 'a|b'`). Untuk regex, panggil flutter_tools langsung lewat `dart.exe … flutter_tools.snapshot test`.
- 2026-10-14 Aksi yang mengganti target menulis (ganti alat, ganti halaman) harus berlaku untuk sentuhan berikutnya walau frame belum digambar ulang: baca target saat pointer-down (lihat `InkCanvas.tool` dan `InkCanvas.target`), jangan dari properti widget yang baru berubah di frame berikutnya.
- 2026-10-14 Widget test `tester.tap` menekan dan mengangkat dalam satu frame, jadi tidak menangkap bug yang muncul bila jari tertahan (mis. menu tertutup saat pointer-down). Untuk kontrol yang bereaksi pada pointer-down, tambahkan test dengan `startGesture` → `pump(80ms)` → `up`.
- 2026-10-14 FastAPI: jangan pakai `from __future__ import annotations` di modul yang mendefinisikan dependensi/model di dalam fungsi (`create_app`); tipe berupa string tak bisa di-resolve dan dependensi berubah jadi query parameter (422).
- 2026-10-14 Peluang crash `flutter_tester` naik seiring panjang berkas test; jaga berkas widget test ≤ ~20 test (pecah per grup, helper bersama di `test/support/app_harness.dart`).
- 2026-10-14 VPS karyabangsa adalah produksi: pemeriksaan baca-saja boleh, tetapi setiap perubahan (berkas, systemd, nginx, cloudflared) wajib dikonfirmasi pemilik lebih dulu. Kunci API dan PIN diisi pemilik sendiri di server, tidak lewat AI.
- 2026-10-14 Izin `INTERNET` Flutter hanya ada di manifest debug; APK rilis tanpa izin itu di `src/main/AndroidManifest.xml` gagal "tidak bisa terhubung" walau server sehat (dijaga `test/android_manifest_test.dart`). Cek log akses nginx server: bila permintaan panel tidak tercatat, masalahnya di perangkat.
- 2026-10-15 APK yang dikirim ke pemilik untuk dipakai/diuji guru dibangun **tanpa** `DIAGNOSTICS` (`dist/papan-tulis.apk`); alat ukur di bilah atas membuat UI tampak tidak profesional. Tinjau UI lewat `app/tool/screenshots_test.dart` (1920×1080, font Roboto asli).
- 2026-10-15 Test model (items) tidak menangkap bug gambar: `InkPictureCache` pernah menyimpan alias list controller sehingga perubahan di tempat tak tergambar. Untuk fitur kanvas baru, cek juga screenshot (`tool/screenshots_test.dart`, panggil `_settle` sebelum `_shot`) dan test cache.
- 2026-10-14 Jangan `dispose()` ValueNotifier yang masih bisa diubah oleh penulisan async yang tertunda (lihat `SaveQueue._disposed`).
