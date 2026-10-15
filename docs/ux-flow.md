# UX Flow — Whiteboard IFP

> **Layer 1: Spec (pengalaman pengguna).** Dokumen ini menjelaskan *bagaimana pengguna
> menyelesaikan tugasnya*: layar apa, urutan apa, dan apa yang tampil di setiap keadaan.
> Disusun setelah SPEC.md disepakati, sebelum kode tampilan ditulis.
> Layar yang belum berstatus **Disetujui** tidak boleh dikoding.
> Panduan pengisian: `references/panduan-ui-ux.md` di skill SDD.

- **Versi:** 1.9
- **Status:** Disetujui (SCR-06 v1.1: rincian usulan menunggu konfirmasi)
- **Mengacu SPEC versi:** 1.4

---

## 1. Pengguna & Konteks Pemakaian

| Peran | Perangkat utama | Lokasi/kondisi pakai | Kemampuan teknologi | Catatan |
|---|---|---|---|---|
| Guru | Panel Hisense IFP, layar sentuh besar lanskap (ukuran dan resolusi belum diketahui, SPEC P-01) | Berdiri di depan kelas, menghadap siswa, jari atau stylus | Beragam, termasuk guru senior | Tidak bisa menjangkau sisi atas layar besar; tangan sering sibuk (spidol, buku) |
| Siswa penulis | Panel yang sama | Maju ke depan, menulis singkat, mungkin beberapa orang bersamaan | Terbiasa layar sentuh | Hanya perlu menulis dan menghapus |
| Penerima PDF | HP pribadi, layar sekitar 360–430 px, peramban | Di tempat duduk, memindai QR dari layar panel | Terbiasa kamera dan peramban | Tidak memasang aplikasi dan tidak punya akun |
| Operator | Laptop | Kantor/ruang IT | Mahir teknis | Tidak punya layar khusus; hanya memakai Pengaturan di panel dan berkas konfigurasi server |

---

## 2. Tugas Utama (urut dari yang paling sering)

> Tugas tersering harus menjadi alur tercepat. Tugas ini juga dipakai untuk uji pengguna (UX-T).
> Angka target adalah usulan; dikonfirmasi saat uji di panel.

| ID | Peran | Tugas | Frekuensi | Target (langkah / waktu) | REQ terkait |
|---|---|---|---|---|---|
| TSK-01 | Guru | Mulai menulis materi di papan, termasuk membuat bentuk sederhana | Tiap pelajaran | 0 ketukan setelah aplikasi terbuka (papan terakhir langsung siap, bila P-10 disetujui); ganti warna atau ketebalan ≤ 2 ketukan; membuat satu bentuk ≤ 2 ketukan | REQ-01, REQ-02, REQ-04, REQ-06, REQ-08 |
| TSK-02 | Guru | Membahas soal dengan AI: tulis soal, lingkari, minta dipecah, tempel hasil | Beberapa kali per minggu | ≤ 5 ketukan dari soal tertulis sampai hasil tertempel di papan | REQ-10, REQ-13, REQ-14, REQ-15, REQ-16 |
| TSK-03 | Guru | Membagikan hasil papan ke HP siswa lewat QR | Tiap akhir pelajaran | ≤ 2 ketukan sampai kode QR tampil; QR tampil ≤ 15 detik; bila gagal, papan tetap utuh | REQ-11, REQ-12, REQ-18 |
| TSK-04 | Guru | Mengajar di atas PDF atau gambar latar | Beberapa kali per minggu | ≤ 4 ketukan dari papan kosong sampai PDF terpasang dan siap ditulisi | REQ-07, REQ-09 |
| TSK-05 | Siswa penulis | Menulis jawaban bersama di papan | Tiap pelajaran | Langsung menulis tanpa langkah tambahan; beberapa jari tidak saling mengganggu | REQ-03 |
| TSK-06 | Guru | Mengatur halaman: tambah, pindah, urutkan, hapus | Tiap pelajaran | Tambah halaman baru ≤ 1 ketukan; pindah halaman ≤ 2 ketukan | REQ-04, REQ-05 |
| TSK-07 | Guru | Membuka papan lama, mengganti nama, atau menghapus papan | Mingguan | Buka papan ≤ 2 ketukan dari papan mana pun | REQ-06 |
| TSK-08 | Operator / Guru | Menghubungkan aplikasi ke server sekolah (sekali di awal, atau saat kunci diganti) | Jarang | ≤ 4 langkah: buka Pengaturan, isi alamat, isi kunci, tes koneksi | REQ-17 |

---

## 3. Peta Layar (Sitemap)

```
[Papan SCR-01] ◄── layar yang langsung terbuka (papan terakhir, P-10)
 ├─ [Panel Halaman SCR-03]
 ├─ [Bagikan / QR SCR-04] ───► (HP siswa) [Halaman Unduh SCR-07]   ← ditunda (P-12)
 ├─ [Asisten AI SCR-05]
 └─ [Beranda: Daftar Papan SCR-02]
      └─ [Pengaturan SCR-06]
```

| ID Layar | Nama | Peran yang boleh membuka | Mode desain |
|---|---|---|---|
| SCR-01 | Papan | Guru, Siswa penulis | Fungsional |
| SCR-02 | Daftar Papan | Guru | Fungsional |
| SCR-03 | Panel Halaman | Guru | Fungsional |
| SCR-04 | Bagikan (kode QR) | Guru | Fungsional |
| SCR-05 | Asisten AI | Guru | Fungsional |
| SCR-06 | Pengaturan | Guru, Operator (perlindungan PIN menunggu P-11) | Fungsional |
| SCR-07 | Halaman Unduh (web di HP) | Penerima PDF | Fungsional |

> Semua layar bermode Fungsional: aplikasi pakai di kelas, bukan etalase. Yang diutamakan adalah kanvas yang lega, kontras tinggi, dan kecepatan tugas.

---

## 4. Alur per Tugas

### TSK-01 — Mulai menulis materi
```
Buka aplikasi → SCR-01 Papan (papan terakhir) → tulis dengan Pena → [ketuk warna/ketebalan bila perlu] → lanjut menulis
```
- **Jalan keluar:** Undo di bilah atas membatalkan goresan terakhir; Beranda membuka daftar papan tanpa kehilangan pekerjaan (simpan otomatis).
- **Pencegahan kesalahan:** Penghapus menghapus goresan utuh yang tersentuh dan bisa di-undo; tidak ada tombol "hapus semua" tanpa konfirmasi.

### TSK-02 — Membahas soal dengan AI
```
SCR-01 Papan → alat Pilih → lingkari soal → [Asisten AI] → SCR-05 pilih aksi (Pecah soal / Buat soal serupa / Ringkas papan) → AI bekerja → hasil tampil → [Tempel ke papan] → kembali ke SCR-01 + pesan berhasil
```
- **Jalan keluar:** Batalkan saat AI bekerja; Buang untuk menolak hasil; papan tidak berubah sampai Tempel ke papan ditekan.
- **Pencegahan kesalahan:** Tanpa area terpilih, aksi yang butuh soal tidak berjalan dan menampilkan ajakan melingkari soal; peringatan "periksa hasil AI" selalu tampil; peringatan privasi tampil di layar AI.

### TSK-03 — Membagikan hasil papan lewat QR
```
SCR-01 Papan → [Bagikan] → SCR-04 (pilih Semua halaman / Halaman ini) → [Buat kode QR] → PDF dibuat dan diunggah → QR tampil → siswa memindai → SCR-07 → [Unduh PDF]
```
- **Jalan keluar:** Tutup atau Batal kapan saja; membatalkan saat unggah tidak membuat tautan.
- **Pencegahan kesalahan:** QR menampilkan batas waktu berlaku; bila gagal, papan tetap aman.

### TSK-04 — Mengajar di atas PDF atau gambar
```
SCR-01 Papan → [Halaman] → SCR-03 → [Pasang latar] → pilih berkas → latar terpasang → kembali menulis
```
- **Jalan keluar:** Batal di pemilih berkas kembali ke SCR-03; Lepas latar tersedia di SCR-03.
- **Pencegahan kesalahan:** Berkas tidak valid ditolak dengan pesan yang menyebut nama berkas; penghapus tidak menghapus latar.

### TSK-05 — Siswa menulis jawaban bersama
```
SCR-01 Papan (alat Pena aktif) → beberapa siswa menulis bersamaan → guru menghapus/membatalkan bila perlu
```
- **Jalan keluar:** Undo oleh siapa pun yang memegang panel.
- **Pencegahan kesalahan:** Pena dan penghapus tidak terpengaruh sentuhan jari lain; sentuhan yang dibatalkan sistem (telapak) tidak meninggalkan tinta.

### TSK-06 — Mengatur halaman
```
SCR-01 → [＋] tambah halaman (1 ketukan) atau [Halaman] → SCR-03 → ketuk gambar mini untuk pindah / tombol Duplikat / Hapus / tahan-geser untuk urutkan
```
- **Jalan keluar:** Menutup SCR-03 kembali ke SCR-01; hapus halaman meminta konfirmasi.
- **Pencegahan kesalahan:** Halaman terakhir tidak bisa dihapus.

### TSK-07 — Mengelola papan
```
SCR-01 → [Beranda] → SCR-02 → ketuk papan untuk buka / ikon Ganti nama / ikon Hapus → konfirmasi
```
- **Jalan keluar:** Kembali ke papan yang sedang terbuka dengan satu ketukan.
- **Pencegahan kesalahan:** Hapus papan meminta konfirmasi yang menyebut judul dan jumlah halaman.

### TSK-08 — Menghubungkan aplikasi ke server
```
SCR-02 Daftar Papan → [Pengaturan] → SCR-06 → (sudah pernah diatur: [Ubah (admin)] → PIN) → isi alamat server dan PIN admin → [Tes koneksi] → hasil → [Simpan]
```
- **Peran:** Admin, sekali saat memasang aplikasi di panel (P-11: PIN admin menggantikan kunci perangkat).
- **Jalan keluar:** Kembali tanpa menyimpan; isian tidak hilang selama layar belum ditutup.
- **Pencegahan kesalahan:** Alamat wajib diawali https:// (http:// hanya untuk server lokal di jaringan sekolah); PIN disembunyikan; hasil tes membedakan "server tidak terjangkau" dari "PIN ditolak".

### TSK-09 — Memilih penyedia dan model AI (admin)
```
SCR-02 Daftar Papan → [Pengaturan] → SCR-06 bagian Asisten AI → [Ubah (admin)] → masukkan PIN admin → pilih Penyedia (daftar dari server) → pilih Model → [Tes AI] → hasil → [Simpan]
```
- **Peran:** Admin/operator. Guru hanya melihat penyedia yang sedang dipakai.
- **Jalan keluar:** Kembali tanpa menyimpan; penyedia lama tetap dipakai. Kunci admin terbuka hanya sampai layar Pengaturan ditutup.
- **Pencegahan kesalahan:** Hanya penyedia yang diaktifkan operator yang bisa dipilih (tahap awal: Ollama cloud saja); pilihan Model menyesuaikan penyedia; model tanpa dukungan gambar diberi keterangan "teks saja"; pilihan "Ikuti bawaan server (Ollama cloud)" selalu ada; keterangan tetap di bawah pilihan: "Bila penyedia ini gagal, AI otomatis memakai Ollama cloud."

### TSK-10 — Mengganti PIN admin (misalnya karena bocor)
```
SCR-06 Pengaturan → [Ubah (admin)] → masukkan PIN → [Ganti PIN admin] → isi PIN lama, PIN baru, ulangi PIN baru → [Ganti PIN] → pesan berhasil
```
- **Peran:** Admin.
- **Jalan keluar:** [Batal] menutup dialog; PIN lama tetap berlaku.
- **Pencegahan kesalahan:** Isian PIN disembunyikan dengan tombol lihat; PIN baru diketik dua kali; aturan PIN ditulis di bawah isian; bila PIN lupa atau sudah diganti orang lain, dialog menyebut jalan darurat: minta operator mengatur ulang lewat server.

---

## 5. Kartu Layar

> Satu kartu per layar. Teks di kolom state ditulis **persis** seperti yang akan tampil.
> Tanda `{…}` menandai nilai yang diisi aplikasi (judul, nomor, jam).

### SCR-01 — Papan

- **Status:** Disetujui
- **Tujuan:** Tempat guru dan siswa menulis di kanvas yang lega, dengan alat yang mudah dijangkau.
- **Aksi utama (satu):** Menulis dengan Pena (alat bawaan saat papan terbuka)
- **Aksi lain:** Penghapus, Pilih, Bentuk, Gambar, Teks, Geser, Undo, Redo, Warna dan Ketebalan, Halaman, Bagikan, Asisten AI, Beranda
- **Data yang tampil:** judul papan, status simpan (ikon awan bertanda centang = tersimpan; teks hanya saat "Menyimpan…" atau "Belum tersimpan"), nomor halaman di kontrol halaman kiri bawah ("Hlm 2/5"), isi halaman (v1.4)
- **Hak akses:** Guru dan siswa penulis (tanpa login)

**Wireframe (lanskap):**
```
┌────────────────────────────────────────────────────────────────────┐
│ ☰  {Judul papan}  ☁✓                        [ Asisten AI ]  ↶  ↷     │
│                                                                    │
│                                                                    │
│                      (kanvas luas — kosong)                        │
│                                                                    │
│                                                                    │
│  ◀ Hlm 2/5 ▶  [＋]                                                 │
│ ┌──────────────────────────────────────────────────────────────┐   │
│ │ ✎Pena  ⌫Penghapus  ⬚Pilih  △Bentuk  🖼Gambar  ✋Geser │ ● ━ │ ⇄ │   │
│ └──────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────┘
```
- Bilah alat berada di bawah tengah dan dapat dipindah ke kiri atau kanan layar agar terjangkau dari posisi berdiri (usulan).
- Bilah atas hanya memuat aksi yang jarang dipakai saat menulis.
- v1.4 (permintaan pemilik: tampilan profesional, tanpa kata yang tidak perlu): Beranda jadi ikon ☰ (keterangan "Beranda" saat ditahan), "Hlm x dari y" dihapus dari bilah atas karena sudah ada di kontrol halaman, "Tersimpan" jadi ikon awan. Di bilah alat, Warna, Ketebalan, dan Pindahkan bilah alat tampil sebagai ikon saja (label tetap sebagai keterangan dan untuk pembaca layar); alat tetap berlabel. Alat ukur uji (Isi goresan, FPS, Info panel) hanya ada di APK diagnostik, tidak di APK untuk guru.

**Gestur (diputuskan P-02, 2026-10-14):**

| Kondisi | Perilaku usulan |
|---|---|
| Alat Pena atau Penghapus aktif | Semua jari/stylus yang menyentuh menulis atau menghapus |
| Alat Geser aktif | Satu atau dua jari menggeser; cubit untuk zoom |
| Cubit dua jari di luar mode Geser | Tidak zoom; setiap jari menulis (P-02) |

| State | Yang tampil (teks persis) |
|---|---|
| Memuat | Kanvas redup dan teks "Membuka papan {judul}…" (ditampilkan bila lebih dari 1 detik) |
| Kosong | Petunjuk samar di tengah kanvas: "Halaman kosong. Mulai menulis dengan jari atau stylus." (hilang saat goresan pertama) |
| Gagal | Papan rusak: "Papan {judul} tidak bisa dibuka karena berkasnya rusak. Salinan otomatis terakhir pukul {jam} masih ada." dengan tombol "Pulihkan salinan" dan "Buat papan baru". Penyimpanan penuh: "Papan belum tersimpan karena ruang penyimpanan panel penuh. Hapus papan lama di Beranda, lalu lanjutkan menulis." |
| Berhasil | Indikator di bilah atas: "Tersimpan" (berubah dari "Menyimpan…"); tanpa pesan besar setiap simpan otomatis |
| Validasi | Ganti nama papan kosong: "Nama papan tidak boleh kosong." |

**Ditambahkan saat Checkpoint 4 (teks usulan AI, mohon dikonfirmasi):**
- Menu **Bentuk** (di atas bilah alat): Otomatis, Garis, Persegi, Lingkaran, Segitiga, Panah. Memilih jenis lalu menyeret = 2 ketukan (TSK-01). Otomatis: gambar bebas, dirapikan bila dikenali.
- **Pilih**: ketuk gambar/bentuk untuk memilih (bingkai biru + 4 pegangan sudut); seret isi untuk memindah, seret pegangan untuk mengubah ukuran (gambar tetap proporsional); tombol merah "Hapus" di samping bingkai.
- **Gambar**: membuka pemilih berkas panel; gambar diletakkan di tengah layar dan langsung terpilih (alat berpindah ke Pilih).
- Gagal Gambar: "{nama berkas} tidak bisa dipakai sebagai gambar. Pilih berkas gambar (PNG atau JPG) yang tidak rusak."

### SCR-02 — Daftar Papan

- **Status:** Disetujui
- **Tujuan:** Membuka kembali papan lama atau membuat papan baru.
- **Aksi utama (satu):** "Papan baru"
- **Aksi lain:** Buka papan, Ganti nama, Hapus papan, Pengaturan, Kembali ke papan
- **Data yang tampil:** gambar mini halaman pertama, judul, tanggal diubah, jumlah halaman
- **Hak akses:** Guru

**Wireframe:**
```
┌────────────────────────────────────────────────────────────┐
│ ← Kembali ke papan     Papan saya              ⚙ Pengaturan│
├────────────────────────────────────────────────────────────┤
│ [ ＋ Papan baru ]                                          │
│ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐            │
│ │ (mini)  │ │ (mini)  │ │ (mini)  │ │ (mini)  │            │
│ │ Mtk XI  │ │ Basis   │ │ ...     │ │ ...     │            │
│ │ 5 hlm   │ │ Data    │ │         │ │         │            │
│ │ ✎  🗑   │ │ ✎  🗑   │ │ ✎  🗑   │ │ ✎  🗑   │            │
│ └─────────┘ └─────────┘ └─────────┘ └─────────┘            │
└────────────────────────────────────────────────────────────┘
```

| State | Yang tampil (teks persis) |
|---|---|
| Memuat | Kotak-kotak abu bentuk kartu papan (skeleton) |
| Kosong | "Belum ada papan. Ketuk Papan baru untuk mulai menulis." |
| Gagal | "Daftar papan tidak bisa dimuat. Tutup dan buka aplikasi lagi. Bila terulang, hubungi operator IT sekolah." |
| Berhasil | Setelah hapus: "Papan {judul} dihapus." Setelah ganti nama: "Nama papan diubah." |
| Validasi | Ganti nama kosong: "Nama papan tidak boleh kosong." |

Dialog konfirmasi hapus: judul "Hapus papan {judul}?", isi "Seluruh {5} halamannya ikut terhapus dan tidak bisa dikembalikan." Tombol "Hapus" (bahaya) dan "Batal".

### SCR-03 — Panel Halaman

- **Status:** Disetujui
- **Tujuan:** Melihat semua halaman papan, berpindah, dan mengatur halaman.
- **Aksi utama (satu):** Ketuk gambar mini untuk pindah halaman
- **Aksi lain:** "Halaman baru", Duplikat, Hapus halaman, Pasang latar, Lepas latar, tahan-geser untuk mengubah urutan
- **Data yang tampil:** gambar mini tiap halaman, nomor halaman, penanda halaman yang sedang dibuka
- **Hak akses:** Guru

**Wireframe (panel dari tepi kiri):**
```
┌────────────┬───────────────────────────────┐
│ Halaman    │                               │
│ ┌────────┐ │                               │
│ │ 1 mini │ │       (papan di belakang)     │
│ └────────┘ │                               │
│ ┌────────┐ │                               │
│ │ 2 mini ◄ │  halaman terbuka              │
│ └────────┘ │                               │
│ [＋ Halaman baru]                           │
│ [Duplikat] [Pasang latar] [Hapus]          │
└────────────┴───────────────────────────────┘
```

| State | Yang tampil (teks persis) |
|---|---|
| Memuat | Kotak abu di tempat gambar mini |
| Kosong | Tidak terjadi: papan selalu punya minimal satu halaman |
| Gagal | "Gambar mini halaman {3} belum bisa dibuat. Halamannya tetap aman." |
| Berhasil | "Halaman {4} ditambahkan." / "Halaman {3} diduplikat." / "Latar terpasang di halaman {2}." / PDF banyak halaman: "Latar terpasang di halaman {2} sampai {6}." / "Latar halaman {2} dilepas." *(dua yang terakhir ditambahkan CP4, usulan)* |
| Validasi | Hapus halaman terakhir: "Papan harus punya minimal satu halaman." Berkas latar salah: "{nama berkas} tidak bisa dipakai sebagai latar. Pilih berkas PDF atau gambar yang tidak rusak." PDF terkunci *(CP4, usulan)*: "{nama berkas} terkunci kata sandi. Buka kuncinya dulu, lalu pilih lagi." PDF lebih dari 5 halaman *(CP4, P-13)*: pesan berhasil ditambah "{nama berkas} punya {n} halaman. Yang dipasang hanya 5 halaman pertama." (menetap sampai ditutup) |

Dialog konfirmasi hapus halaman: judul "Hapus halaman {3}?", isi "Tulisan dan gambar di halaman ini ikut terhapus." Tombol "Hapus" dan "Batal".

### SCR-04 — Bagikan (kode QR)

- **Status:** Disetujui
- **Tujuan:** Mengubah papan menjadi PDF dan menampilkan kode QR agar siswa mengunduhnya di HP.
- **Aksi utama (satu):** "Buat kode QR"
- **Aksi lain:** Pilih "Semua halaman" atau "Halaman ini saja", "Coba lagi", "Tutup"
- **Data yang tampil:** pilihan halaman, kemajuan pembuatan, kode QR besar, batas waktu berlaku
- **Hak akses:** Guru

**Wireframe:**
```
┌───────────────────────────────────────┐
│ Bagikan {Judul papan}             ✕   │
├───────────────────────────────────────┤
│ (•) Semua halaman  ( ) Halaman ini saja│
│                                       │
│          [ Buat kode QR ]             │
└───────────────────────────────────────┘

Setelah berhasil:
┌───────────────────────────────────────┐
│ Pindai dengan kamera HP           ✕   │
│            ███ QR besar ███           │
│ Berlaku sampai {jam}, {tanggal}.      │
│               [ Tutup ]               │
└───────────────────────────────────────┘
```

| State | Yang tampil (teks persis) |
|---|---|
| Memuat | "Menyiapkan PDF… halaman {3} dari {5}" lalu "Mengunggah ke server sekolah…" dengan tombol "Batal" |
| Kosong | Tidak terjadi: papan selalu punya isi untuk dicetak (halaman kosong tetap menghasilkan halaman PDF kosong) |
| Gagal | "PDF belum bisa dibagikan karena panel tidak terhubung ke server sekolah. Periksa Wi-Fi panel, lalu tekan Coba lagi. Papan Anda tetap aman." Bila berkas terlalu besar: "PDF terlalu besar untuk dibagikan. Pilih Halaman ini saja, atau kurangi gambar di papan." |
| Berhasil | "Pindai kode ini dengan kamera HP untuk mengunduh PDF. Berlaku sampai {jam}, {tanggal}." |
| Validasi | Tidak ada isian teks |

### SCR-05 — Asisten AI

- **Status:** Disetujui
- **Tujuan:** Membantu guru membahas soal dan merangkum papan dengan bantuan AI, dengan hasil yang dicek dulu sebelum masuk papan.
- **Aksi utama (satu):** "Tempel ke papan" (setelah hasil tampil); sebelum itu aksi dipilih dari empat pilihan
- **Aksi lain:** "Pecah soal", "Buat soal serupa", "Ringkas papan", "Jadikan grafik" (v1.2, REQ-20), "Batalkan", "Buang", "Coba lagi"
- **Data yang tampil:** area terpilih (gambar mini), penyedia dan model yang dipakai, daftar aksi, kemajuan, hasil teks **atau pratinjau grafik interaktif**, pengingat
- **Hak akses:** Guru

**Wireframe:**
```
┌──────────────────────────────────────────────┐
│ Asisten AI                               ✕   │
│ Memakai: {Claude (Anthropic)} · {nama model} │
├──────────────────────────────────────────────┤
│ Area terpilih: {soal tulisan tangan} ✓       │
│ [ Pecah soal ] [ Buat soal serupa ] [ Ringkas papan ]│
│ [ Jadikan grafik ]                           │
├──────────────────────────────────────────────┤
│ Hasil:                                       │
│  1. ...                                      │
│  2. ...                                      │
│ Periksa hasil AI sebelum dipakai mengajar.   │
│ [ Buang ]                  [ Tempel ke papan ]│
├──────────────────────────────────────────────┤
│ Isi area yang dipilih dikirim ke layanan AI  │
│ di internet. Jangan sertakan nama siswa.     │
└──────────────────────────────────────────────┘
```

| State | Yang tampil (teks persis) |
|---|---|
| Memuat | "AI sedang mengerjakan {memecah soal / membuat soal serupa / meringkas papan / membuat grafik}… Biasanya sampai 30 detik." dengan tombol "Batalkan" |
| Kosong | Tanpa area terpilih untuk Pecah soal / Buat soal serupa: "Lingkari soal di papan dulu dengan alat Pilih, lalu ketuk Asisten AI lagi." Tanpa area untuk Jadikan grafik: "Lingkari rumus di papan dulu dengan alat Pilih, lalu ketuk Asisten AI lagi." |
| Gagal | Koneksi: "AI belum bisa menjawab karena panel tidak terhubung ke server sekolah. Area Anda tidak berubah. Tekan Coba lagi." Pilihan dinonaktifkan operator: "{Penyedia lama} tidak lagi tersedia. AI memakai Ollama cloud untuk sementara." Penyedia terpilih dan Ollama cloud sama-sama gagal: "AI sedang tidak tersedia. Papan Anda tidak berubah. Coba lagi beberapa menit lagi." Terlalu lama: "AI tidak menjawab dalam 60 detik. Papan Anda tidak berubah. Tekan Coba lagi." PIN ditolak atau Pengaturan belum diisi: "Panel belum diizinkan memakai AI. Periksa PIN admin di Pengaturan." (v1.2: PIN admin menggantikan kunci perangkat, P-11) |
| Berhasil | Setelah ditempel: "Hasil AI ditempel di papan. Geser atau ubah sesuai kebutuhan." Bila dialihkan ke cadangan, di bawah hasil tampil keterangan kecil (bukan pesan gagal): "{Nama penyedia} sedang bermasalah, jadi jawaban ini dari Ollama cloud." |
| Validasi | Isi tidak terbaca: "AI tidak bisa membaca tulisan di area ini. Tulis lebih besar atau ubah dulu ke teks, lalu coba lagi." Jadikan grafik tanpa rumus fungsi yang bisa digambar: "AI tidak menemukan rumus fungsi yang bisa digambar di area ini. Tulis rumus seperti y = x² − 3, lalu coba lagi." |

**Grafik interaktif di papan (v1.2, REQ-20):** bidang koordinat berkotak dengan sumbu bernomor, kurva berwarna dari palet pena per rumus, legenda rumus, dan satu penggeser per parameter berlabel "{A} = {nilai}" di pojok kanan atas grafik. Penggeser ≥ 48 dp tinggi area sentuhnya; digeser dengan jari saat alat apa pun aktif kecuali Geser. Grafik dipindah/diubah ukuran/dihapus dengan Pilih.

### SCR-06 — Pengaturan

- **Status:** Disetujui
- **Tujuan:** Menghubungkan aplikasi ke server sekolah dan memilih penyedia AI.
- **Aksi utama (satu):** "Tes koneksi"
- **Aksi lain:** "Ubah (admin)", "Tes AI", "Ganti PIN admin" (hanya setelah kunci admin terbuka), "Simpan", "Kembali"
- **Data yang tampil:** alamat server, status PIN ("PIN tersimpan" / kosong), hasil tes, penyedia AI dan model (daftar dari server), hasil Tes AI, versi aplikasi
- **Hak akses:** Guru hanya melihat. Admin mengubah semua isian setelah "Ubah (admin)" + PIN admin (v1.1, P-11). Pada pemasangan pertama (belum ada pengaturan) isian langsung bisa diisi.

**Wireframe:**
```
┌───────────────────────────────────────┐
│ ← Pengaturan                          │
├───────────────────────────────────────┤
│ 🔒 Hanya admin yang bisa mengubah.     │
│                       [ Ubah (admin) ] │
│ Alamat server    [ https://...      ] │
│ PIN admin        [ ••••••           ] │
│ [ Tes koneksi ]                       │
├───────────────────────────────────────┤
│ Asisten AI                            │
│ Penyedia  [ Ollama cloud          ▾ ] │
│           Ikuti bawaan server /       │
│           Ollama cloud / OpenAI* /    │
│           Claude* / Gemini* / lainnya*│
│           (*tampil bila diaktifkan)   │
│ Model     [ {nama model}          ▾ ] │
│ Bila penyedia ini gagal, AI otomatis  │
│ memakai Ollama cloud.                 │
│ [ Tes AI ]                            │
│ [ Ganti PIN admin ]  (setelah dibuka) │
├───────────────────────────────────────┤
│ Versi aplikasi {1.0.0}                │
│                       [ Simpan ]      │
└───────────────────────────────────────┘
```

| State | Yang tampil (teks persis) |
|---|---|
| Memuat | "Menguji koneksi ke {alamat}…" / "Memuat daftar penyedia AI…" / "Menguji {nama penyedia}…" |
| Kosong | Isian kosong dengan contoh di bawah label: "Contoh: https://papan.sekolahanda.sch.id". Bagian Asisten AI sebelum terhubung: "Hubungkan ke server dulu untuk memilih penyedia AI." Server tanpa penyedia aktif: "Belum ada penyedia AI yang diaktifkan di server. Hubungi operator." Guru (belum membuka kunci admin): pilihan tampil abu-abu dengan teks "Hanya admin yang bisa mengganti penyedia AI." |
| Gagal | Server tidak terjangkau: "Tidak bisa terhubung ke {alamat}. Periksa alamat dan Wi-Fi panel." PIN ditolak: "Server menolak PIN admin. Periksa PIN, atau minta admin memasukkan PIN terbaru." Tes AI gagal: "{Nama penyedia} tidak menjawab: {penyebab singkat, mis. kuota habis / model tidak ditemukan / kunci API di server ditolak}. Saat dipakai mengajar, AI akan otomatis memakai Ollama cloud." PIN salah: "PIN admin salah." Terlalu banyak salah: "PIN salah 5 kali. Coba lagi dalam 5 menit." Ganti PIN, PIN lama salah: "PIN lama salah. PIN admin tidak berubah." Ganti PIN, server tidak terjangkau: "PIN belum diganti karena panel tidak terhubung ke server. Coba lagi." |
| Berhasil | "Terhubung ke server sekolah." / Tes AI: "{Nama penyedia} · {model} menjawab dalam {n} detik." / Simpan: "Pengaturan disimpan. Asisten AI memakai {nama penyedia}." / Ganti PIN: "PIN admin sudah diganti. PIN lama tidak berlaku lagi di semua panel." |
| Validasi | "Alamat server harus diawali https://." (http:// diterima untuk alamat jaringan lokal) / "PIN admin tidak boleh kosong." / "PIN baru minimal 6 angka." / "PIN baru terlalu mudah ditebak. Hindari angka berurutan atau berulang." / "PIN baru tidak boleh sama dengan PIN lama." / "Ulangan PIN baru tidak sama." |

### SCR-07 — Halaman Unduh (web di HP siswa)

- **Status:** Disetujui
- **Tujuan:** Siswa mengunduh PDF dengan satu ketukan.
- **Aksi utama (satu):** "Unduh PDF"
- **Aksi lain:** Tidak ada
- **Data yang tampil:** judul papan, tanggal dibuat, ukuran berkas, batas waktu berlaku
- **Hak akses:** Siapa pun yang memegang tautan, selama belum kedaluwarsa

**Wireframe (HP 360 px):**
```
┌──────────────────────┐
│ {Judul papan}        │
│ Dibuat {tanggal}     │
│ PDF · {2,4 MB}       │
│ Berlaku sampai {jam} │
│                      │
│   [  Unduh PDF  ]    │
└──────────────────────┘
```

| State | Yang tampil (teks persis) |
|---|---|
| Memuat | "Menyiapkan unduhan…" |
| Kosong | Tidak terjadi |
| Gagal | Kedaluwarsa: "Tautan ini sudah kedaluwarsa. Minta guru Anda membuat kode QR yang baru." Tidak ditemukan: "Tautan tidak ditemukan. Pindai ulang kode QR dari layar." Unduhan putus: "Unduhan terputus. Periksa sinyal HP, lalu ketuk Unduh PDF lagi." |
| Berhasil | "PDF sudah diunduh. Cek di folder Unduhan HP Anda." |
| Validasi | Tidak ada isian |

---

## 6. Komponen & Pola Berulang

| Pola | Aturan |
|---|---|
| Bilah alat | Di bawah tengah layar, dapat dipindah ke kiri atau kanan; tombol utama ≥ 64 dp dan tombol lain ≥ 48 dp (NFR-06); alat aktif ditandai dengan warna dan teks, bukan warna saja |
| Konfirmasi hapus | Dialog menyebut nama atau nomor data dan akibatnya; tombol "Hapus" (bahaya) dan "Batal"; tidak ada hapus tanpa konfirmasi untuk papan dan halaman |
| Notifikasi berhasil | Bilah kecil di atas tengah selama 4 detik (bukan di bawah agar tidak menutup bilah alat); kata kerja sama dengan tombol yang ditekan |
| Notifikasi gagal | Menetap sampai ditutup atau tindakan dilakukan; selalu menyebut apa terjadi, apakah papan aman, dan tindakan berikutnya |
| Indikator simpan | Teks kecil "Menyimpan…" / "Tersimpan" di bilah atas; tidak menghalangi menulis |
| Proses panjang | Indikator kemajuan dengan keterangan langkah dan tombol Batalkan; tidak mengunci kanvas kecuali dialog Bagikan dan AI |
| Pilih area (lasso) | Alat Pilih: lingkari dengan jari/stylus di tempat kosong; area terpilih diberi garis putus-putus dan **bilah di bawah area** (di atas area bila tidak muat) berisi tombol utama "Jadikan grafik" (v1.3, seperti video referensi; "Ubah ke teks" menyusul REQ-10). Aksi AI lain lewat tombol "Asisten AI" di bilah atas. Mengetuk gambar/bentuk/grafik tetap memilih objek itu |
| Pinyin & arti (v1.9, REQ-30, teks usulan AI) | Menu pintar pada tulisan Hanzi: hanya tombol "Pinyin & arti" (tanpa Rapikan rumus). Berhasil: kartu di samping tulisan berisi pinyin, Hanzi besar, terjemahan kalimat + "Terjemahan AI — periksa sebelum dipakai" (bila AI tidak menjawab: "Terjemahan kalimat belum tersedia (AI tidak menjawab). Arti per kata dari kamus."), kotak per kata (Hanzi, pinyin, arti; arti Inggris diberi "(Inggris)"), tombol "Dengarkan" dan "Pelan"; ketuk kotak kata = bunyi kata itu. Tanpa suara Mandarin di panel: tombol diganti "Suara Mandarin belum terpasang di panel. Pasang paket suara Mandarin di Pengaturan Android." Notifikasi "Kartu pinyin & arti ditempel di samping tulisan." Gagal (papan tidak berubah): pesan menu pintar yang ada; tanpa Hanzi "Tidak ada aksara Mandarin yang dikenali. Tulis lebih jelas, lalu lingkari lagi."; kamus "Kamus Mandarin sedang tidak tersedia. Coba lagi beberapa menit lagi." Kartu dipindah/diubah ukuran/dihapus dengan Pilih seperti gambar; badan kartu tidak menerima tinta |
| Tabel (v1.8, REQ-21, teks usulan AI) | Bilah alat: tombol "Tabel" → dialog "Sisipkan tabel": "Baris" dan "Kolom" dengan tombol − / + (bawaan 5 × 3; batas 2–20 dan 2–6), "Batal" / "Sisipkan". Berhasil: "Tabel ditempel. Ketuk sel untuk mengisinya." Sel: ketuk (alat apa pun kecuali Pilih dan Geser) → dialog "Isi tabel" ("Baris pertama: judul kolom. Kolom pertama: nilai x atau nama. Kolom lain: angka (koma desimal boleh).", semua sel, keyboard di sel yang diketuk, tombol berikutnya pindah sel; "Batal" / "Simpan"); di papan baris pertama tebal (judul kolom), petunjuk samar di sel judul kosong "Judul". Tabel terpilih (Pilih): bingkai + pegangan seperti gambar, di bawah tabel tombol "Jadikan grafik", "Tambah baris", "Tambah kolom", dan "Hapus". Jadikan grafik pada tabel tanpa angka langsung menampilkan pesan tanpa membuka menu. Jadikan grafik → menu "Garis", "Batang", "Titik" (Garis/Titik nonaktif dengan keterangan "Garis dan Titik butuh angka di kolom pertama." bila kolom pertama berisi teks). Berhasil: "Grafik ditempel di samping tabel. Ubah angka di tabel, grafik ikut berubah." Gagal: tanpa angka "Tabel belum berisi angka. Isi kolom kedua dan seterusnya dengan angka, lalu coba lagi."; batas "Tabel paling banyak 20 baris dan 6 kolom."; sel bukan angka ditandai garis bawah + ikon "!" dengan keterangan "Bukan angka, tidak digambar." Tanpa server/internet: semua tetap jalan |
| Peraga (v1.7, REQ-26–28, usulan) | Bilah alat: tombol "Peraga" → menu baris 1: Bandul, Gerak parabola, Pegas, Bidang miring, Kuis; baris 2: Indikator asam-basa, Logam + asam, Kelarutan fenol, Pembakaran. Kartu "Simulasi: {nama}" / "Lab virtual: {nama}": adegan, pembacaan rumus, penggeser "{label}: {nilai}", pilihan "{label}: {nama}" (ketuk = berikutnya), tombol "Putar"/"Jeda" dan "Ulang". Berhasil: "{Nama} ditempel. Atur nilainya, lalu tekan Putar." Menu pintar: "Peraga: {nama}". |
| Kuis (v1.7, REQ-27, usulan) | Dialog "Kuis pencocokan": "Judul kuis" (bawaan "Pasangkan dengan benar"), baris "Kiri (soal) n" ↔ "Kanan (jawaban) n" (maks 6, 60 huruf), "Tambah pasangan", "Isi dari papan (AI)" ("AI menyusun pasangan dari isi papan…"; gagal: "AI belum bisa menyusun kuis dari papan ini. Tulis pasangannya sendiri."), "Batal" / "Buat kuis"; validasi "Isi paling sedikit 2 pasangan lengkap." Di papan: judul, "Skor a / b", kartu kiri/kanan (benar: hijau + centang; salah: merah; terpilih: biru), "Acak ulang". Berhasil: "Kuis ditempel. Siswa mengetuk kartu kiri lalu pasangannya di kanan." |
| Sketsa → bangun ruang (v1.7, REQ-23, usulan) | Menu pintar pada sketsa persegi/segitiga/lingkaran: "Jadikan {Kubus/Balok/Limas/Kerucut/Bola/Tabung}". Berhasil: "Sketsa menjadi {nama}. Tekan Undo untuk kembali ke sketsa." |
| Kapur & tema papan (v1.7, REQ-29, usulan) | Menu Warna: warna + Putih, Kuning; baris 2: "Kapur" (nyala/mati), "Papan putih", "Papan hijau kapur", "Papan hitam" |
| Bangun ruang (v1.6, REQ-23, usulan) | Menu Bentuk baris kedua: Kubus, Balok, Prisma, Limas, Tabung, Kerucut, Bola (ikon gambar 3D kecil). Berhasil: "{Nama} ditempel. Geser jari di atasnya untuk memutar." Di dalam objek: tombol "Jaring-jaring"/"Tutup jaring" dan "Bidang potong"/"Sembunyikan potongan" (bola hanya Bidang potong) |
| Kimia di menu pintar (v1.6, REQ-24, usulan) | Reaksi/rumus kimia: "Rapikan rumus", "Setarakan" (bila belum setara), "Video eksperimen (n)" (bila ada di katalog). Setarakan berhasil: "Persamaan setara ditempel di samping reaksi." Dialog "Video eksperimen": daftar judul → pemutar (Putar/Jeda, penggeser waktu), "Daftar video", tombol tutup "Tutup". Gagal: "Video tidak bisa diputar. Periksa sambungan ke server sekolah, lalu coba lagi." |
| Rekam kelas (v1.6, REQ-25, usulan) | Bilah atas: "Rekam" → dialog "Rekam pelajaran?" ("Suara di kelas akan direkam lalu dikirim ke server sekolah untuk dibuat ringkasan. Rekaman dihapus setelah diolah. Hindari menyebut nama atau data pribadi siswa." — "Batal" / "Mulai rekam") → tombol merah "Merekam mm:ss · Selesai" → "Ringkasan diproses…" (menulis tetap jalan) → "Ringkasan siap" / "Ringkasan gagal" → dialog "Ringkasan pelajaran" (teks, "Periksa ringkasan sebelum dibagikan ke siswa.", "Buang" / "Tempel ke papan" / "Coba lagi"). Berhasil: "Ringkasan ditempel di halaman {n}." Gagal: izin mikrofon "Aplikasi belum diizinkan memakai mikrofon. Izinkan di Pengaturan Android, lalu coba lagi."; mikrofon "Mikrofon panel tidak bisa dipakai. Periksa mikrofon, lalu coba lagi."; jaringan "Rekaman belum terkirim karena panel tidak terhubung ke server sekolah. Tekan Coba lagi."; tanpa suara "Tidak ada suara pelajaran yang terdengar di rekaman."; AI "Ringkasan belum bisa dibuat. Coba lagi beberapa menit lagi." |
| Menu pintar (v1.5, REQ-22) | Begitu area dilingkari: bilah di bawah area "Mengenali…" (indikator putar). Lalu sesuai isi — fungsi: "Jadikan grafik" + "Rapikan rumus"; persamaan: "Rapikan rumus" + "Selesaikan" (Selesaikan hanya bila bisa dihitung tepat); lainnya: "Rapikan rumus". Berhasil: Jadikan grafik "Grafik ditempel di samping rumus."; Rapikan rumus (tulisan diganti rumus cetak di tempatnya) "Rumus dirapikan. Tekan Undo untuk kembali ke tulisan tangan."; Selesaikan (penyelesaian di samping) "Penyelesaian ditempel di samping persamaan." Gagal (di bilah, papan tidak berubah): "Tidak ada rumus yang dikenali. Tulis lebih jelas, lalu lingkari lagi." · "Panel tidak terhubung ke server sekolah." · "Panel belum terhubung ke server. Periksa alamat dan PIN admin di Pengaturan." · "Pengenal rumus sedang tidak tersedia. Coba lagi beberapa menit lagi." · "PIN salah 5 kali. Coba lagi dalam 5 menit." — semua dengan tombol "Coba lagi" kecuali tidak ada rumus. Melingkari lagi mengganti hasil lama |
| Jadikan grafik langsung (v1.3, digantikan menu pintar v1.5) | Tanpa AI dan tanpa jendela (SPEC 1.8). Memuat: tombol berubah menjadi indikator putar + "Membaca rumus…" dan tidak bisa ditekan lagi; kanvas tetap bisa ditulisi. Berhasil: grafik muncul di samping area, langsung terpilih, area hilang, notifikasi "Grafik ditempel di samping rumus." (Undo menghapusnya). Gagal (papan dan area tetap, tombol bisa ditekan lagi): rumus tidak terbaca "Rumus tidak terbaca. Tulis lebih jelas, misalnya y = x² − 3, lalu coba lagi."; tanpa jaringan "Panel tidak terhubung ke server sekolah. Papan Anda tidak berubah. Coba lagi."; Pengaturan/PIN "Panel belum terhubung ke server sekolah. Periksa alamat dan PIN admin di Pengaturan."; server/pengenal bermasalah atau terlalu lama "Pengenal rumus sedang tidak tersedia. Papan Anda tidak berubah. Coba lagi beberapa menit lagi."; PIN terkunci "PIN salah 5 kali. Coba lagi dalam 5 menit." Tanpa pengaturan server di panel: bilah tidak tampil |

---

## 7. Daftar Istilah (Bahasa Antarmuka)

| Istilah di UI | Bukan | Catatan |
|---|---|---|
| Papan | Board, Dokumen, Berkas | Satu kumpulan halaman yang disimpan |
| Halaman | Slide, Lembar | |
| Pena | Pensil, Kuas | |
| Penghapus | Eraser | Menghapus goresan utuh |
| Pilih | Seleksi, Lasso | |
| Bagikan | Ekspor, Share, Kirim | Menghasilkan PDF dan kode QR |
| Kode QR | Barcode | |
| Asisten AI | Chatbot, Bot | Nama tombol di bilah atas |
| Pecah soal | Solve, Jawab | Menjabarkan langkah penyelesaian |
| Buat soal serupa | Generate soal | |
| Ringkas papan | Rangkum | |
| Tempel ke papan | Insert, Terapkan | |
| Jadikan grafik | Plot, Visualisasi | REQ-20; v1.3 tombol di bilah bawah area, tanpa AI (pengenal rumus) |
| Grafik | Chart, Plot | Objek grafik interaktif di papan |
| Penggeser | Slider | Pengatur nilai parameter grafik |
| Tabel | Table, Spreadsheet | Objek tabel di papan (REQ-21) |
| Pinyin & arti | Terjemahkan, Translate | Tombol menu pintar untuk tulisan Mandarin (REQ-30) |
| Dengarkan / Pelan | Play, Putar suara | Suara Mandarin dari panel (REQ-30) |
| Garis / Batang / Titik | Line / Bar / Scatter | Jenis grafik dari tabel |
| Latar | Background, Template | PDF atau gambar di belakang tulisan |
| Pengaturan | Konfigurasi, Setting | |
| Penyedia AI | Provider, Vendor | Ollama cloud, OpenAI, Claude, Gemini, atau lainnya |
| Model | Engine, Versi AI | Nama model dari penyedia, ditampilkan apa adanya |
| Tes AI | Ping AI, Cek API | |

---

## 8. Riwayat Persetujuan

| Versi | Tanggal | Layar | Status | Oleh |
|---|---|---|---|---|
| 0.1 | 2026-10-14 | Semua (SCR-01 s/d SCR-07) | Draft | AI |
| 0.2 | 2026-10-14 | SCR-05, SCR-06, TSK-09, istilah | Draft — pilihan penyedia/model AI | AI (atas permintaan pemilik) |
| 0.3 | 2026-10-14 | SCR-05, SCR-06, TSK-09 | Draft — kunci admin, cadangan otomatis ke Ollama cloud, awal hanya Ollama cloud | AI (atas jawaban pemilik) |
| 0.4 | 2026-10-14 | SCR-06, TSK-10 | Draft — Ganti PIN admin di Pengaturan | AI (atas jawaban pemilik) |
| 1.0 | 2026-10-14 | Semua (SCR-01 s/d SCR-07) | **Disetujui** | Pemilik (Sukardi) |
| 1.2 | 2026-10-14 | SCR-05, pola Pilih area | Jadikan grafik + grafik interaktif (REQ-20) | Pemilik (persetujuan usulan), teks AI |
| 1.9 | 2026-10-15 | SCR-01 Pinyin & arti, kartu Mandarin | Teks usulan AI (REQ-30 disetujui pemilik; teks dikonfirmasi saat uji) | AI |
| 1.8 | 2026-10-15 | SCR-01 Tabel, Jadikan grafik dari tabel | Teks usulan AI (REQ-21 disetujui pemilik; teks dikonfirmasi sebelum/saat uji) | AI |
| 1.7 | 2026-10-15 | SCR-01 Peraga, Kuis, sketsa → 3D, kapur & tema papan | Teks usulan AI (dibangun dulu, dikonfirmasi saat uji) | AI |
| 1.6 | 2026-10-15 | SCR-01 bangun ruang, kimia, rekam kelas | Teks usulan AI (dibangun dulu, dikonfirmasi saat uji) | AI |
| 1.5 | 2026-10-15 | SCR-01 menu pintar | Pengenalan otomatis saat melingkari; aksi sesuai jenis isi; Rapikan rumus mengganti tulisan; Selesaikan | Pemilik (pilihan: otomatis, diganti di tempat), teks usulan AI |
| 1.4 | 2026-10-15 | SCR-01 bilah atas & bilah alat | Bilah atas ringkas (☰, judul, ikon simpan, Asisten AI, Undo/Redo); Warna/Ketebalan/Pindah ikon saja; APK guru tanpa alat ukur | Pemilik (pilihan) |
| 1.3 | 2026-10-15 | SCR-01 pola Pilih area, Jadikan grafik langsung | Bilah di bawah area berisi "Jadikan grafik" yang langsung menempel grafik tanpa jendela (seperti video); tombol cepat "Asisten AI" di samping area diganti, Asisten AI tetap di bilah atas | Pemilik (pilihan: isi bilah = Jadikan grafik; langsung muncul), teks usulan AI |
| 1.1 | 2026-10-14 | SCR-06, TSK-08 | PIN admin menggantikan kunci perangkat; seluruh Pengaturan terkunci admin (rincian usulan); SCR-04/07 ditunda | Pemilik (keputusan), rincian AI |
