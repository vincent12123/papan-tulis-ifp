# PROGRESS.md — Posisi Pengerjaan

> Diperbarui AI **di akhir setiap sesi**. Dibaca AI **di awal setiap sesi**.
> File ini bukan sumber requirement — requirement tetap di `SPEC.md`.

---

## Status Saat Ini

- **Checkpoint aktif:** 16 Mandarin — langkah 1 (pengenal Hanzi) selesai di kode server: `app/hanzi_reader.py` + `python -m app.cli uji-hanzi`; uji awal dengan font: rapi 60/60, kursif sebagian salah. **Berikutnya:** (a) pemilik/guru Mandarin mengirim tangkapan tulisan asli dari panel untuk AC-195; (b) cek suara zh-CN di panel Hisense (AC-194); (c) lanjut kamus (pypinyin, jieba, CC-CEDICT), endpoint, kartu `mandarin` di aplikasi. Model belum dipasang di VPS (perlu konfirmasi pemilik).
- **Versi SPEC yang dipakai:** 1.13 (ux-flow 1.8)
- **Terakhir diperbarui:** 2026-10-15 oleh AI
- **Repo:** https://github.com/vincent12123/papan-tulis-ifp (publik, branch main)

## ✅ Sudah Selesai
- **Checkpoint 16 langkah 1 — pengenal Hanzi (2026-10-15):** dibandingkan RapidOCR (pendeteksi + pengenal) vs pengenal saja per baris; dipilih model PP-OCRv4 rec ONNX langsung lewat onnxruntime (tanpa rapidocr/opencv). Ambang keyakinan 0,7 + tolak huruf non-Han. Model di `server/models/ppocr-v4-rec/` (SHA-256 di README). 11 pytest baru. Paket uji (rapidocr, opencv) sudah dicopot lagi dari venv lokal.
- **Checkpoint 15 — Tabel → grafik (REQ-21, 2026-10-15):** `lib/table/` (table_data: baca angka koma/titik, seri, sumbu bulat; table_painter: sel + tanda sel bukan angka; chart_painter: Garis/Batang berkelompok/Titik, penanda bentuk berbeda per seri + legenda; table_editor: dialog Sisipkan tabel & Isi tabel). Objek `TableItem` (jenis `tabel`) dan `ChartItem` (jenis `grafik` + field `jenis`, salinan sel + id tabel) di `stroke.dart` + codec; `InkController.updateTable` (tabel + grafiknya satu Undo, `ReplaceMany`); ketukan sel di `InkCanvas.onTableCell`; tombol Tabel di bilah alat; tombol tabel di bawah tabel; grafik ditaruh di samping tabel tanpa menimpa. Tanpa server, tanpa dependency baru. 13 test baru (`test/table_test.dart`) + screenshot 10–12.
- **Perbaikan bug lama (2026-10-15):** `InkPictureCache` menyimpan alias list item controller, sehingga item yang ditambah/diganti di tempat tidak digambar ulang selama halaman tanpa kuis/peraga berjalan (terbukti: test regresi gagal dengan kode lama). Kini menyimpan salinan list. Perlu dicek di panel bahwa goresan tetap tampil setelah jari diangkat.
- **SPEC 1.13 (2026-10-15):** REQ-30 Mandarin disetujui (Checkpoint 16; AC-190–AC-195).
- **SPEC 1.12 (2026-10-15):** REQ-21 Tabel → grafik disetujui dan diterapkan (§3.1, §4.3 jenis `tabel`, §5.4, Checkpoint 15); AC-180–AC-187; pola Tabel di ux-flow 1.8 (teks usulan). Kode tempelan dari luar (OCR tabel AI + Mandarin) ditinjau dan tidak dipakai.
- **Checkpoint 11–14 (REQ-26–29 + sketsa REQ-23):** `lib/peraga/` (katalog 8 peraga + rumus, penggambar adegan, kuis + editor), lapisan hidup `LiveItemsPainter` + ticker di `InkCanvas` (hanya jalan saat ada peraga diputar), objek `peraga` & `kuis` (codec), tombol "Peraga", menu pintar `smart_suggest.dart` (saran peraga, sketsa → bangun), goresan kapur (tekstur butiran, field `k`), tema papan (app_state per papan); server: jenis AI `kuis` (`parse_quiz`).
- **Checkpoint 8 — Bangun ruang 3D (REQ-23):** `lib/solid/` (geometri + jaring berengsel + penggambar sendiri), objek `bangun` (codec), menu Bentuk baris kedua, putar dengan jari, tombol Jaring-jaring (animasi) / Bidang potong di dalam objek.
- **Checkpoint 9 — Kimia + video (REQ-24):** server `formula_chem.py` (baca rumus/reaksi, penyetaraan SymPy), `video_library.py` (katalog `video/katalog.toml`), `GET /video/{id}`; aplikasi: bilah kimia (Rapikan, Setarakan, Video eksperimen), `video_dialog.dart` (video_player).
- **Checkpoint 10 — Rekam kelas (REQ-25):** server `class_summary.py` (faster-whisper + ringkasan AI, job), `POST/GET /kelas/ringkas`; aplikasi `lib/lesson/` (perekam `record`, sesi, tombol Rekam, dialog ringkasan, tempel di halaman baru); izin RECORD_AUDIO. Jawaban teks AI kini tanpa Markdown/LaTeX.
- **Checkpoint 7 — Menu pintar (2026-10-15, SPEC 1.9 REQ-22):** server 0.7.0 `POST /rumus/kenali` (formula_insight: fungsi/persamaan/ekspresi + SymPy solve terbatas polinom ≤ derajat 4 / SPL ≤ 3; formula_render: matplotlib mathtext Computer Modern, PNG transparan warna tinta, bentuk seperti ditulis). Aplikasi: `lib/board/smart_menu.dart` (pengenalan otomatis saat melingkari, tombol sesuai jenis, pesan gagal + Coba lagi), Rapikan rumus = `InkController.replaceItems` (satu Undo), Selesaikan di samping area. Dipasang di VPS (cadangan `/root/papan-server-0.6.0-backup-20261015.tgz`); uji HTTPS: fungsi 3,0 dtk, x² = 4 → x = ±2 0,6 dtk.
- **SPEC 1.8 — Jadikan grafik tanpa AI (2026-10-15):** server 0.6.0 di VPS: `formula_reader.py` (potong baris + Pix2Text MFR 1.5 via onnxruntime, tanpa torch) dan `formula_math.py` (SymPy: daftar putih, log basis 10, uji hitung 41 titik, sumbu otomatis). Format jawaban sama → APK lama tetap jalan. Model di `server/models/` (diunduh di VPS, SHA-256 cocok). 103 pytest, ruff bersih. Cadangan kode lama: `/root/papan-server-0.5.0-backup-20261015.tgz`.
- **Server di VPS karyabangsa (2026-10-14):** disalin langsung ke `/var/www/papan.karyabangsa.sch.id/server` (milik `sukardi:www-data`, venv, `.env` 640, `data/` 750); `papan.service` di 127.0.0.1:3030; situs nginx `papan.karyabangsa.sch.id`; ingress Cloudflare Tunnel + CNAME (cadangan `/etc/cloudflared/config.yml.bak-20261014-papan`). `https://papan.karyabangsa.sch.id/sehat` → 200; `/koneksi` → `pin_belum_diatur` (benar, PIN belum diatur). App lain tetap 200 setelah restart cloudflared.
- **Checkpoint 1–4 (kode):** menulis multi-jari, Penghapus, Geser/zoom, simpan otomatis + salinan, halaman, Daftar Papan, Bentuk/Pilih/Gambar, latar PDF ≤ 5 halaman.
- **Checkpoint 5 (kode):** server FastAPI (PIN admin scrypt + kunci 5 menit, penyedia dari `penyedia.toml`, 5 adaptor, cadangan Ollama, catatan tanpa isi, CLI operator, berkas `deploy/`) dan SCR-06 Pengaturan (terkunci admin, Tes koneksi, penyedia/model, Tes AI, Ganti PIN).
- **Checkpoint 6 (sebagian) — dari video referensi "AI Blackboard":**
  - REQ-20 disetujui pemilik (SPEC v1.6): rumus tulisan tangan → **grafik interaktif** dengan penggeser parameter; P-03 diputuskan: gambar area dikirim ke AI vision.
  - Server: kelima adaptor mengirim gambar (Ollama `images`, OpenAI/kompatibel `image_url`, Anthropic `image`, Gemini `inline_data`); model bergambar dipilih otomatis (juga untuk cadangan Ollama); aksi `grafik` mengembalikan JSON tervalidasi (whitelist karakter rumus, batas 4 fungsi/6 parameter, rentang wajar); 66 pytest.
  - Aplikasi: pengurai rumus aman sendiri (`lib/graph/expression.dart`, tanpa menjalankan kode), objek **grafik** (kotak koordinat, sumbu bernomor, kurva per rumus, legenda rapi, penggeser "A = 1,5") yang bisa dipindah/diubah ukuran/dihapus/Undo dan tersimpan; penggeser bisa digeser dengan alat apa pun kecuali Geser; objek **teks** untuk hasil Pecah soal/Soal serupa/Ringkas.
  - Pilih: seret di tempat kosong = lingkari area (garis putus-putus) + tombol cepat "Asisten AI"; tombol "Asisten AI" juga di bilah atas.
  - SCR-05 Asisten AI: 4 aksi (Pecah soal, Buat soal serupa, Ringkas papan, Jadikan grafik), memuat + Batalkan, semua pesan gagal kartu, pratinjau teks/grafik, Buang / Tempel ke papan (di samping area, langsung terpilih), keterangan cadangan, peringatan privasi.
  - Dicek di pratinjau web dengan server tiruan: lingkari → Jadikan grafik → Tempel → geser A = 4,5 dan B = 2 dengan alat Pena; kurva berubah langsung seperti di video.
- APK untuk guru: `dist/papan-tulis.apk` (tanpa alat ukur). APK diagnostik hanya dibangun bila perlu mengukur kinerja.

## 🔄 Sedang Dikerjakan / Tertunda
- **Uji di panel** (AC-83 ⏳): isi alamat + PIN di Pengaturan, lalu Jadikan grafik dengan tulisan tangan asli. Uji dari PC lewat alamat publik sudah lolos: gambar rumus → `y = x^2 - 3`, `y = A * sin(x) + B` + penggeser A/B dalam ~2 dtk (gemma4:31b).
- Jawaban teks AI (Pecah soal) masih memakai Markdown/LaTeX (`**…**`, `$x^2$`) yang tampil mentah di objek teks papan — perlu prompt "teks biasa" atau pembersih di aplikasi.
- REQ-10 "Ubah ke teks" (tulisan tangan → teks) — usulan: lewat AI vision yang sama (menjawab P-04), menunggu konfirmasi.
- Teks hasil AI belum bisa diedit di papan (baru pindah/ubah ukuran/hapus) — butuh alat Teks.
- Uji di panel (Checkpoint 1–6).

## ⛔ Blocker / Menunggu Keputusan
- Uji akurasi pengenal rumus dengan tulisan tangan asli di panel (server 0.6.0 sudah terpasang).
- Persetujuan usulan SPEC 1.7 (REQ-21 Tabel → grafik) beserta rinciannya.
- P-04: Ubah ke teks lewat AI vision (usulan) atau ML Kit.
- Teks usulan yang belum dikonfirmasi (SCR-06 dan CP4) — lihat ux-flow.

## ➡️ Langkah Berikutnya
1. Masukkan `https://papan.karyabangsa.sch.id` + PIN di Pengaturan panel, uji Jadikan grafik dengan tulisan tangan asli.
2. Uji Jadikan grafik dengan tulisan tangan nyata di panel; sesuaikan prompt bila perlu.
3. REQ-10 Ubah ke teks dan alat Teks (edit teks), lalu Checkpoint 7 uji pengguna.

---

## Riwayat Sesi

| Tanggal | Checkpoint | Yang dikerjakan | Hasil verifikasi |
|---|---|---|---|
| 2026-10-14 | — | SPEC v0.1–v1.0, ux-flow v1.0 disetujui; acceptance criteria, AGENTS.md, design system | — |
| 2026-10-14 | 1 | Toolchain, proyek Flutter, kanvas uji + diagnostik, APK rilis | AC-01/02/04/06/07/08/09/11, UX-01, NF-06 ✅; AC-03, AC-10, NF-31 ⏳ |
| 2026-10-14 | 2 | SCR-01: Penghapus, Geser/zoom, warna/ketebalan, bilah alat bisa dipindah, P-02 | +AC-05, AC-20, AC-21, NF-04, A11Y-02/04 ✅; uji panel ⏳ |
| 2026-10-14 | 3 | SQLite, simpan otomatis, salinan otomatis, halaman (SCR-03), Daftar Papan (SCR-02), P-09/P-10 | +AC-22–27, AC-30–35, NF-05, UX-02/03/09 ✅ (81 test); uji panel ⏳ |
| 2026-10-14 | 4 | Bentuk (menu + Otomatis), Pilih (pindah/ubah ukuran/hapus), Gambar, latar PDF ≤ 5 halaman/gambar, pembersihan media, P-06/P-07/P-13 | +AC-40–45 ✅ (127 test); uji panel ⏳ |
| 2026-10-14 | 5 | Server FastAPI (PIN admin, penyedia, adaptor + cadangan Ollama, catatan), SCR-06 Pengaturan, keputusan P-05/P-11/P-12 | AC-77–82 (server), AC-90–99, NF-01, NF-01b, UX-06 ✅ (47 pytest + 161 test aplikasi); VPS ⏳ |
| 2026-10-14 | 6 | REQ-20 dari video: grafik interaktif + penggeser, AI vision (P-03), lasso Pilih, SCR-05 Asisten AI, objek teks | AC-70–74, AC-76, AC-84–88, NF-21 ✅; AC-83 ⏳ (butuh server nyata) |
| 2026-10-14 | 5 | Server dipasang di VPS: papan.karyabangsa.sch.id (systemd, nginx, Cloudflare Tunnel) | /sehat 200 lewat HTTPS ✅; kunci AI + PIN menunggu pemilik |
| 2026-10-14 | 6 | Kunci Ollama + PIN dipasang atas permintaan pemilik; model vision gemma4:31b (kimi-k3/glm-5.3-flash 402, mistral-large-4 403 di paket ini) | /koneksi 200; /ai/jalankan grafik & pecah_soal 200 lewat HTTPS ✅; uji panel ⏳ |
| 2026-10-14 | 6 | Perbaikan: APK rilis tidak punya izin INTERNET (Tes koneksi gagal di panel) → ditambahkan di manifest utama + test; APK uji dibangun ulang | aapt: uses-permission INTERNET ✅; Tes koneksi di panel ⏳ |
| 2026-10-15 | 6 | Uji awal Pix2Text MFR 1.5 (ONNX, CPU PC) + SymPy parse_latex pada 24 gambar font tulisan tangan | ±18/24 benar, ±0,45 dtk/gambar; gagal di √, log, tanda − pada font tanpa glyph; SymPy perlu daftar putih simbol (I terbaca sebagai bilangan imajiner) |
| 2026-10-15 | 6 | Server 0.6.0 di VPS: Jadikan grafik lewat pengenal rumus Pix2Text + SymPy (tanpa AI) | /koneksi 0.6.0 ✅; /ai/jalankan grafik 200 dalam 0,7–3 dtk lewat HTTPS ✅; tulisan tangan asli ⏳ |
| 2026-10-15 | 6 | Perbaikan: rumus yang ditulis berdekatan (baris bersentuhan) terbaca sebagai satu blok egin{matrix} dan ditolak → grafik/penggeser A,B hilang. `split_rows` memecah blok per baris; dipasang di VPS (cadangan /root/formula_math.py.bak-20261015) | 106 pytest ✅; uji publik baris bersentuhan → 2 rumus + A,B ✅; widget test baru: penggeser bisa digeser tepat setelah Tempel (Pilih) ✅ |
| 2026-10-15 | 6 | ux-flow 1.3 (pilihan pemilik dari video): bilah di bawah area dilingkari berisi "Jadikan grafik" yang langsung menempel grafik tanpa jendela; tombol cepat Asisten AI di samping area diganti (Asisten AI tetap di bilah atas) | board_graph_bar_test 8 ✅, board_ai_test 16 ✅; uji di panel ⏳ (APK baru) |
| 2026-10-15 | 6 | ux-flow 1.4: UI lebih profesional (bilah atas ringkas: ☰, judul, ikon simpan; Warna/Ketebalan/Pindah ikon saja). APK guru `dist/papan-tulis.apk` dibangun TANPA DIAGNOSTICS (alat ukur Isi goresan/FPS/Info panel hanya untuk APK diagnostik). Tema: Roboto eksplisit. Alat tangkapan layar `app/tool/screenshots_test.dart` | analyze bersih; test terdampak lolos; screenshot 1920×1080 `dist/tampilan-papan.png` |
| 2026-10-15 | 7 | Menu pintar + Rapikan rumus + Selesaikan (REQ-22), server 0.7.0 dipasang | AC-100–104 ✅ otomatis; uji publik HTTPS ✅; uji panel ⏳ |
| 2026-10-15 | 8–10 | Bangun ruang 3D, kimia + video, rekam kelas + ringkasan dibangun sekaligus | server 169 pytest ✅; aplikasi: geometri 22, papan 3D 8, kimia 6, rekam 8 test ✅; uji panel ⏳ |
| 2026-10-15 | 8–10 | Server 0.8.0 dipasang (cadangan `/root/papan-server-0.7.0-backup-20261015.tgz`; model Whisper small 464 MB di `server/models/whisper`; folder `server/video/` + katalog contoh kosong). APK `dist/papan-tulis.apk` (izin INTERNET + RECORD_AUDIO) | 261 test aplikasi ✅, 169 pytest ✅; uji HTTPS: kimia H2+O2→H2O disetarakan 1,7 dtk ✅, ringkasan rekaman 15 dtk selesai 11 dtk ✅; Whisper VPS ±0,33× durasi audio |
| 2026-10-15 | 11–14 | Simulasi fisika, kuis, lab kimia virtual, sketsa → 3D, kapur + tema papan | aplikasi 280 test ✅ (peraga 11, extras 8); server 172 pytest ✅; screenshot dicek; uji panel ⏳ |
| 2026-10-15 | 11–14 | Server 0.9.0 dipasang (cadangan `/root/papan-server-0.8.0-backup-20261015.tgz`); APK `dist/papan-tulis.apk` 53,2 MB | uji HTTPS kuis AI: 5 pasangan tepat dalam 8 dtk ✅ |
