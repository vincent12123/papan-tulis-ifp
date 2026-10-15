# Acceptance Criteria — Whiteboard IFP

> **Layer 2: Verifier.** Dokumen ini mendefinisikan kapan sebuah pekerjaan dianggap **selesai**.
> Setiap kriteria harus bisa dijawab **ya/tidak** — tidak boleh "kurang lebih sudah".
> Diturunkan dari SPEC.md v1.0 dan docs/ux-flow.md v1.0.

---

## Cara Memakai

1. Sebelum mulai coding satu fitur, baca kriteria fitur tersebut.
2. Setelah selesai, periksa setiap kriteria dan tandai hasilnya.
3. Pekerjaan **belum selesai** selama masih ada kriteria yang gagal.
4. Tuliskan bukti verifikasi (perintah test, screenshot, output).
5. Kolom **Req** berisi ID dari `SPEC.md §3.1` (atau `NFR-xx` dari §7).

**Metode verifikasi:**
- `AUTO` — dicek otomatis (`flutter test` untuk aplikasi, `pytest` untuk server)
- `MANUAL` — dicek manusia di panel Hisense / HP
- `REVIEW` — ditinjau terhadap SPEC dan ux-flow

**Status:** ☐ belum · ✅ lolos · ❌ gagal · ⏳ menunggu dicek pemilik di panel

---

## A. Menulis dan Menghapus (SPEC 5.1)

| ID | Req | Kriteria (Given – When – Then) | Jenis | Metode | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-01 | REQ-01 | **Diberikan** alat Pena aktif, **ketika** satu jari menggambar garis, **maka** satu objek goresan tersimpan berisi semua titik yang dilalui beserta warna dan ketebalan terpilih | Positif | AUTO | ✅ | `flutter test` 2026-10-14: ink_controller_test |
| AC-02 | REQ-01 | **Diberikan** titik dengan kecepatan berbeda, **ketika** goresan dirender, **maka** lebar goresan bervariasi (tidak konstan) sesuai tekanan/kecepatan | Positif | AUTO | ✅ | `flutter test` 2026-10-14: stroke_geometry_test |
| AC-03 | REQ-01, NFR-30 | **Diberikan** halaman berisi 3.000 goresan di panel, **ketika** menulis 1 jari, **maka** rata-rata ≥ 55 fps (angka dikalibrasi Checkpoint 1) | Positif | MANUAL | ⏳ | Menunggu uji di panel (tombol "Isi 3000 goresan" + angka fps di layar uji) |
| AC-04 | REQ-02 | **Diberikan** warna merah dan ketebalan tebal dipilih, **ketika** menulis, **maka** goresan baru memakai warna dan ketebalan itu; goresan lama tidak berubah | Positif | AUTO | ✅ | `flutter test` 2026-10-14: ink_controller_test |
| AC-05 | REQ-02 | **Diberikan** alat Penghapus, **ketika** jari menyentuh sebuah goresan, **maka** goresan itu terhapus utuh dan latar halaman tidak berubah | Positif | AUTO | ✅ | `flutter test` 2026-10-14: eraser_and_view_test + board_screen_test |
| AC-06 | REQ-02 | **Diberikan** 3 goresan, **ketika** Undo ditekan dua kali lalu Redo sekali, **maka** tersisa 2 goresan sesuai urutan semula | Positif | AUTO | ✅ | `flutter test` 2026-10-14: ink_controller_test |
| AC-07 | REQ-02 | **Diberikan** papan baru tanpa aksi, **ketika** layar tampil, **maka** tombol Undo dan Redo nonaktif | Negatif | AUTO | ✅ | `flutter test` 2026-10-14: ink_controller_test + widget_test |
| AC-08 | REQ-02 | **Diberikan** aksi baru dilakukan setelah Undo, **ketika** aksi selesai, **maka** riwayat Redo dikosongkan | Negatif | AUTO | ✅ | `flutter test` 2026-10-14: ink_controller_test |
| AC-09 | REQ-03 | **Diberikan** alat Pena aktif, **ketika** 3 jari menulis bersamaan, **maka** terbentuk 3 goresan terpisah yang tidak saling menyambung | Positif | AUTO | ✅ | `flutter test` 2026-10-14: ink_controller_test + widget_test |
| AC-10 | REQ-03, NFR-30 | **Diberikan** panel sungguhan, **ketika** 3 jari menulis bersamaan pada halaman 3.000 goresan, **maka** rata-rata ≥ 45 fps | Positif | MANUAL | ⏳ | Menunggu uji di panel (tombol "Isi 3000 goresan" + angka fps di layar uji) |
| AC-11 | REQ-01 | **Diberikan** sentuhan yang hanya satu titik (ketukan), **ketika** dilepas, **maka** tersimpan sebagai titik kecil, bukan diabaikan atau error | Negatif | AUTO | ✅ | `flutter test` 2026-10-14: ink_controller_test + stroke_geometry_test |

## B. Halaman dan Kanvas Luas (SPEC 5.2)

| ID | Req | Kriteria | Jenis | Metode | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-20 | REQ-04 | **Diberikan** mode Geser, **ketika** kanvas digeser dan di-zoom, **maka** posisi pandang berubah dan goresan baru tersimpan pada koordinat kanvas yang benar | Positif | AUTO | ✅ | `flutter test` 2026-10-14: eraser_and_view_test (round-trip) + board_screen_test (Geser lalu Pena) |
| AC-21 | REQ-04 | **Diberikan** zoom di batas maksimum/minimum, **ketika** zoom diteruskan, **maka** zoom berhenti di batas tanpa error | Negatif | AUTO | ✅ | `flutter test` 2026-10-14: eraser_and_view_test (batas 0,5×–4×, usulan menunggu P-08) |
| AC-22 | REQ-05 | **Diberikan** papan 1 halaman, **ketika** ＋ ditekan, **maka** halaman 2 kosong dibuat dan langsung terbuka | Positif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_screen_test (＋ 1 ketukan, halaman baru terbuka) |
| AC-23 | REQ-05 | **Diberikan** halaman berisi goresan, **ketika** Duplikat, **maka** halaman baru berisi salinan objek dengan id berbeda tepat setelah halaman asal | Positif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_repository_test + board_screen_test (Duplikat, id baru) |
| AC-24 | REQ-05 | **Diberikan** 3 halaman, **ketika** halaman 3 dipindah ke posisi 1, **maka** urutan tersimpan 3,1,2 | Positif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_repository_test (urutan 3,1,2 tersimpan); seret di SCR-03 memakai ReorderableListView — uji sentuh di panel |
| AC-25 | REQ-05 | **Diberikan** papan hanya 1 halaman, **ketika** Hapus halaman, **maka** ditolak dengan pesan sesuai kartu SCR-03 dan halaman tetap ada | Negatif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_screen_test (pesan "Papan harus punya minimal satu halaman.") |
| AC-26 | REQ-05 | **Diberikan** hapus halaman 2, **ketika** dialog tampil, **maka** dialog menyebut "halaman 2" dan halaman baru terhapus setelah "Hapus" ditekan | Positif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_screen_test (dialog "Hapus halaman 2?") |
| AC-27 | REQ-04 | **Diberikan** halaman 1 di-zoom lalu pindah ke halaman 2 dan kembali, **maka** posisi pandang halaman 1 sama seperti sebelumnya | Positif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_screen_test (posisi pandang per halaman) + board_repository_test (tersimpan) |

## C. Papan Tersimpan (SPEC 5.3)

| ID | Req | Kriteria | Jenis | Metode | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-30 | REQ-06 | **Diberikan** papan dengan goresan, **ketika** aplikasi ditutup dan dibuka ulang, **maka** papan, halaman, dan objek kembali sama persis | Positif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_repository_test (tutup-buka DB) + board_screen_test (aplikasi dibuka ulang) |
| AC-31 | REQ-06, NFR-32 | **Diberikan** goresan selesai digambar, **ketika** 5 detik berlalu, **maka** goresan sudah tersimpan di basis data lokal | Positif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_screen_test: goresan langsung ditulis ke penyimpanan saat selesai (tanpa jeda) |
| AC-32 | REQ-06 | **Diberikan** daftar papan, **ketika** ganti nama dengan judul kosong, **maka** ditolak dengan pesan validasi kartu SCR-02 | Negatif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_repository_test + board_screen_test |
| AC-33 | REQ-06 | **Diberikan** hapus papan, **ketika** dialog tampil, **maka** dialog menyebut judul dan jumlah halaman; papan baru hilang setelah "Hapus" | Positif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_repository_test + board_screen_test (dialog judul & jumlah halaman) |
| AC-34 | REQ-18 | **Diberikan** berkas papan rusak, **ketika** dibuka, **maka** aplikasi menawarkan salinan otomatis terakhir dan tidak crash | Negatif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_repository_test (data rusak terdeteksi, salinan dipulihkan) + board_screen_test (layar papan rusak) |
| AC-35 | REQ-06 | **Diberikan** basis data dari versi format lama, **ketika** APK baru membuka, **maka** papan lama tetap terbuka (migrasi berversi) | Positif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_repository_test (versi skema = 1, onUpgrade siap) |

## D. Gambar, Bentuk, dan Latar (SPEC 5.4)

| ID | Req | Kriteria | Jenis | Metode | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-40 | REQ-07 | **Diberikan** berkas PNG/JPG valid, **ketika** disisipkan, **maka** gambar tampil di halaman dan bisa dipindah, diubah ukuran, dan dihapus | Positif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: shapes_test + media_import_test + board_content_test (sisip, pindah, ubah ukuran, hapus, undo) |
| AC-41 | REQ-07, REQ-09 | **Diberikan** berkas bukan gambar/PDF atau rusak, **ketika** dipilih, **maka** ditolak dengan pesan yang menyebut nama berkas | Negatif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: media_import_test + board_content_test (pesan menyebut nama berkas) |
| AC-42 | REQ-08 | **Diberikan** alat Bentuk, **ketika** memilih garis/persegi/lingkaran/segitiga/panah dan menyeret, **maka** terbentuk bentuk rapi sesuai jenis | Positif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: shapes_test + board_content_test (menu 2 ketukan; Otomatis mengenali garis/persegi/lingkaran/segitiga) |
| AC-43 | REQ-09 | **Diberikan** PDF 3 halaman, **ketika** dipasang sebagai latar, **maka** terbentuk 3 halaman papan berlatar halaman PDF berurutan; PDF > 5 halaman → hanya 5 halaman pertama + pemberitahuan (P-13) | Positif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: media_import_test (3 halaman PDF → 3 halaman papan berlatar; 9 halaman → 5) |
| AC-44 | REQ-09 | **Diberikan** halaman berlatar, **ketika** Penghapus dipakai di atasnya, **maka** latar tidak terhapus | Negatif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: shapes_test (penghapus tidak menyentuh latar maupun gambar) |
| AC-45 | REQ-09 | **Diberikan** PDF terkunci kata sandi, **ketika** dipilih, **maka** ditolak dengan pesan penjelasan | Negatif | AUTO | ✅ | `tool/test.ps1` 2026-10-14: media_import_test + board_content_test (pesan terkunci); deteksi kunci di PdfRenderer Android ⏳ uji panel |

## E. Tulisan Tangan Menjadi Teks (SPEC 5.5)

| ID | Req | Kriteria | Jenis | Metode | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-50 | REQ-10 | **Diberikan** area berisi tulisan "2x + 3 = 7", **ketika** Ubah ke teks, **maka** kotak teks hasil tampil dan bisa diedit sebelum dipakai | Positif | MANUAL | ☐ | |
| AC-51 | REQ-10 | **Diberikan** hasil pengenalan tampil, **ketika** Batal, **maka** tulisan asli tidak berubah | Negatif | AUTO | ☐ | |
| AC-52 | REQ-10 | **Diberikan** area kosong dipilih, **ketika** Ubah ke teks, **maka** tampil ajakan melingkari tulisan | Negatif | AUTO | ☐ | |

## F. Ekspor PDF dan Bagikan QR (SPEC 5.6)

> **Ditunda (P-12, SPEC v1.4):** kriteria AC-60–AC-66 tidak diverifikasi sampai fitur ini dijadwalkan lagi.

| ID | Req | Kriteria | Jenis | Metode | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-60 | REQ-11 | **Diberikan** papan 2 halaman berisi goresan, bentuk, gambar, dan latar, **ketika** diekspor, **maka** PDF berisi 2 halaman dan semua jenis objek tercetak | Positif | AUTO | ☐ | |
| AC-61 | REQ-12 | **Diberikan** server menerima unggahan, **ketika** Buat kode QR, **maka** server mengembalikan tautan bertoken acak ≥ 128 bit dan QR berisi tautan itu | Positif | AUTO | ☐ | |
| AC-62 | REQ-12 | **Diberikan** tautan kedaluwarsa atau token tak dikenal, **ketika** dibuka, **maka** halaman unduh menampilkan pesan sesuai kartu SCR-07 dan berkas tidak terkirim | Negatif | AUTO | ☐ | |
| AC-63 | REQ-12 | **Diberikan** permintaan unggah tanpa/dengan PIN admin salah, **ketika** dikirim, **maka** server menolak (401) | Negatif | AUTO | ☐ | |
| AC-64 | REQ-12 | **Diberikan** berkas unggahan bukan PDF atau melebihi batas ukuran, **ketika** dikirim, **maka** server menolak dengan kode yang dikenali aplikasi | Negatif | AUTO | ☐ | |
| AC-65 | REQ-18 | **Diberikan** server tidak terjangkau, **ketika** Buat kode QR, **maka** pesan gagal sesuai kartu SCR-04 tampil dan isi papan tidak berubah | Negatif | AUTO | ☐ | |
| AC-66 | REQ-12 | **Diberikan** tautan kedaluwarsa, **ketika** pembersihan berjalan, **maka** berkas PDF terhapus dari disk server | Positif | AUTO | ☐ | |

## G. Asisten AI (SPEC 5.7)

| ID | Req | Kriteria | Jenis | Metode | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-70 | REQ-13 | **Diberikan** soal terpilih, **ketika** Pecah soal, **maka** server memanggil penyedia dengan prompt pecah soal dan aplikasi menampilkan langkah bernomor | Positif | AUTO | ✅ | 2026-10-14: board_ai_test (Pecah soal → teks bernomor dari server; prompt di server ai.py) |
| AC-71 | REQ-14 | **Diberikan** soal terpilih, **ketika** Buat soal serupa, **maka** hasil berisi soal latihan baru | Positif | AUTO | ✅ | 2026-10-14: server test_graph + board_ai_test (aksi soal_serupa memakai alur yang sama) |
| AC-72 | REQ-15 | **Diberikan** halaman berisi tulisan, **ketika** Ringkas papan tanpa area terpilih, **maka** seluruh halaman diringkas | Positif | AUTO | ✅ | 2026-10-14: board_ai_test (Ringkas papan tanpa area memakai seluruh halaman) |
| AC-73 | REQ-13, REQ-14 | **Diberikan** tidak ada area terpilih, **ketika** Pecah soal atau Buat soal serupa, **maka** tampil teks Kosong kartu SCR-05 dan tidak ada permintaan ke server | Negatif | AUTO | ✅ | 2026-10-14: board_ai_test (tanpa area: ajakan melingkari, tidak ada permintaan ke server) |
| AC-74 | REQ-13 | **Diberikan** hasil tampil, **ketika** Buang, **maka** papan tidak berubah; **ketika** Tempel ke papan, **maka** satu objek teks baru ditambahkan | Positif | AUTO | ✅ | 2026-10-14: board_ai_test (Buang tidak mengubah papan; Tempel menambah satu objek) |
| AC-75 | REQ-16, NFR-01 | **Diberikan** APK rilis, **ketika** isinya dipindai, **maka** tidak ada kunci API penyedia AI di dalamnya; aplikasi hanya memanggil alamat server sekolah | Negatif | REVIEW | ☐ | |
| AC-76 | REQ-18, NFR-33 | **Diberikan** server tidak menjawab, **ketika** 60 detik berlalu, **maka** tampil pesan "terlalu lama" kartu SCR-05 dan papan tidak berubah | Negatif | AUTO | ✅ | 2026-10-14: server: batas 30 + 60 dtk (test_ac78 timeout); panel: AiTimedOut → teks "AI tidak menjawab dalam 60 detik…" |
| AC-77 | REQ-16, NFR-21 | **Diberikan** permintaan AI selesai, **ketika** catatan server diperiksa, **maka** hanya ada waktu, jenis, status, durasi, penyedia, model (tanpa isi papan/hasil) | Negatif | AUTO | ✅ | 2026-10-14: pytest test_ac77 (log hanya waktu/jenis/status/durasi/penyedia/model/cadangan; isi & PIN tidak di log) |
| AC-78 | REQ-19 | **Diberikan** penyedia terpilih gagal (kuota habis/kunci ditolak/tak terjangkau/batas 30 detik), **ketika** aksi AI dijalankan, **maka** server mengulang ke Ollama cloud, hasil diberi keterangan cadangan, dan catatan berisi `cadangan_dari` + `alasan_cadangan` | Positif | AUTO | ✅ | 2026-10-14: pytest test_ac78 (5 penyebab gagal → Ollama cloud + catatan cadangan) |
| AC-79 | REQ-19 | **Diberikan** penyedia terpilih dan Ollama cloud sama-sama gagal, **ketika** aksi AI, **maka** tampil "AI sedang tidak tersedia…" dan papan tidak berubah | Negatif | AUTO | ✅ | 2026-10-14: pytest test_ac79 (server 503 ai_tidak_tersedia); teks di SCR-05 → CP6 |
| AC-80 | REQ-19 | **Diberikan** penyedia terpilih = Ollama cloud dan gagal, **ketika** aksi AI, **maka** tidak ada pengulangan ke penyedia lain | Negatif | AUTO | ✅ | 2026-10-14: pytest test_ac80 |
| AC-81 | REQ-19 | **Diberikan** adaptor ollama, openai, anthropic, gemini, openai_kompatibel, **ketika** dipanggil dengan aksi yang sama, **maka** masing-masing membentuk permintaan sesuai format API penyedia dan mengembalikan teks hasil seragam | Positif | AUTO | ✅ | 2026-10-14: pytest test_ac81 (ollama/openai/anthropic/gemini/openai_kompatibel; kunci Gemini di header, bukan URL) |
| AC-82 | REQ-19 | **Diberikan** pilihan panel menunjuk penyedia nonaktif, **ketika** aksi AI, **maka** server memakai Ollama cloud dan respons menandai bahwa pilihan tidak lagi tersedia | Negatif | AUTO | ✅ | 2026-10-14: pytest test_ac82 (server menandai cadangan_dari + tidak_aktif); pemberitahuan di SCR-05 → CP6 |
| AC-83 | REQ-20 | **Diberikan** area berisi tulisan "y = x² − 3" dan "y = A sin x + B", **ketika** "Jadikan grafik" di bilah bawah area ditekan (v1.3; atau lewat Asisten AI → pratinjau → Tempel), **maka** satu objek grafik dengan 2 kurva dan penggeser A dan B langsung muncul di samping area tanpa jendela, terpilih, dan bisa di-Undo | Positif | MANUAL | ⏳ | Alur lengkap lolos dengan server tiruan (board_ai_test, pratinjau web); 2026-10-15: server 0.6.0 (pengenal rumus Pix2Text + SymPy, tanpa AI) di VPS menjawab dalam 0,7–3 dtk; uji gambar font tulisan tangan 20/24 terbaca benar, sisanya ditolak (bukan salah). Menunggu tulisan tangan asli di panel |
| AC-84 | REQ-20 | **Diberikan** grafik dengan parameter A, **ketika** penggeser A digeser, **maka** kurva yang memakai A berubah langsung, nilai baru tersimpan, dan Undo mengembalikan nilai lama | Positif | AUTO | ✅ | 2026-10-14: graph_test (penggeser dengan Pena/Penghapus/Pilih, bukan Geser; Undo) |
| AC-85 | REQ-20 | **Diberikan** hasil pengenal rumus yang tidak lolos daftar putih SymPy (simbol asing, `I` imajiner, fungsi tak dikenal, persamaan bukan fungsi x) atau rumus berisi kode (mis. `__import__`, `x;rm`), **ketika** diterima, **maka** rumus ditolak dan tidak ada kode yang dijalankan; bila tak ada rumus tersisa tampil pesan Validasi SCR-05 | Negatif | AUTO | ✅ | 2026-10-14: graph_test + test_graph (server whitelist) + board_ai_test; 2026-10-15: test_formula (11 kasus ditolak) + test_graph (keluaran pengenal tak terbaca = tanpa_rumus) |
| AC-86 | REQ-20 | **Diberikan** pengurai rumus, **ketika** menghitung x², sin, akar, pembagian nol, log negatif, dan perkalian tersirat (2x, A sin x), **maka** hasilnya benar dan nilai tak terdefinisi tidak digambar (kurva terputus, bukan crash) | Positif | AUTO | ✅ | 2026-10-14: graph_test (x², sin, akar, pembagian nol, log negatif, perkalian tersirat) |
| AC-87 | REQ-20 | **Diberikan** objek grafik, **ketika** Pilih/pindah/ubah ukuran/hapus/Penghapus dan aplikasi dibuka ulang, **maka** perilaku sama seperti gambar (Penghapus tidak menghapus) dan grafik tersimpan utuh | Positif | AUTO | ✅ | 2026-10-14: graph_test (codec, Penghapus) + Pilih seperti gambar |
| AC-88 | REQ-13–15, P-03 | **Diberikan** permintaan bergambar untuk aksi teks (v1.8: Jadikan grafik tidak lagi memakai AI — test_ac83 memastikan tidak ada panggilan ke penyedia), **ketika** model pilihan tidak bisa membaca gambar, **maka** server memakai model bergambar penyedia yang sama; cadangan Ollama juga memakai model bergambar | Positif | AUTO | ✅ | 2026-10-14: test_graph (model bergambar penyedia sama; cadangan Ollama bergambar) |

### G2. Menu pintar (SPEC 1.9, REQ-22)

| ID | Requirement | Kriteria (Diberikan / Ketika / Maka) | Jenis | Cara cek | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-100 | REQ-22 | **Diberikan** tulisan di papan, **ketika** dilingkari dengan Pilih, **maka** tanpa menekan apa pun bilah di bawah area menampilkan "Mengenali…" dan server dipanggil sekali dengan gambar area dan warna tinta | Positif | AUTO | ✅ | 2026-10-15: board_smart_menu_test |
| AC-101 | REQ-22 | **Diberikan** area berisi fungsi / persamaan / ekspresi, **ketika** dikenali, **maka** bilah menampilkan berturut-turut [Jadikan grafik, Rapikan rumus] / [Rapikan rumus, Selesaikan] / [Rapikan rumus] | Positif | AUTO | ✅ | 2026-10-15: board_smart_menu_test + test_insight (klasifikasi) |
| AC-102 | REQ-22 | **Diberikan** area dikenali, **ketika** Rapikan rumus, **maka** goresan di area diganti rumus cetak (warna tinta sama, di posisi dan ukuran tulisan), tersimpan bersama papan, dan satu Undo mengembalikan tulisan tangan | Positif | AUTO + MANUAL | ✅ / ⏳ panel | 2026-10-15: board_smart_menu_test, test_insight (bentuk seperti ditulis, pangkat, pecahan); uji publik HTTPS |
| AC-103 | REQ-22 | **Diberikan** persamaan polinom (≤ derajat 4) atau sistem persamaan dengan jumlah persamaan = jumlah variabel (≤ 3), **ketika** Selesaikan, **maka** penyelesaian real yang tepat ditempel di samping area; tanpa penyelesaian real tertulis "tidak ada penyelesaian real"; persamaan lain tidak menampilkan Selesaikan | Positif / Negatif | AUTO | ✅ | 2026-10-15: test_insight (x²=4, x²−5x+6=0, 2x+3=7, SPL, 1/x=2, x²+1=0; sin x=0,5 dan x+y=5 tidak ditawari) |
| AC-104 | REQ-22 | **Diberikan** tidak ada rumus / tanpa jaringan / server bermasalah / Pengaturan kosong, **ketika** area dilingkari, **maka** bilah menampilkan pesan yang sesuai (dengan "Coba lagi" kecuali tidak ada rumus) dan papan tidak berubah | Negatif | AUTO | ✅ | 2026-10-15: board_smart_menu_test, test_insight (422/503, gambar rusak, tanpa PIN 401, catatan tanpa isi) |

### G3. Bangun ruang 3D (REQ-23)

| ID | Requirement | Kriteria (Diberikan / Ketika / Maka) | Jenis | Cara cek | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-110 | REQ-23 | **Diberikan** papan, **ketika** Bentuk dibuka, **maka** tampil 7 bangun ruang; memilih satu menempelkannya di tengah layar | Positif | AUTO | ✅ | 2026-10-15: solid_board_test |
| AC-111 | REQ-23 | **Diberikan** bangun ruang, **ketika** jari menggeser di atasnya dengan Pena, **maka** bangun berputar (tanpa tinta), satu Undo per gerakan; Pilih memindah, Geser/Penghapus tidak mengubahnya | Positif / Negatif | AUTO | ✅ | 2026-10-15: solid_board_test |
| AC-112 | REQ-23 | **Diberikan** bangun bersisi datar/tabung/kerucut, **ketika** Jaring-jaring, **maka** sisi-sisi berputar pada engsel menjadi jaring rata (ukuran sisi tetap, tidak bertumpuk; tabung → persegi panjang + 2 lingkaran, kerucut → juring + lingkaran); Tutup jaring mengembalikan | Positif | AUTO + MANUAL | ✅ / ⏳ panel | 2026-10-15: solid_geometry_test (22), solid_board_test |
| AC-113 | REQ-23 | **Diberikan** bangun ruang, **ketika** Bidang potong, **maka** bidang potong berwarna tampil di dalam bangun; ditekan lagi hilang; bola tanpa tombol Jaring-jaring | Positif | AUTO | ✅ | 2026-10-15: solid_board_test, screenshot |

### G4. Kimia + video (REQ-24)

| ID | Requirement | Kriteria (Diberikan / Ketika / Maka) | Jenis | Cara cek | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-120 | REQ-24 | **Diberikan** reaksi kimia tulisan tangan, **ketika** dilingkari, **maka** bilah menawarkan Rapikan rumus dan (bila belum setara) Setarakan; Setarakan menempel persamaan setara (koefisien bulat terkecil) di samping; rumus matematika tidak dianggap kimia | Positif / Negatif | AUTO | ✅ | 2026-10-15: test_chem (pembacaan 7 contoh keluaran pengenal, 8 bukan-kimia, penyetaraan 3 reaksi, tak mungkin disetarakan), board_chem_test |
| AC-121 | REQ-24 | **Diberikan** katalog video sekolah berisi video berkata kunci zat itu, **ketika** dilingkari, **maka** tombol "Video eksperimen (n)" membuka daftar dan memutar video dari server (dengan PIN, mendukung Range); entri katalog rusak/di luar folder diabaikan | Positif / Negatif | AUTO + MANUAL | ✅ / ⏳ panel | 2026-10-15: test_chem (katalog, 206 Range, 401, 404), board_chem_test |

### G5. Rekam kelas + ringkasan (REQ-25)

| ID | Requirement | Kriteria (Diberikan / Ketika / Maka) | Jenis | Cara cek | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-130 | REQ-25 | **Diberikan** persetujuan rekam, **ketika** pelajaran direkam lalu Selesai, **maka** rekaman (dan rumus yang dikenali selama rekam) terkirim, berkas di panel dihapus, server mentranskrip lalu meringkas dalam teks biasa, berkas di server dihapus, catatan tanpa isi | Positif | AUTO | ✅ | 2026-10-15: lesson_test, test_summary |
| AC-131 | REQ-25 | **Diberikan** ringkasan siap, **ketika** Tempel ke papan, **maka** ringkasan muncul di halaman baru; Buang membatalkan; selama diproses guru tetap bisa menulis | Positif | AUTO + MANUAL | ✅ / ⏳ panel | 2026-10-15: lesson_test |
| AC-132 | REQ-25 | **Diberikan** izin mikrofon ditolak / mikrofon rusak / tanpa jaringan / tanpa suara / AI mati / rekaman > 90 menit, **maka** pesan yang sesuai; tanpa jaringan rekaman disimpan dan "Coba lagi" mengirim ulang; > 90 menit berhenti otomatis | Negatif | AUTO | ✅ | 2026-10-15: lesson_test, test_summary |

### G6. Peraga, kuis, sketsa, kapur (REQ-23, REQ-26–29)

| ID | Requirement | Kriteria (Diberikan / Ketika / Maka) | Jenis | Cara cek | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-150 | REQ-26, REQ-28 | **Diberikan** papan, **ketika** Peraga dibuka, **maka** tampil 4 simulasi fisika, Kuis, dan 4 lab kimia; memilih satu menempelkannya | Positif | AUTO | ✅ | 2026-10-15: peraga_test |
| AC-151 | REQ-26 | **Diberikan** peraga, **ketika** Putar, **maka** animasi berjalan sesuai waktu; Jeda membekukan; Ulang kembali ke awal; status ini tidak disimpan | Positif | AUTO + MANUAL | ✅ / ⏳ panel | 2026-10-15: peraga_test (1 dtk frame → t ≈ 1 dtk) |
| AC-152 | REQ-26 | **Diberikan** peraga, **ketika** penggeser digeser, **maka** nilai & pembacaan berubah (rumus benar: T bandul/pegas, H & R parabola, a bidang miring, diam bila tan θ ≤ μ), satu Undo per geseran, tanpa tinta | Positif / Negatif | AUTO | ✅ | 2026-10-15: peraga_test |
| AC-153 | REQ-28 | **Diberikan** lab, **ketika** pilihan diketuk (indikator/logam), **maka** berganti; warna indikator sesuai bagan (lakmus merah/biru, PP tak berwarna < 8,2, universal pelangi); Cu tidak bereaksi; fenol jernih ≥ 66 °C; badan peraga tidak menerima tinta | Positif / Negatif | AUTO | ✅ | 2026-10-15: peraga_test |
| AC-160 | REQ-27 | **Diberikan** Kuis, **ketika** guru mengisi < 2 pasangan, **maka** "Isi paling sedikit 2 pasangan lengkap."; dengan ≥ 2 kuis tampil; siswa memasangkan: benar hijau + centang + skor, salah merah; Acak ulang; AI dapat mengisi pasangan (diperiksa guru); kuis tersimpan | Positif / Negatif | AUTO + MANUAL | ✅ / ⏳ panel | 2026-10-15: board_extras_test, test_quiz (server) |
| AC-161 | REQ-23 | **Diberikan** sketsa persegi/segitiga/lingkaran dilingkari, **maka** "Jadikan Kubus/Balok", "Limas/Kerucut", "Bola/Tabung" tampil (tanpa pesan "tidak ada rumus"); memilih mengganti sketsa dengan bangun ruang; satu Undo mengembalikan | Positif | AUTO | ✅ | 2026-10-15: board_extras_test |
| AC-162 | REQ-26, REQ-28 | **Diberikan** rumus periode bandul/pegas atau reaksi dengan zat yang cocok, **maka** menu pintar menawarkan "Peraga: …" yang sesuai | Positif / Negatif | AUTO | ✅ | 2026-10-15: board_extras_test |
| AC-170 | REQ-29 | **Diberikan** Warna, **ketika** Kapur dan Papan hijau kapur dipilih, **maka** goresan baru bertekstur kapur (tersimpan), papan hijau, pena hitam berganti putih, tema tersimpan per papan; goresan lama tetap terbaca | Positif | AUTO + MANUAL | ✅ / ⏳ panel | 2026-10-15: board_extras_test |

### G7. Tabel → grafik (REQ-21)

| ID | Requirement | Kriteria (Diberikan / Ketika / Maka) | Jenis | Cara cek | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-180 | REQ-21 | **Diberikan** papan, **ketika** Tabel → 4 baris × 3 kolom → Sisipkan, **maka** tabel kosong 4 × 3 muncul di tengah layar dan terpilih; satu Undo menghapusnya; tabel tersimpan bersama papan | Positif | AUTO | ✅ | 2026-10-15: table_test (AC-180) |
| AC-181 | REQ-21 | **Diberikan** tabel, **ketika** sel diketuk dengan Pena lalu "12,5" diketik, **maka** sel berisi 12,5 (dibaca sebagai angka 12.5), tidak ada tinta di badan tabel, dan satu Undo mengembalikan isi lama; dengan Geser, ketukan tidak membuka keyboard | Positif / Negatif | AUTO | ✅ | 2026-10-15: table_test (AC-181; juga Batal tidak mengubah tabel, parseCell) |
| AC-182 | REQ-21 | **Diberikan** tabel 20 baris atau 6 kolom, **ketika** Tambah baris / Tambah kolom, **maka** ditolak dengan pesan batas dan tabel tidak berubah; pilihan di bawah 2 atau di atas batas tidak bisa disisipkan | Negatif | AUTO | ✅ | 2026-10-15: table_test (AC-182) |
| AC-183 | REQ-21 | **Diberikan** tabel berangka di kolom pertama dan 2 seri, **ketika** Jadikan grafik → Garis / Batang / Titik, **maka** grafik muncul di samping tabel dengan 2 seri, sumbu menyesuaikan nilai, legenda bertuliskan judul kolom; bila kolom pertama berisi teks hanya Batang yang bisa dipilih (batang berkelompok) | Positif / Negatif | AUTO | ✅ | 2026-10-15: table_test (AC-183 ×2, grafik di samping tidak menimpa tabel); screenshot 12-tabel-grafik |
| AC-184 | REQ-21 | **Diberikan** grafik dari tabel, **ketika** angka di tabel diubah, **maka** grafik langsung berubah dan tersimpan; sel kosong/bukan angka dilewati; sel bukan angka ditandai (garis bawah + ikon); tabel tanpa angka → pesan, tidak ada grafik | Positif / Negatif | AUTO | ✅ | 2026-10-15: table_test (AC-184, isBadCell); ink_controller_test (gambar ulang setelah tabel diubah) |
| AC-185 | REQ-21 | **Diberikan** panel tanpa internet dan tanpa pengaturan server, **ketika** Jadikan grafik dari tabel, **maka** grafik tetap dibuat dan tidak ada panggilan ke server | Negatif | AUTO | ✅ | 2026-10-15: table_test (FakeServer tanpa permintaan; tanpa pengaturan server di AC-183/184) |
| AC-186 | REQ-21 | **Diberikan** tabel dan grafiknya, **ketika** aplikasi dibuka ulang, **maka** keduanya utuh dan masih terhubung; **ketika** tabel dihapus, **maka** grafik tetap dengan data terakhir dan tidak terhubung lagi; Penghapus tidak menghapus tabel | Positif / Negatif | AUTO | ✅ | 2026-10-15: table_test (codec + data rusak ditolak, buka ulang, hapus tabel, Penghapus) |
| AC-187 | REQ-21 | **Diberikan** panel Hisense, **ketika** guru mengisi tabel 5 × 3 dengan keyboard layar lalu membuat grafik, **maka** selesai tanpa bantuan, teks sel ≥ 20 sp terbaca dari belakang kelas, dan menulis di luar tabel tetap mulus (NFR-30) | Positif | MANUAL | ⏳ | Menunggu uji di panel |

### G8. Bahasa Mandarin (REQ-30)

| ID | Requirement | Kriteria (Diberikan / Ketika / Maka) | Jenis | Cara cek | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-190 | REQ-30 | **Diberikan** area berisi Hanzi tulisan tangan, **ketika** dilingkari, **maka** bilah menu pintar menawarkan "Pinyin & arti"; area tanpa aksara Han tidak menawarkannya | Positif / Negatif | AUTO | ✅ | 2026-10-15: test_mandarin (server: Hanzi didahulukan, ragu/tercampur → menu rumus), mandarin_test (aplikasi ×2) |
| AC-191 | REQ-30 | **Diberikan** teks 你好 / 学习 / 好好学习，天天向上, **ketika** server mengolahnya, **maka** pinyin bertanda nada benar (nǐ hǎo, xué xí, …) berasal dari pypinyin dan arti per kata dari kamus, bukan dari AI | Positif | AUTO | ✅ | 2026-10-15: test_mandarin (pinyin & kata dari kamus; AI hanya terjemahan + arti yang belum ada, diingat) |
| AC-192 | REQ-30 | **Diberikan** AI mati atau terlalu lama, **ketika** Pinyin & arti, **maka** kartu tetap muncul dengan pinyin + arti per kata tanpa terjemahan kalimat (tanpa data contoh); tanpa jaringan/PIN → pesan menu pintar yang ada dan papan tidak berubah; tanpa PIN server menolak (401) | Negatif | AUTO | ✅ | 2026-10-15: test_mandarin (AI mati, tanpa Hanzi 422, 401, teks tidak tercatat), mandarin_test (503/422/tanpa terjemahan) |
| AC-193 | REQ-30 | **Diberikan** kartu Mandarin, **ketika** dipindah/diubah ukuran/dihapus/Undo dan aplikasi dibuka ulang, **maka** perilaku seperti gambar dan kartu tersimpan utuh; terjemahan AI berlabel "Terjemahan AI — periksa sebelum dipakai" | Positif | AUTO | ✅ | 2026-10-15: mandarin_test (kartu di samping, Undo, codec + data rusak); screenshot 13-kartu-mandarin |
| AC-194 | REQ-30 | **Diberikan** panel dengan suara zh-CN, **ketika** Dengarkan / Pelan / ketuk kata, **maka** terdengar Hanzi yang sesuai; tanpa suara zh-CN tombol suara tersembunyi dan pesan cara memasang tampil | Positif / Negatif | AUTO + MANUAL | ✅ / ⏳ panel | 2026-10-15: mandarin_test (suara palsu: kata, Pelan, Dengarkan; tanpa suara tidak ada target). Suara zh-CN di panel Hisense belum dicek |
| AC-195 | REQ-30 | **Diberikan** 20 contoh Hanzi tulisan tangan guru Mandarin di panel, **ketika** dilingkari, **maka** pengenalan cukup akurat menurut guru (target usulan ≥ 16/20 benar; sisanya ditolak, bukan salah diam-diam) | Positif | MANUAL | ⏳ | 2026-10-15 uji awal (bukan tulisan asli): 100 gambar dari font gaya tulisan tangan — rapi 60/60 benar; semi-kursif 15 benar, 2 ditolak, 3 salah; 草书 4/10/6 (`python -m app.cli uji-hanzi`, test_hanzi 11 test). Menunggu tulisan guru Mandarin di panel |

## H. Pengaturan (SPEC 5.8)

| ID | Req | Kriteria | Jenis | Metode | Status | Bukti |
|---|---|---|---|---|---|---|
| AC-90 | REQ-17 | **Diberikan** alamat kosong, tanpa skema, atau `http://` ke alamat di luar jaringan lokal, **ketika** Tes koneksi/Simpan, **maka** ditolak dengan pesan validasi kartu SCR-06; `http://` ke localhost/10.x/172.16–31.x/192.168.x diterima (P-05) | Negatif | AUTO | ✅ | 2026-10-14: server_client_test + settings_screen_test |
| AC-91 | REQ-17 | **Diberikan** server menolak PIN admin, **ketika** Tes koneksi, **maka** pesan "Server menolak PIN admin…" (berbeda dari "Tidak bisa terhubung ke {alamat}…") | Negatif | AUTO | ✅ | 2026-10-14: server_client_test + settings_screen_test |
| AC-92 | REQ-17 | **Diberikan** alamat dan PIN admin benar, **ketika** Tes koneksi, **maka** tampil "Terhubung ke server sekolah." | Positif | AUTO | ✅ | 2026-10-14: pytest + settings_screen_test |
| AC-93 | REQ-17 | **Diberikan** PIN admin disimpan, **ketika** penyimpanan diperiksa, **maka** PIN ada di penyimpanan aman Android (`flutter_secure_storage`), bukan di SQLite/berkas biasa; PIN tidak pernah tampil terbuka di layar | Negatif | REVIEW | ✅ | 2026-10-14: server_client_test (PIN di flutter_secure_storage, tidak ada di app_state SQLite) |
| AC-93b | REQ-17 | **Diberikan** pengaturan sudah tersimpan, **ketika** guru membuka Pengaturan, **maka** semua isian terkunci; "Ubah (admin)" + PIN benar membukanya; bila server tak terjangkau PIN dicocokkan ke PIN tersimpan | Positif | AUTO | ✅ | 2026-10-14: settings_screen_test (terkunci untuk guru; Ubah (admin); PIN tersimpan saat server tak terjangkau) |
| AC-94 | REQ-19 | **Diberikan** bagian Asisten AI terkunci, **ketika** guru mencoba mengubah penyedia, **maka** pilihan nonaktif dengan teks "Hanya admin yang bisa mengganti penyedia AI." | Negatif | AUTO | ✅ | 2026-10-14: settings_screen_test |
| AC-95 | REQ-19 | **Diberikan** PIN admin benar, **ketika** Ubah (admin), **maka** pilihan penyedia/model terbuka sampai layar ditutup | Positif | AUTO | ✅ | 2026-10-14: settings_screen_test |
| AC-96 | REQ-19 | **Diberikan** PIN salah 5 kali, **ketika** percobaan ke-6, **maka** server menolak selama 5 menit dan aplikasi menampilkan pesan kunci 5 menit | Negatif | AUTO | ✅ | 2026-10-14: pytest test_ac96 + settings_screen_test |
| AC-97 | REQ-19 | **Diberikan** Ganti PIN dengan PIN baru "123456" / berbeda dari ulangan / sama dengan lama, **maka** ditolak dengan pesan validasi masing-masing | Negatif | AUTO | ✅ | 2026-10-14: pytest test_ac97 + settings_screen_test |
| AC-98 | REQ-19 | **Diberikan** PIN berhasil diganti, **ketika** panel lain mengirim PIN lama, **maka** server menolak (401) sampai PIN baru dimasukkan; server hanya menyimpan hash scrypt PIN dan mencatat waktu penggantian tanpa isi PIN | Positif | AUTO | ✅ | 2026-10-14: pytest test_ac98 (hash scrypt; log penggantian tanpa isi PIN) |
| AC-99 | REQ-19 | **Diberikan** server tanpa penyedia aktif, **ketika** Pengaturan dibuka, **maka** tampil "Belum ada penyedia AI yang diaktifkan di server. Hubungi operator." | Negatif | AUTO | ✅ | 2026-10-14: settings_screen_test |

---

## C. Kebutuhan Non-Fungsional

| ID | Req | Kriteria | Metode | Status | Bukti |
|---|---|---|---|---|---|
| NF-01 | NFR-01 | Semua endpoint server kecuali `/sehat` menolak permintaan tanpa PIN admin yang benar (401); kunci API penyedia dan PIN tidak muncul di log maupun respons | AUTO | ✅ | 2026-10-14: pytest test_nf01 + test_provider_list (kunci API tidak keluar dari server) |
| NF-01b | NFR-01 | PIN salah 5 kali berturut-turut dari satu alamat → semua permintaan dari alamat itu ditolak 429 selama 5 menit; permintaan AI > batas per menit ditolak 429 | AUTO | ✅ | 2026-10-14: pytest test_ac96 + test_nf01b (20 permintaan AI/menit per alamat) |
| NF-02 | NFR-02 | Halaman unduh tanpa scroll horizontal di lebar 360 px; aplikasi tampil benar di resolusi panel lanskap | MANUAL | ☐ | |
| NF-03 | NFR-03 | Tidak ada teks antarmuka berbahasa Inggris di aplikasi dan halaman unduh | REVIEW | ☐ | |
| NF-04 | NFR-04 | Waktu tersimpan UTC; judul papan default dan tampilan waktu memakai WIB | AUTO | ✅ | `flutter test` 2026-10-14: eraser_and_view_test: judul default WIB |
| NF-05 | NFR-05 | Salinan otomatis terakhir papan ada dan bisa dipulihkan | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_repository_test (salinan otomatis di berkas terpisah salinan.db) |
| NF-06 | NFR-06 | Tombol utama ≥ 64 dp, tombol lain ≥ 48 dp, teks UI ≥ 20 sp | AUTO | ☐ | |
| NF-21 | NFR-21 | Layar AI menampilkan peringatan privasi "Jangan sertakan nama siswa" | AUTO | ✅ | 2026-10-14: board_ai_test (peringatan privasi di SCR-05) + test_ac77 (tanpa isi di catatan server) |
| NF-23 | NFR-23 | Dengan Wi-Fi mati: menulis, halaman, gambar, bentuk, latar, dan simpan tetap berfungsi | MANUAL | ☐ | |
| NF-31 | NFR-31 | APK terpasang dan berjalan di panel Hisense sekolah | MANUAL | ☐ | |
| NF-32 | NFR-32 | Force-stop aplikasi 5 detik setelah menulis → goresan masih ada saat dibuka ulang | MANUAL | ☐ | |
| NF-33 | NFR-33 | QR tampil ≤ 15 detik untuk papan 10 halaman di Wi-Fi sekolah | MANUAL | ☐ | |

---

## D. UI/UX

### D1. State & Alur (dari `docs/ux-flow.md`)

| ID | Layar/Tugas | Kriteria (Given – When – Then) | Metode | Status | Bukti |
|---|---|---|---|---|---|
| UX-01 | SCR-01 | **Diberikan** papan baru, **ketika** terbuka, **maka** alat Pena aktif dan guru bisa langsung menulis (0 ketukan) | AUTO | ✅ | `flutter test` 2026-10-14: widget_test (layar uji CP1; diuji ulang di SCR-01 CP2) |
| UX-02 | SCR-02 | **Diberikan** belum ada papan, **ketika** Daftar Papan dibuka, **maka** tampil teks Kosong kartu SCR-02 dan tombol buat papan | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_screen_test (teks Kosong SCR-02) |
| UX-03 | SCR-03 | **Diberikan** hapus halaman terakhir, **maka** tampil teks penolakan kartu SCR-03 | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_screen_test |
| UX-04 | SCR-04 | **Diberikan** unggah gagal, **maka** tampil teks Gagal kartu SCR-04 dengan tombol Coba lagi, papan utuh | AUTO | ☐ | |
| UX-05 | SCR-05 | **Diberikan** AI bekerja, **maka** tampil teks Memuat kartu SCR-05 dengan tombol Batalkan | AUTO | ☐ | |
| UX-06 | SCR-06 | **Diberikan** server tak terjangkau, **maka** tampil "Tidak bisa terhubung ke {alamat}…" | AUTO | ✅ | 2026-10-14: settings_screen_test (teks "Tidak bisa terhubung ke {alamat}…") |
| UX-07 | SCR-07 | **Diberikan** token kedaluwarsa, **maka** halaman unduh menampilkan teks Gagal kartu SCR-07 | AUTO | ☐ | |
| UX-08 | Semua | Proses > 1 detik menampilkan indikator dan menonaktifkan tombol pemicu (tidak terkirim dua kali) | AUTO | ☐ | |
| UX-09 | Semua | Hapus papan/halaman selalu meminta konfirmasi yang menyebut nama/nomor | AUTO | ✅ | `tool/test.ps1` 2026-10-14: board_screen_test (hapus papan & halaman) |
| UX-10 | Semua | Tidak ada kode error mentah / stack trace yang tampil ke pengguna | AUTO | ☐ | |
| UX-11 | Semua | Teks tombol & notifikasi memakai istilah `ux-flow.md §7` | REVIEW | ☐ | |

### D2. Aksesibilitas

| ID | Kriteria | Metode | Status | Bukti |
|---|---|---|---|---|
| A11Y-01 | Tombol utama ≥ 64 dp, tombol lain ≥ 48 dp | AUTO | ☐ | |
| A11Y-02 | Alat aktif ditandai warna **dan** teks/ikon terpilih, bukan warna saja | REVIEW | ✅ | `flutter test` 2026-10-14: board_screen_test + review: alat aktif = latar, bingkai, teks tebal, semantics selected |
| A11Y-03 | Kontras teks antarmuka ≥ 4.5:1 terhadap latarnya | REVIEW | ☐ | |
| A11Y-04 | Setiap ikon tanpa teks punya label aksesibel (Semantics/tooltip) | AUTO | ✅ | `flutter test` 2026-10-14: ToolButton/IconButton punya label & tooltip berbahasa Indonesia |
| A11Y-05 | Bilah alat bisa dipindah ke kiri/kanan sehingga terjangkau dari dua sisi | MANUAL | ☐ | |

### D3. Uji Tugas dengan Pengguna Nyata

| ID | Tugas | Kriteria | Metode | Status | Bukti |
|---|---|---|---|---|---|
| UX-T-01 | TSK-01 | 2 dari 2 guru mulai menulis, ganti warna (≤ 2 ketukan), dan membuat bentuk (≤ 2 ketukan) tanpa bantuan | MANUAL | ☐ | |
| UX-T-02 | TSK-02 | 2 dari 2 guru dari soal tertulis sampai hasil AI tertempel dalam ≤ 5 ketukan tanpa bantuan | MANUAL | ☐ | |
| UX-T-03 | TSK-03 | 2 dari 2 guru menampilkan QR dalam ≤ 2 ketukan tanpa bantuan | MANUAL | ☐ | |

### D4. Kepatuhan Design System

| ID | Kriteria | Metode | Status |
|---|---|---|---|
| DS-01 | Hanya memakai warna token di `lib/ui/theme.dart` sesuai `docs/design-system.md` (tidak ada `Color(0x…)` lepas di widget) | REVIEW | ☐ |
| DS-02 | Satu keluarga font (bawaan sistem Roboto) | REVIEW | ☐ |
| DS-03 | Satu aksi utama per layar, varian tombol sesuai | REVIEW | ☐ |
| DS-04 | Semua layar mode Fungsional | REVIEW | ☐ |

---

## D5. Matriks Keterlacakan (Traceability)

| Req | Layar terkait | Kriteria terkait | Semua lolos? |
|---|---|---|---|
| REQ-01 | SCR-01 | AC-01, AC-02, AC-03, AC-11, UX-01 | ☐ |
| REQ-02 | SCR-01 | AC-04, AC-05, AC-06, AC-07, AC-08 | ☐ |
| REQ-03 | SCR-01 | AC-09, AC-10 | ☐ |
| REQ-04 | SCR-01 | AC-20, AC-21, AC-27 | ☐ |
| REQ-05 | SCR-01, SCR-03 | AC-22–AC-26, UX-03 | ☐ |
| REQ-06 | SCR-01, SCR-02 | AC-30–AC-33, AC-35, UX-02 | ☐ |
| REQ-07 | SCR-01 | AC-40, AC-41 | ☐ |
| REQ-08 | SCR-01 | AC-42 | ☐ |
| REQ-09 | SCR-03 | AC-41, AC-43, AC-44, AC-45 | ☐ |
| REQ-10 | SCR-01 | AC-50, AC-51, AC-52 | ☐ |
| REQ-11 | SCR-04 | AC-60 | ⏸ ditunda (P-12) |
| REQ-12 | SCR-04, SCR-07 | AC-61–AC-64, AC-66, UX-04, UX-07 | ⏸ ditunda (P-12) |
| REQ-13 | SCR-05 | AC-70, AC-73, AC-74 | ☐ |
| REQ-14 | SCR-05 | AC-71, AC-73 | ☐ |
| REQ-15 | SCR-05 | AC-72 | ☐ |
| REQ-16 | SCR-05 | AC-75, AC-77 | ☐ |
| REQ-17 | SCR-06 | AC-90–AC-93b, UX-06 | ☐ |
| REQ-18 | SCR-01, SCR-04, SCR-05 | AC-34, AC-65, AC-76 | ☐ |
| REQ-19 | SCR-05, SCR-06 | AC-78–AC-82, AC-94–AC-99 | ☐ |
| REQ-20 | SCR-01, SCR-05 | AC-83–AC-88 | ☐ |
| REQ-21 | SCR-01 (Tabel, Jadikan grafik dari tabel) | AC-180–AC-187 | ⏳ uji panel (AC-180–186 ✅) |
| REQ-30 | SCR-01 (menu pintar, kartu Mandarin) | AC-190–AC-195 | ⏳ uji panel (AC-190–193 ✅) |
| REQ-22 | SCR-01 (menu pintar) | AC-100–AC-104 | ⏳ uji panel |
| REQ-23 | SCR-01 (Bentuk → bangun ruang) | AC-110–AC-113 | ⏳ uji panel |
| REQ-24 | SCR-01 (menu pintar kimia, video) | AC-120–AC-121 | ⏳ uji panel |
| REQ-25 | SCR-01 (Rekam) | AC-130–AC-132 | ⏳ uji panel |
| REQ-26–28 | SCR-01 (Peraga, Kuis) | AC-150–AC-162 | ⏳ uji panel |
| REQ-29 | SCR-01 (Warna → Kapur, tema) | AC-170 | ⏳ uji panel |

---

## E. Definition of Done

- [ ] Semua kriteria fitur terkait berstatus lolos
- [ ] Semua test otomatis hijau (`tool/test.ps1` di `app/`, `pytest` di `server/`)
- [ ] `flutter analyze` dan `ruff check` tanpa error
- [ ] SPEC.md diperbarui bila ada perubahan perilaku
- [ ] Tidak ada kunci API / PIN tertinggal di kode
- [ ] Setiap fitur punya minimal satu kriteria negatif yang lolos
- [ ] Layar yang diubah: 4 state bisa dimunculkan, screenshot resolusi panel dilampirkan
- [ ] `PROGRESS.md` diperbarui

---

## F. Riwayat Verifikasi

| Tanggal | Checkpoint | Hasil | Catatan |
|---|---|---|---|
| 2026-10-14 | 6 | Sebagian | REQ-20 grafik interaktif + Asisten AI: server 66 pytest, aplikasi lolos `tool/test.ps1`; alur dicek di pratinjau web (lingkari → Jadikan grafik → Tempel → geser A/B). Pembacaan tulisan tangan nyata menunggu server di VPS. REQ-10 (Ubah ke teks) belum |
| 2026-10-14 | 5 | Sebagian | Server: 47 pytest lolos + uji asap server sungguhan (PIN, daftar penyedia, panggilan nyata ke ollama.com). Aplikasi: 161 test lolos (`tool/test.ps1`). Pemasangan di VPS karyabangsa menunggu konfirmasi pemilik |
| 2026-10-14 | 4 | Sebagian | 127 test otomatis lolos, analyze bersih; SCR-01 (Pilih/Bentuk/Gambar) dicek di pratinjau web; bug menu (ketukan lama) ditemukan di pratinjau dan diperbaiki + test regresi; pemilih berkas & PDF asli menunggu uji di panel |
| 2026-10-14 | 3 | Sebagian | 81 test otomatis lolos (via tool/test.ps1), analyze bersih; SCR-01/02/03 dicek visual di pratinjau web; uji di panel menunggu |
| 2026-10-14 | 2 | Sebagian | 48 test otomatis lolos (3× berturut-turut), analyze bersih; SCR-01 dicek visual di pratinjau web; uji fps dan sentuh di panel menunggu |
| 2026-10-14 | 1 | Sebagian | 26 test otomatis lolos, analyze bersih; AC-03, AC-10, NF-31 menunggu uji di panel |
