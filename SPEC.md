# SPEC.md — Whiteboard IFP

> **Layer 1: Spec.** Dokumen ini adalah sumber kebenaran tunggal tentang *apa* yang dibangun.
> Semua keputusan di sini hasil wawancara (interview) dengan pemilik project.
> Jika ada konflik antara dokumen lain dan SPEC.md, SPEC.md yang berlaku.
>
> **Konvensi penulisan:**
> - Butir bertanda **(usulan)** berasal dari AI dan belum diputuskan pemilik; jangan dianggap keputusan sebelum disetujui.
> - Setiap requirement diberi ID `REQ-xx` agar bisa dilacak ke acceptance criteria.
> - SPEC hanya boleh diubah oleh pemilik. AI boleh **mengusulkan** perubahan (lihat §12), bukan mengubah langsung.

- **Versi:** 1.13
- **Status:** Disepakati
- **Pemilik:** Sukardi
- **Terakhir diperbarui:** 2026-10-15

---

## 1. Latar Belakang & Tujuan

**Masalah yang diselesaikan:**
Panel interaktif (IFP) Hisense di sekolah memakai aplikasi whiteboard bawaan. Pemilik ingin aplikasi whiteboard sendiri yang lebih mulus saat menulis, dan yang menambahkan hal yang tidak ada di aplikasi bawaan: asisten AI untuk guru (memecah soal, membuat soal serupa, meringkas papan) yang bisa memakai penyedia AI pilihan serta berbagi hasil papan ke HP siswa lewat kode QR.

**Tujuan project:**
- Menulis di panel terasa mulus dan alami, dengan jari maupun stylus, termasuk saat beberapa siswa menulis bersamaan.
- Guru bisa mengajar dengan papan multi-halaman berkanvas luas, gambar, bentuk, dan latar PDF/gambar.
- Guru bisa membagikan hasil papan sebagai PDF lewat kode QR tanpa kabel atau flashdisk.
- Guru dibantu AI untuk membahas soal di kelas, dengan penyedia yang bisa dipilih di Pengaturan (Ollama cloud, OpenAI, Claude, Gemini, atau layanan lain yang kompatibel OpenAI), tanpa kunci API tersimpan di panel.

**Indikator keberhasilan:** (target angka lihat §7; dikonfirmasi setelah uji di panel sungguhan)
- Guru bisa mulai menulis dalam satu ketukan dari saat aplikasi dibuka.
- Menulis terasa mulus di panel sungguhan dengan halaman yang berisi banyak goresan, diukur pada Checkpoint 1.
- Guru bisa menampilkan kode QR PDF dalam waktu singkat setelah menekan Bagikan (target di NFR-33).
- Dua guru yang belum pernah memakai aplikasi bisa menyelesaikan tugas utama tanpa dibantu (uji pengguna, Checkpoint 7).

---

## 2. Pengguna & Peran

| Peran | Deskripsi | Jumlah |
|---|---|---|
| Guru | Memegang panel; menulis, mengatur halaman, membagikan PDF, memakai asisten AI. Tanpa akun/login. | Semua guru sekolah yang memakai panel |
| Siswa penulis | Maju menulis jawaban di panel; memakai fitur menulis saja. Tanpa akun. | Beberapa orang bersamaan |
| Penerima PDF | Siswa/orang lain yang memindai QR di HP dan mengunduh PDF lewat peramban. Tanpa aplikasi dan tanpa akun. | Tak terbatas (selama tautan berlaku) |
| Operator | Pemilik project; memasang APK, mengelola server perantara dan kunci API penyedia AI. Disebut **admin** di aplikasi: satu-satunya pemegang PIN admin (mengganti penyedia AI dan PIN di Pengaturan). Selain itu memakai berkas konfigurasi di server. | 1 (Sukardi) |

---

## 3. Ruang Lingkup

### 3.1 Masuk MVP
| ID | Requirement | Prioritas |
|---|---|---|
| REQ-01 | Menulis dengan jari atau stylus menghasilkan goresan halus dengan ketebalan dinamis, tanpa jeda yang terasa | Wajib |
| REQ-02 | Guru dapat memakai pena (pilih warna dan ketebalan), penghapus goresan, serta undo dan redo | Wajib |
| REQ-03 | Beberapa jari/penulis dapat menulis bersamaan di kanvas yang sama | Wajib |
| REQ-04 | Kanvas luas yang dapat digeser dan di-zoom | Wajib |
| REQ-05 | Papan multi-halaman: tambah, duplikat, hapus, ubah urutan, dan pindah halaman | Wajib |
| REQ-06 | Papan tersimpan otomatis di panel dan bisa dibuka kembali dari daftar papan | Wajib |
| REQ-07 | Guru dapat menyisipkan gambar ke halaman, lalu memindah, mengubah ukuran, dan menghapusnya | Wajib |
| REQ-08 | Guru dapat membuat bentuk dasar yang rapi (garis, persegi, lingkaran, segitiga, panah) | Wajib |
| REQ-09 | Guru dapat memasang PDF atau gambar sebagai latar halaman dan menulis di atasnya | Wajib |
| REQ-10 | Tulisan tangan pada area yang dipilih dapat diubah menjadi teks ketikan | Wajib |
| REQ-11 | Papan dapat diekspor menjadi PDF; tulisan, bentuk, gambar, dan latar ikut tercetak | Wajib |
| REQ-12 | PDF dibagikan lewat kode QR yang berisi tautan sementara ke berkas di server sekolah | Wajib |
| REQ-13 | Asisten AI memecah soal yang dipilih guru menjadi langkah penyelesaian | Wajib |
| REQ-14 | Asisten AI membuat soal latihan serupa dari soal yang dipilih guru | Wajib |
| REQ-15 | Asisten AI meringkas isi papan menjadi catatan | Wajib |
| REQ-16 | Kunci API semua penyedia AI tersimpan hanya di server perantara; aplikasi memanggil server, bukan penyedia AI langsung | Wajib |
| REQ-17 | Admin dapat mengatur alamat server dan PIN admin di panel, serta mengetes koneksi (P-11: PIN admin menggantikan kunci perangkat) | Wajib |
| REQ-18 | Gangguan jaringan, server, atau AI tidak boleh menghilangkan atau merusak isi papan | Wajib |
| REQ-19 | Asisten AI dapat memakai beberapa penyedia (Ollama cloud, OpenAI, Anthropic Claude, Google Gemini, dan layanan lain yang kompatibel dengan API OpenAI); penyedia dan model dipilih **admin** di Pengaturan (bagian terkunci PIN admin) dari daftar yang diaktifkan operator di server; bila penyedia terpilih gagal, server otomatis berpindah ke Ollama cloud; ketiga aksi AI bekerja sama apa pun penyedianya | Wajib |
| REQ-20 | Guru memilih rumus fungsi tulisan tangan (mis. y = x² − 3, y = A sin x + B), lalu Asisten AI "Jadikan grafik" mengubahnya menjadi **grafik interaktif** di papan: bidang koordinat, satu kurva berwarna per rumus, dan penggeser untuk setiap parameter huruf yang langsung menggerakkan kurva; grafik bisa dipindah, diubah ukurannya, dihapus, dan tersimpan | Wajib |
| REQ-21 | **Tabel → grafik** (v1.12): alat **Tabel** menyisipkan tabel (2–20 baris × 2–6 kolom) sebagai objek di papan; isi sel **diketik** (baris pertama = judul kolom, kolom pertama = nilai x atau nama kategori, kolom berikutnya = seri angka, koma desimal diterima); tabel terpilih → **Jadikan grafik** → guru memilih **Garis**, **Batang**, atau **Titik**; grafik dibuat di panel **tanpa AI dan tanpa internet**, **terhubung** ke tabel (angka diubah → grafik ikut berubah), sumbu otomatis, legenda dari judul kolom | Wajib |
| REQ-22 | **Menu pintar** (v1.9, dari panduan "Smart Blackboard"): begitu area dilingkari dengan Pilih, server mengenali isinya tanpa AI (pengenal rumus + SymPy) dan bilah di bawah area menampilkan aksi yang cocok — fungsi (y = …): "Jadikan grafik", "Rapikan rumus"; persamaan (x² = 4, sistem persamaan): "Rapikan rumus", "Selesaikan"; ekspresi lain: "Rapikan rumus". "Rapikan rumus" mengganti tulisan tangan di area dengan rumus cetak di tempat yang sama (Undo mengembalikan); "Selesaikan" menaruh penyelesaian (dihitung SymPy) di samping area | Wajib |
| REQ-23 | **Bangun ruang 3D** (v1.9): kubus, balok, prisma, limas, tabung, kerucut, bola dari menu; bisa diputar dengan jari, dibuka jaring-jaringnya, dan diberi bidang potong; digambar sendiri di Flutter (tanpa WebView) | Wajib (setelah REQ-22) |
| REQ-24 | **Kimia + video eksperimen** (v1.9): mengenali rumus/reaksi kimia di area dan menampilkan video dari perpustakaan video sekolah yang cocok | Sebaiknya (setelah REQ-23; perlu perpustakaan video) |
| REQ-25 | **Rekam kelas + ringkasan** (v1.9): merekam suara guru, mengubahnya ke teks, dan membuat ringkasan materi bersama rumus di papan | Sebaiknya (setelah REQ-24; perlu AI + izin rekaman — dibahas bersama pemanfaatan AI) |
| REQ-26 | **Simulasi fisika** (v1.11, dari prototipe HTML pemilik): objek peraga Bandul (L, g, simpangan; T = 2π√(L/g)), Gerak parabola (v₀, sudut, g; tinggi maks & jarak), Pegas (k, m, A; T = 2π√(m/k)), Bidang miring (θ, μ, g; a = g(sin θ − μ cos θ)) dengan animasi, panah gaya/kecepatan, penggeser, Putar/Jeda/Ulang | Wajib |
| REQ-27 | **Kuis siswa di papan** (v1.11): guru mengisi 2–6 pasangan (atau "Isi dari papan (AI)" lalu diperiksa guru); siswa mengetuk kartu kiri lalu pasangannya; benar = hijau + centang + skor, salah = merah; "Acak ulang" | Wajib |
| REQ-28 | **Lab kimia virtual** (v1.11): Indikator asam-basa (pH, universal/lakmus/fenolftalein), Logam + asam (Mg/Zn/Fe/Cu, konsentrasi; gelembung H₂), Kelarutan fenol (suhu; jernih ≥ ±66 °C), Pembakaran (O₂; sempurna/tidak sempurna) — tanpa video; ditawarkan menu pintar sesuai zat | Wajib |
| REQ-29 | **Gaya kapur dan tema papan** (v1.11): pena "Kapur" bertekstur butiran; papan Putih/Hijau kapur/Hitam per papan (pena ikut terlihat); warna Putih dan Kuning ditambahkan | Sebaiknya |
| REQ-30 | **Bahasa Mandarin: pinyin, arti, suara** (v1.13): Hanzi tulisan tangan yang dilingkari dikenali server; menu pintar menawarkan "Pinyin & arti"; server memberi pinyin bertanda nada (pypinyin) dan arti per kata dari kamus (CC-CEDICT), terjemahan kalimat oleh AI berlabel "Terjemahan AI"; hasil menjadi kartu di papan (jenis `mandarin`) dengan suara dari TTS panel (Dengarkan, Pelan, ketuk kata) | Sebaiknya (setelah REQ-21; syarat uji akurasi Hanzi & suara zh-CN di panel) |

> Aturan: setiap REQ **wajib** punya minimal satu kriteria di `verification/acceptance-criteria.md`.
> **Ditunda (P-12, 2026-10-14):** REQ-11 (ekspor PDF) dan REQ-12 (bagikan lewat QR) beserta SCR-04 dan SCR-07 ditunda dulu atas keputusan pemilik. Latar PDF (REQ-09) tetap ada.
>
> Catatan: pemilik memilih semua fitur untuk versi pertama dan menginginkan hasil "sederhana tapi sangat mulus". Urutan pengerjaan di §9 menaruh menulis mulus lebih dulu; fitur mana yang ditunda bila waktu mepet adalah pertanyaan terbuka (§10, P-12).

### 3.2 Tidak Masuk MVP (Out of Scope)
- Akun dan login guru: pemilik memilih tanpa login; papan tersimpan di panel.
- Kolaborasi waktu nyata antar-perangkat (HP siswa ikut menulis): di luar kebutuhan; siswa hanya menerima PDF.
- Sinkronisasi papan ke cloud atau antar-panel: papan hanya di panel tempat dibuat.
- Integrasi Google Classroom dan fitur "lebih canggih dari bawaan": pemilik memilih versi sederhana.
- Rekam layar, audio, video, dan penayangan layar ke perangkat lain.
- iOS, Windows, dan publikasi ke toko aplikasi: aplikasi hanya untuk panel sekolah sendiri, dipasang manual lewat APK.
- Antarmuka admin untuk server: operator memakai berkas konfigurasi.

---

## 4. Model Data / Content Model

### 4.1 Papan (disimpan di panel)
| Field | Tipe | Wajib | Keterangan |
|---|---|---|---|
| id | uuid | Ya | Dibuat aplikasi |
| judul | string | Ya | Default dari tanggal dan jam; bisa diganti guru |
| dibuat_pada | datetime | Ya | Disimpan UTC, tampil WIB |
| diubah_pada | datetime | Ya | Diperbarui setiap simpan otomatis |
| halaman_terakhir | integer | Ya | Halaman yang terbuka saat papan ditutup |

### 4.2 Halaman
| Field | Tipe | Wajib | Keterangan |
|---|---|---|---|
| id | uuid | Ya | |
| papan_id | uuid | Ya | Milik satu papan |
| urutan | integer | Ya | Mulai dari 1 |
| latar | referensi berkas | Tidak | PDF/gambar latar (REQ-09) |
| posisi_pandang | angka (x, y, zoom) | Ya | Posisi geser/zoom terakhir halaman ini |

### 4.3 Objek (isi halaman)
| Field | Tipe | Wajib | Keterangan |
|---|---|---|---|
| id | uuid | Ya | |
| halaman_id | uuid | Ya | |
| jenis | enum: goresan, bentuk, gambar, teks, grafik, bangun, peraga, kuis, tabel, mandarin | Ya | grafik (REQ-20): daftar rumus, parameter (nama, min, maks, nilai), rentang sumbu, posisi & ukuran. tabel (REQ-21): judul kolom, isi sel per baris (teks apa adanya), posisi & ukuran. Grafik dari tabel (REQ-21): jenis grafik (garis/batang/titik), id tabel sumber (tidak terhubung lagi bila tabel itu sudah tidak ada di halaman; salinan halaman menautkan grafik ke salinan tabelnya), salinan data terakhir, posisi & ukuran. mandarin (REQ-30): Hanzi, daftar kata (hanzi, pinyin, arti), pinyin kalimat, terjemahan kalimat (boleh kosong), posisi & ukuran |
| data | bergantung jenis | Ya | Goresan: titik, tekanan/kecepatan, warna, ketebalan. Bentuk: jenis dan geometri. Gambar: referensi berkas, posisi, ukuran. Teks: isi, posisi, ukuran huruf |
| urutan_tumpuk | integer | Ya | Objek yang lebih baru tampil di atas |

### 4.4 Berbagi (disimpan di server)
| Field | Tipe | Wajib | Keterangan |
|---|---|---|---|
| token | string acak | Ya | Bagian dari tautan; tidak bisa ditebak |
| nama_berkas | string | Ya | Nama PDF untuk diunduh |
| dibuat_pada | datetime | Ya | UTC |
| kedaluwarsa_pada | datetime | Ya | Setelah lewat, tautan ditolak dan berkas dihapus |

### 4.5 Catatan Permintaan AI (disimpan di server, tanpa isi)
| Field | Tipe | Wajib | Keterangan |
|---|---|---|---|
| waktu | datetime | Ya | UTC |
| jenis | enum: pecah_soal, soal_serupa, ringkas | Ya | |
| penyedia | string | Ya | id penyedia yang dipakai (mis. `openai`, `claude`) |
| model | string | Ya | Nama model yang dipakai |
| cadangan_dari | string | Tidak | Diisi id penyedia asal bila permintaan dialihkan ke Ollama cloud |
| alasan_cadangan | enum: tidak_terjangkau, kuota_habis, kunci_ditolak, model_tidak_ada, batas_waktu | Tidak | Penyebab pengalihan |
| status | enum: berhasil, gagal, batas_waktu | Ya | |
| durasi_ms | integer | Ya | Untuk memantau lambatnya AI |

> Isi papan dan isi jawaban AI **tidak** dicatat di server (lihat NFR-21).

### 4.5a Penyedia AI (berkas konfigurasi server, diisi operator)
| Field | Tipe | Wajib | Keterangan |
|---|---|---|---|
| id | string | Ya | Pengenal unik, mis. `ollama`, `openai`, `claude`, `gemini`, `openrouter` |
| nama_tampil | string | Ya | Nama yang tampil di Pengaturan panel, mis. "Claude (Anthropic)" |
| jenis_adaptor | enum: ollama, openai, anthropic, gemini, openai_kompatibel | Ya | Menentukan format panggilan API; `openai_kompatibel` untuk "lainnya" (OpenRouter, Groq, DeepSeek, Ollama lokal, dll.) |
| alamat_api | url | Tidak | Wajib untuk `openai_kompatibel`; selain itu memakai alamat resmi penyedia |
| kunci_api | rahasia | Ya* | Dibaca dari variabel lingkungan, bukan ditulis di kode; *boleh kosong untuk Ollama lokal |
| model | daftar string | Ya | Model yang boleh dipilih guru |
| model_bawaan | string | Ya | Dipakai bila panel belum memilih model |
| dukung_gambar | boolean per model | Ya | Apakah model bisa membaca gambar area (terkait P-03) |
| aktif | boolean | Ya | Penyedia nonaktif tidak tampil di panel |

**Ollama cloud** adalah penyedia **bawaan dan cadangan** server: dipakai bila panel belum memilih, bila pilihan panel sudah tidak aktif, dan bila penyedia terpilih gagal (lihat 5.7). Ollama cloud tidak boleh dinonaktifkan selama ia menjadi cadangan.

Tahap awal: **hanya Ollama cloud yang aktif**. Entri OpenAI, Claude, Gemini, dan lainnya sudah disiapkan di konfigurasi dalam keadaan `aktif = false` dan dinyalakan operator nanti tanpa mengubah APK.

Server juga menyimpan **PIN admin** dalam bentuk hash (bukan teks asli); panel memeriksanya lewat server. PIN **diganti admin dari layar Pengaturan** (lihat 5.8) dan langsung berlaku di semua panel. Operator tetap bisa mengatur ulang PIN lewat konfigurasi server sebagai jalan darurat bila PIN lupa atau sudah diganti orang lain.

### 4.5b Pilihan AI di panel (disimpan lokal di panel)
| Field | Tipe | Wajib | Keterangan |
|---|---|---|---|
| penyedia_ai | string | Tidak | id penyedia; kosong berarti ikut bawaan server |
| model_ai | string | Tidak | Kosong berarti `model_bawaan` penyedia |

### 4.6 Relasi
- Papan **one-to-many** Halaman — satu papan punya satu halaman atau lebih (minimal satu).
- Halaman **one-to-many** Objek — isi halaman berupa objek yang bertumpuk.
- Berbagi berdiri sendiri — tidak menunjuk ke Papan; hanya berisi salinan PDF yang sudah jadi, sehingga papan di panel tetap milik panel.

---

## 5. Fitur & Workflow

### 5.1 Menulis dan Menghapus
**Deskripsi:** Menulis bebas dengan jari atau stylus, memilih warna dan ketebalan, menghapus goresan, membatalkan dan mengulang. Beberapa jari boleh menulis bersamaan.

**Alur:**
```
Buka papan → pilih Pena (warna, ketebalan) → tulis → (Penghapus untuk hapus goresan) → Undo/Redo bila perlu
```

**Requirement terkait:** REQ-01, REQ-02, REQ-03

**Layar & tugas terkait:** SCR-01 · TSK-01, TSK-05 — lihat `docs/ux-flow.md`

**Aturan bisnis:**
- Goresan baru tampil di atas objek lama.
- Undo/redo bekerja per papan selama aplikasi terbuka.
- Penghapus menghapus goresan yang tersentuh, bukan menimpa dengan warna latar.
- Aturan gestur (P-02): geser dan zoom hanya di alat **Geser** yang dipilih khusus; selama Pena atau Penghapus aktif, setiap jari/stylus menulis atau menghapus. Tidak ada cubit-zoom di mode Pena.

**Kasus gagal / edge case:**
- Sentuhan tidak sengaja oleh telapak tangan → sentuhan yang dibatalkan sistem (palm rejection bawaan panel) tidak meninggalkan tinta. Penolakan telapak berdasarkan ukuran sentuhan ditinjau setelah data panel (P-01) ada.
- Memori penuh saat menulis → goresan terakhir tetap tersimpan; guru diberi tahu dan diminta menutup halaman lain atau menyimpan lalu membuka ulang (teks persis di ux-flow).
- Undo saat tidak ada yang bisa dibatalkan → tombol nonaktif.

### 5.2 Halaman dan Kanvas Luas
**Deskripsi:** Papan punya banyak halaman. Tiap halaman berkanvas luas yang bisa digeser dan di-zoom.

**Alur:**
```
Buka panel Halaman → tambah / duplikat / hapus / geser urutan → ketuk halaman untuk pindah
Di halaman: geser kanvas dan zoom sesuai aturan gestur
```

**Requirement terkait:** REQ-04, REQ-05

**Layar & tugas terkait:** SCR-01, SCR-03 · TSK-06 — lihat `docs/ux-flow.md`

**Aturan bisnis:**
- Papan selalu punya minimal satu halaman.
- Menghapus halaman meminta konfirmasi yang menyebut nomor halaman.
- Posisi geser/zoom diingat per halaman.
- Batas ukuran kanvas dan jumlah halaman menunggu keputusan P-08.

**Kasus gagal / edge case:**
- Menghapus satu-satunya halaman → ditolak dengan pesan penjelasan.
- Zoom melewati batas → berhenti di batas tanpa error.
- Pindah halaman saat sedang menulis → goresan yang sedang berjalan diselesaikan lebih dulu.

### 5.3 Papan Tersimpan
**Deskripsi:** Papan tersimpan otomatis di panel. Daftar papan menampilkan gambar mini; guru bisa membuka, mengganti nama, menghapus.

**Alur:**
```
Buka aplikasi → papan terakhir terbuka (usulan) → menulis → simpan otomatis
Beranda → daftar papan → buka / ganti nama / hapus
```

**Requirement terkait:** REQ-06, REQ-18

**Layar & tugas terkait:** SCR-01, SCR-02 · TSK-01, TSK-07 — lihat `docs/ux-flow.md`

**Aturan bisnis:**
- Simpan otomatis berjalan terus; guru tidak perlu menekan Simpan.
- Aplikasi yang tertutup mendadak (mati listrik, force close) kehilangan paling banyak selang waktu pada NFR-32.
- Menghapus papan meminta konfirmasi yang menyebut judul papan.
- Layar awal (P-10): aplikasi langsung membuka papan terakhir; bila belum ada papan, papan baru dibuat otomatis.

**Kasus gagal / edge case:**
- Berkas papan rusak → tawarkan salinan otomatis terakhir.
- Penyimpanan panel penuh → beri tahu dan jangan menutup papan yang sedang terbuka.
- Judul papan kosong saat ganti nama → tolak dengan pesan validasi.

### 5.4 Gambar, Bentuk, dan Latar
**Deskripsi:** Guru menyisipkan gambar, membuat bentuk dasar yang rapi, dan memasang PDF/gambar sebagai latar halaman.

**Alur:**
```
Gambar: alat Gambar → pilih berkas → gambar muncul di halaman → pindah / ubah ukuran / hapus
Bentuk: alat Bentuk → pilih jenis → buat di kanvas → pindah / ubah ukuran / hapus
Latar: menu halaman → Pasang latar → pilih PDF atau gambar → tulis di atasnya
Tabel: alat Tabel → pilih jumlah baris & kolom → Sisipkan → ketuk sel → ketik isi
       → tabel terpilih → Jadikan grafik → Garis / Batang / Titik → grafik di samping tabel
```

**Requirement terkait:** REQ-07, REQ-08, REQ-09, REQ-21

**Layar & tugas terkait:** SCR-01, SCR-03 · TSK-04 — lihat `docs/ux-flow.md`

**Aturan bisnis:**
- Latar PDF memakai satu halaman PDF per halaman papan; PDF banyak halaman menghasilkan banyak halaman papan, **paling banyak 5 halaman** (P-13). Halaman PDF pertama menjadi latar halaman yang sedang dibuka; berikutnya menjadi halaman baru tepat sesudahnya. PDF lebih dari 5 halaman: hanya 5 halaman pertama yang dipasang, dan guru diberi tahu.
- Latar tidak ikut terhapus saat penghapus dipakai.
- Berkas gambar dan PDF dipilih dari **penyimpanan panel** lewat pemilih berkas Android (P-06). Berkas disalin ke penyimpanan aplikasi sehingga papan tetap utuh bila berkas asli dihapus.
- Bentuk dibuat dengan **dua cara** (P-07): memilih jenis dari menu Bentuk lalu menyeret, atau pilihan "Otomatis" di menu Bentuk: guru menggambar bebas dan goresan dirapikan menjadi garis, persegi, lingkaran, atau segitiga bila dikenali (usulan: bila tidak dikenali, goresan tetap seperti digambar).
- Gambar dan bentuk dipindah, diubah ukurannya, dan dihapus dengan alat **Pilih** (ketuk objek). Bentuk juga bisa dihapus dengan Penghapus seperti goresan; gambar tidak (usulan).
- **Tabel (REQ-21, v1.12):** ukuran awal dipilih saat menyisipkan (2–20 baris × 2–6 kolom); saat terpilih, tabel punya tombol "Tambah baris" dan "Tambah kolom" sampai batas itu (usulan). Tabel dipindah/diubah ukuran/dihapus dengan Pilih seperti gambar; Penghapus tidak menghapusnya dan badan tabel tidak menerima tinta (usulan). Mengetuk sel dengan alat apa pun kecuali Pilih dan Geser membuka dialog **Isi tabel** (semua sel sebagai kolom isian, keyboard layar langsung di sel yang diketuk, tombol berikutnya berpindah sel); **Simpan** = satu Undo, Batal tidak mengubah apa pun. Dengan Pilih, ketukan memilih tabel; tombol tabel tampil di bawah tabel agar tidak menutupi grafik di sampingnya.
- **Jadikan grafik dari tabel:** dihitung dan digambar di panel dengan penggambar grafik sendiri (tanpa server, tanpa dependency baru). Garis dan Titik butuh angka di kolom pertama; bila kolom pertama berisi teks, hanya **Batang** yang bisa dipilih. Beberapa seri pada Batang = batang berkelompok. Grafik dari tabel tidak punya penggeser. Warna seri dari token di `theme.dart`; legenda selalu bertuliskan judul kolom (status tidak dibedakan lewat warna saja).
- Grafik terhubung ke tabelnya: setiap perubahan sel langsung menggambar ulang grafik dan tersimpan. Tabel dihapus → grafik tetap dengan data terakhir dan tidak terhubung lagi.

**Kasus gagal / edge case:**
- Berkas bukan gambar/PDF atau rusak → tolak dengan pesan yang menyebut nama berkas.
- PDF lebih dari 5 halaman → 5 halaman pertama dipasang dan guru diberi tahu batasnya (P-13). Batas ukuran berkas menunggu P-08.
- PDF terkunci kata sandi → tolak dengan pesan penjelasan.
- Sel kosong atau bukan angka di kolom seri → titik/batang itu dilewati; sel berisi teks bukan angka ditandai (garis bawah + ikon, bukan warna saja), sel kosong tidak ditandai. Tabel tanpa satu angka pun → Jadikan grafik menampilkan pesan dan tidak membuat grafik.
- Menambah baris/kolom melewati 20 × 6 → ditolak dengan pesan batas.

### 5.5 Tulisan Tangan Menjadi Teks
**Deskripsi:** Guru memilih area berisi tulisan tangan, lalu mengubahnya menjadi kotak teks ketikan di papan.

**Alur:**
```
Alat Pilih → lingkari tulisan → Ubah ke teks → hasil tampil sebagai kotak teks → Pakai / Batal
```

**Requirement terkait:** REQ-10

**Layar & tugas terkait:** SCR-01 · TSK-02 — lihat `docs/ux-flow.md`

**Aturan bisnis:**
- Teks hasil pengenalan tidak menggantikan tulisan asli sampai guru memilih "Pakai".
- Teks hasil bisa diedit sebelum dipakai.
- Teknologi pengenalan (di perangkat atau lewat server) menunggu keputusan P-04.

**Kasus gagal / edge case:**
- Tulisan tidak terbaca → pesan penjelasan; tulisan asli tidak berubah.
- Area yang dipilih kosong → ajakan untuk melingkari tulisan terlebih dahulu.
- Model pengenalan belum terunduh → beri tahu bahwa perlu internet sekali (bila P-04 memilih ML Kit).

### 5.6 Ekspor PDF dan Bagikan QR
**Deskripsi:** Guru mengekspor papan menjadi PDF dan membagikannya lewat kode QR di layar panel. Siswa memindai QR dengan HP, membuka halaman unduh, dan mengunduh PDF.

**Alur:**
```
Bagikan → pilih halaman yang dibagikan → Buat kode QR → aplikasi membuat PDF → unggah ke server → QR tampil
Siswa: pindai QR → halaman unduh → Unduh PDF
```

**Requirement terkait:** REQ-11, REQ-12, REQ-18

**Layar & tugas terkait:** SCR-04, SCR-07 · TSK-03 — lihat `docs/ux-flow.md`

**Aturan bisnis:**
- PDF dibuat di panel lalu diunggah ke server; server menyimpan salinan sementara dan membuat tautan bertoken acak.
- Tautan kedaluwarsa dan berkasnya dihapus otomatis (masa berlaku menunggu P-05; usulan 24 jam).
- Satu kali Bagikan menghasilkan satu tautan baru; tautan lama tetap berlaku sampai kedaluwarsa.
- Tautan bisa dibuka siapa pun yang memegang tautan itu (tanpa akun).

**Kasus gagal / edge case:**
- Panel tidak terhubung ke server → pesan gagal; papan tidak berubah; tombol Coba lagi.
- Unggah terputus di tengah → ulang dari awal; tidak ada tautan setengah jadi yang tampil.
- Tautan kedaluwarsa atau tidak dikenal → halaman unduh menjelaskan dan meminta guru membuat QR baru.
- PDF terlalu besar untuk diunggah → beri tahu batas ukuran dan tawarkan membagikan halaman tertentu saja.

### 5.7 Asisten AI
**Deskripsi:** Guru memilih area di papan (atau seluruh halaman) lalu meminta AI memecah soal, membuat soal serupa, atau meringkas isi papan. Aplikasi memanggil server perantara dengan menyebut penyedia dan model pilihan panel; server meneruskan ke penyedia itu (Ollama cloud, OpenAI, Claude, Gemini, atau layanan kompatibel OpenAI), hasil ditampilkan untuk dicek guru lalu ditempel ke papan.

**Alur:**
```
Pilih area (atau halaman) → Asisten AI → pilih aksi → server perantara → penyedia AI terpilih → hasil tampil → Tempel ke papan / Buang
```

**Requirement terkait:** REQ-13, REQ-14, REQ-15, REQ-16, REQ-18, REQ-19, REQ-20

**Layar & tugas terkait:** SCR-01, SCR-05 · TSK-02 — lihat `docs/ux-flow.md`

**Aturan bisnis:**
- Aplikasi tidak pernah menyimpan atau mengirim kunci API penyedia AI; hanya PIN admin (tersimpan aman di panel) ke server perantara.
- Server menerjemahkan satu permintaan aplikasi ke format masing-masing penyedia lewat adaptor; prompt untuk ketiga aksi sama untuk semua penyedia sehingga hasilnya sebanding.
- Layar Asisten AI menampilkan penyedia dan model yang sedang dipakai.
- Bila pilihan panel sudah dinonaktifkan operator, server memakai Ollama cloud dan aplikasi memberi tahu guru.
- **Cadangan otomatis:** bila penyedia terpilih gagal (tidak terjangkau, kuota habis, kunci API ditolak, model tidak ada, atau tidak menjawab dalam batas waktunya), server langsung mengulang permintaan yang sama ke Ollama cloud tanpa tindakan guru. Hasil diberi keterangan bahwa jawaban berasal dari Ollama cloud.
- Agar total tetap ≤ 60 detik (NFR-33), penyedia terpilih diberi batas 30 detik, sisanya untuk Ollama cloud (usulan). Bila penyedia terpilih adalah Ollama cloud sendiri, tidak ada pengulangan.
- Setiap perpindahan ke cadangan dicatat di server (penyedia asal, penyebab) agar operator tahu penyedia mana yang bermasalah.
- Hasil AI tidak otomatis masuk papan; guru melihatnya dulu dan memilih "Tempel ke papan".
- Hasil AI ditempel sebagai objek teks yang bisa digeser dan diedit.
- Setiap hasil AI disertai pengingat untuk memeriksa kebenarannya.
- Isi yang dikirim ke AI tidak dicatat di server (lihat §4.5 dan NFR-21).
- Isi papan dikirim ke AI sebagai **gambar area terpilih** (P-03, berlaku untuk Pecah soal, Soal serupa, Ringkas): server meneruskannya ke model yang `dukung_gambar = true`. Bila model pilihan panel tidak bisa membaca gambar, server memakai model bergambar pertama dari penyedia yang sama; cadangan Ollama cloud juga memakai model bergambar.
- **Jadikan grafik** (REQ-20, v1.8): **tanpa AI/model bahasa.** Server memotong gambar area per baris tulisan, membacanya dengan **pengenal rumus Pix2Text MFR 1.5** (gambar → LaTeX, onnxruntime di CPU VPS, lisensi MIT), lalu **SymPy** mengurai dan memvalidasi LaTeX dengan daftar putih (x, parameter satu huruf kecuali I/l/O/o yang mirip angka, angka, operasi, sin, cos, tan, akar, log basis 10, ln, exp, abs, π, e) dan menguji hitung pada 41 titik. Baris yang tidak lolos dibuang; tidak ada yang lolos → "tidak menemukan rumus". Server mengembalikan data terstruktur (rumus, parameter beserta rentang −5…5 dan nilai awal 1, rentang sumbu: ±2π bila ada fungsi trigonometri, selain itu ±10). Panel memeriksa dan menghitung rumus itu dengan pengurai matematika sendiri (operasi + − × ÷ ^, sin, cos, tan, akar, log, ln, abs, eksponen, π, e) — **kode dari AI tidak pernah dijalankan**. Rumus yang tidak bisa diurai ditolak dengan pesan. Hasil grafik dilihat dulu lalu "Tempel ke papan", sama seperti hasil teks.
- Grafik di papan: penggeser parameter bisa digeser langsung dengan jari saat alat apa pun aktif (kecuali Geser); perubahan nilai tersimpan dan bisa di-Undo. Grafik dipindah/diubah ukuran/dihapus dengan Pilih seperti gambar; Penghapus tidak menghapus grafik.

**Kasus gagal / edge case:**
- Tidak ada area yang dipilih untuk "Pecah soal" atau "Buat soal serupa" → ajakan melingkari soal.
- AI tidak bisa membaca isi area → pesan penjelasan; papan tidak berubah.
- Server atau AI tidak menjawab dalam batas waktu → pesan gagal dengan Coba lagi; papan tidak berubah.
- Penyedia terpilih gagal (kuota habis, kunci API di server salah, tidak menjawab) → server otomatis pindah ke Ollama cloud; guru tetap menerima hasil dengan keterangan kecil "dijawab oleh Ollama cloud".
- Penyedia terpilih **dan** Ollama cloud sama-sama gagal → pesan bahwa AI sedang tidak tersedia; papan tidak berubah; fitur lain tetap jalan.
- PIN yang tersimpan di panel ditolak server (mis. PIN sudah diganti) → pesan yang mengarahkan ke Pengaturan.

### 5.8 Pengaturan Koneksi
**Deskripsi:** Admin memasukkan alamat server dan PIN admin (sekali saat memasang aplikasi), mengetes koneksi, lalu memilih penyedia dan model AI. Guru hanya melihat pengaturan.

**Alur:**
```
Beranda → Pengaturan → (pertama kali: langsung bisa diisi; sesudahnya: Ubah (admin) + PIN) → isi alamat server dan PIN admin → Tes koneksi → Simpan
Pengaturan → bagian Asisten AI → pilih Penyedia → pilih Model → Tes AI → Simpan
```

**Requirement terkait:** REQ-17, REQ-19

**Layar & tugas terkait:** SCR-06 · TSK-08, TSK-09 — lihat `docs/ux-flow.md`

**Aturan bisnis:**
- Alamat server wajib diawali `https://` (produksi: subdomain karyabangsa lewat Cloudflare Tunnel, P-05). `http://` hanya diterima untuk alamat jaringan lokal (localhost, 10.x, 172.16–31.x, 192.168.x) agar server bisa diuji di jaringan sekolah.
- PIN admin disimpan di penyimpanan aman Android (Keystore), bukan di berkas biasa, dan dipakai panel untuk setiap permintaan ke server (P-11).
- Setelah pengaturan pertama tersimpan, seluruh isian Pengaturan terkunci; "Ubah (admin)" membukanya dengan PIN admin (dicocokkan ke server, atau ke PIN tersimpan bila server tak terjangkau sehingga alamat yang salah tetap bisa diperbaiki).
- Daftar penyedia dan model diambil dari server setelah koneksi berhasil; panel tidak pernah meminta atau menyimpan kunci API penyedia.
- Pilihan penyedia dan model berlaku untuk seluruh panel (bukan per papan) dan tersimpan sampai diganti.
- Bagian Asisten AI **hanya bisa diubah admin**: guru melihatnya sebagai tampilan baca-saja; tombol "Ubah (admin)" meminta PIN admin, lalu membuka pilihan penyedia dan model sampai layar Pengaturan ditutup.
- PIN salah 5 kali berturut-turut → bagian dikunci 5 menit (usulan).
- **Ganti PIN admin** ada di Pengaturan, setelah kunci admin terbuka: masukkan PIN lama, PIN baru, dan ulangi PIN baru. Dipakai terutama bila PIN bocor.
- PIN baru minimal 6 angka, tidak boleh sama dengan PIN lama, dan tidak boleh deret mudah seperti 123456 atau 111111 (usulan).
- Setelah PIN diganti, kunci admin yang sedang terbuka di panel lain langsung tertutup dan harus memakai PIN baru.
- Setiap penggantian PIN dicatat di server (waktu dan panel asal, tanpa isi PIN).
- "Tes AI" mengirim permintaan pendek ke penyedia terpilih lewat server dan menampilkan hasil serta lama waktunya.
- Hapus papan dan pemakaian AI tidak dilindungi PIN (P-11).
- PIN admin yang diganti dari satu panel membuat panel lain ditolak server sampai admin memasukkan PIN baru di Pengaturan panel itu.

**Kasus gagal / edge case:**
- Alamat salah format → pesan validasi.
- Server tidak terjangkau → pesan gagal yang menyebut alamat yang dicoba.
- PIN ditolak server → pesan yang membedakan "PIN salah" dari "server tidak terjangkau".
- Server belum mengaktifkan penyedia AI apa pun → bagian Asisten AI menjelaskan bahwa operator perlu mengaktifkannya; fitur lain tetap jalan.
- Tes AI gagal (kunci API penyedia ditolak, kuota habis, model tidak ada) → pesan yang menyebut penyedia dan penyebabnya; pilihan tetap bisa disimpan.
- Ganti PIN: PIN lama salah → ditolak (dihitung ke batas 5 kali salah); PIN baru dan ulangannya berbeda → pesan validasi; server tidak terjangkau → PIN tidak berubah dan admin diberi tahu.
- PIN bocor dan sudah diganti oleh orang lain lebih dulu → operator mengatur ulang PIN lewat konfigurasi server.

---

## 6. Hak Akses

| Aksi | Guru (pemegang panel) | Siswa penulis | Penerima PDF | Operator |
|---|---|---|---|---|
| Menulis, menghapus, undo/redo | ✅ | ✅ | ❌ | ❌ |
| Buat, buka, ganti nama, hapus papan | ✅ | ✅* | ❌ | ❌ |
| Bagikan PDF (buat QR) | ✅ | ✅* | ❌ | ❌ |
| Pakai asisten AI | ✅ | ✅* | ❌ | ❌ |
| Ubah Pengaturan koneksi | ✅* | ✅* | ❌ | ✅ |
| Pilih penyedia dan model AI di panel | ❌ (hanya lihat) | ❌ | ❌ | ✅ (dengan PIN admin) |
| Ganti PIN admin di Pengaturan | ❌ | ❌ | ❌ | ✅ (dengan PIN lama) |
| Atur ulang PIN admin tanpa PIN lama | ❌ | ❌ | ❌ | ✅ (berkas konfigurasi server) |
| Unduh PDF lewat tautan | — | — | ✅ (selama tautan berlaku) | ✅ |
| Atur kunci API dan daftar penyedia/model AI, serta masa berlaku tautan | ❌ | ❌ | ❌ | ✅ (berkas konfigurasi server) |

> *Aplikasi tanpa login: siapa pun yang memegang panel dapat melakukan aksi ini. Apakah aksi tertentu (hapus papan, Pengaturan, AI) perlu dibatasi PIN adalah pertanyaan terbuka P-11.

### 6.1 Lingkup Data (Data Scoping)
Tidak berlaku: aplikasi untuk satu sekolah, tanpa multi-unit atau multi-pengguna.

---

## 7. Kebutuhan Non-Fungsional

**Jenis project:** ☐ Website publik  ☐ Aplikasi internal  ☑ API / layanan  ☑ Aplikasi mobile/PWA (Android, untuk panel)
> Halaman unduh di HP siswa hanyalah satu halaman web kecil milik layanan; kebutuhannya tercakup di NFR-02 dan NFR-12.

### 7.1 Umum (berlaku untuk semua)
| ID | Aspek | Target |
|---|---|---|
| NFR-01 | Keamanan | Kunci API semua penyedia AI hanya di server (tidak ada di APK, tidak muncul di log). Semua permintaan aplikasi ke server memakai HTTPS (http hanya untuk server lokal di jaringan sekolah selama P-05) dan PIN admin. Token tautan PDF acak dan tidak bisa ditebak. Batas laju permintaan di server mencegah penyalahgunaan AI. Validasi tipe dan ukuran berkas unggahan. |
| NFR-02 | Responsif | Aplikasi mengikuti ukuran layar panel (resolusi menunggu P-01) dan mode lanskap. Halaman unduh nyaman dibaca di HP lebar 360 px ke atas. |
| NFR-03 | Bahasa | Seluruh antarmuka dan pesan error dalam Bahasa Indonesia. |
| NFR-04 | Zona waktu | Simpan UTC; tampilkan WIB (Asia/Jakarta). |
| NFR-05 | Backup & restore | Papan di panel: salinan otomatis terakhir untuk pemulihan berkas rusak (lihat 5.3). Cadangan papan keluar panel (berkas) tidak dibuat di versi pertama (P-09). Server hanya menyimpan salinan sementara sehingga tidak perlu backup; konfigurasi server (termasuk kunci API penyedia AI) dicadangkan operator. |
| NFR-06 | Usabilitas & aksesibilitas | Dirancang untuk layar sentuh besar yang dipakai sambil berdiri: tombol utama ≥ 64 dp dan tombol lain ≥ 48 dp, teks antarmuka ≥ 20 sp, kontras teks ≥ 4.5:1, bilah alat dapat dijangkau dari dua sisi layar (semua angka usulan). Empat state (memuat, kosong, gagal, berhasil) tertulis per layar. Tugas utama lolos uji dengan 2 guru nyata tanpa bantuan. |

### 7.3 Aplikasi internal / data sensitif (yang relevan)
| ID | Aspek | Target |
|---|---|---|
| NFR-21 | Privasi data | Isi papan bisa memuat nama atau tulisan siswa. Isi yang dikirim ke AI dikirim ke layanan pihak ketiga di internet; layar AI memberi peringatan agar tidak menyertakan nama siswa. Isi papan dan hasil AI tidak dicatat di server. Setiap penyedia punya kebijakan data sendiri; operator hanya mengaktifkan penyedia yang kebijakannya diterima sekolah. PDF di server dihapus saat kedaluwarsa. Apakah kebijakan yayasan membatasi pengiriman konten ke layanan AI cloud menunggu P-12b. |
| NFR-23 | Offline / koneksi lemah | Semua fitur menulis, halaman, gambar, bentuk, latar, dan penyimpanan bekerja tanpa internet. Hanya REQ-10 (bila memakai model unduhan), REQ-12, dan REQ-13–15 membutuhkan koneksi, dan gagal dengan pesan jelas tanpa merusak papan. |

### 7.4 Khusus project ini
| ID | Aspek | Target |
|---|---|---|
| NFR-30 | Kemulusan menulis | Ujung goresan mengikuti ujung jari/stylus tanpa jeda yang terlihat. Target usulan: rata-rata ≥ 55 fps menulis 1 jari dan ≥ 45 fps menulis 3 jari bersamaan pada halaman berisi 3.000 goresan. Angka dikalibrasi setelah pengukuran di panel pada Checkpoint 1. |
| NFR-31 | Kompatibilitas perangkat | Berjalan di panel Hisense yang dipakai sekolah (model dan versi Android menunggu P-01). Aplikasi tidak bergantung pada layanan yang tidak ada di panel, atau memberi tahu bila fitur tidak tersedia. |
| NFR-32 | Ketahanan data | Kehilangan data akibat aplikasi tertutup mendadak paling banyak 5 detik tulisan terakhir (usulan). |
| NFR-33 | Kecepatan bagikan dan AI | Kode QR tampil dalam ≤ 15 detik untuk papan 10 halaman pada Wi-Fi sekolah (usulan). Aksi AI menampilkan indikator proses dan menyerah dengan pesan jelas setelah 60 detik (usulan). |

---

## 8. Tech Stack

> Dipilih berdasarkan kebutuhan; alasan ditulis agar keputusan bisa ditinjau ulang.

| Lapisan | Pilihan | Alasan |
|---|---|---|
| Jenis aplikasi | Aplikasi Android (target panel Hisense IFP) + layanan API perantara | Panel berbasis Android; AI dan berbagi PDF butuh server sebagai perantara |
| Bahasa & runtime (aplikasi) | Dart / Flutter | Dipilih pemilik; render kanvas dengan performa tinggi dan satu basis kode |
| Kanvas & gambar | `CustomPainter` + `perfect_freehand` untuk goresan; penanganan sentuhan lewat `Listener` untuk multi-touch (usulan) | Goresan halus dengan ketebalan dinamis; menangkap beberapa jari sekaligus |
| Ekspor PDF & QR | Paket `pdf` dan `qr_flutter` (usulan) | Membuat PDF di panel dan menampilkan QR tanpa server tambahan |
| Pengenalan tulisan | Menunggu P-04 (kandidat: ML Kit Digital Ink di perangkat; atau lewat server) | Bergantung pada ada tidaknya Google Play Services di panel |
| Penyimpanan di panel | SQLite lokal (`sqflite`, diputuskan P-09) | Menyimpan papan, halaman, objek, dan salinan otomatis dengan andal |
| Bahasa & runtime (server) | Python | Dipilih pemilik |
| Framework backend | FastAPI | Dipilih pemilik |
| Database server | SQLite (usulan) | Hanya menyimpan tautan berbagi dan catatan permintaan AI; tidak perlu server database terpisah |
| Autentikasi | PIN admin (hash scrypt di server) dikirim aplikasi di header setiap permintaan; batas 5 salah → kunci 5 menit per alamat (P-11) | Aplikasi tanpa login; cukup mencegah orang luar memakai server dan kuota AI |
| Integrasi eksternal | Penyedia AI lewat server perantara: Ollama cloud (aktif sejak awal, sekaligus cadangan), lalu OpenAI, Anthropic Claude, Google Gemini, dan layanan kompatibel API OpenAI bila diaktifkan | Dipilih pemilik; admin bisa berganti penyedia tanpa memperbarui APK |
| Adaptor AI di server | Modul adaptor tipis per jenis (`ollama`, `openai`, `anthropic`, `gemini`, `openai_kompatibel`) di atas `httpx`, dengan satu antarmuka `jalankan(aksi, isi, model)` (usulan) | Menambah penyedia baru cukup lewat konfigurasi (bila kompatibel OpenAI) atau satu adaptor baru; aplikasi tidak berubah |
| Hosting server | VPS karyabangsa (Hostinger, Ubuntu 24.04): layanan systemd milik `sukardi` di `127.0.0.1`, nginx berdasarkan `server_name`, HTTPS lewat Cloudflare Tunnel yang sama dengan aplikasi sekolah lain (P-05). Subdomain: `papan.karyabangsa.sch.id` (dikonfirmasi pemilik 2026-10-14), port lokal 3030, kode disalin langsung (tanpa repo GitHub) | Pilihan pemilik; pola yang sama dengan aplikasi lain di VPS itu |

**Pertimbangan pemilihan:** satu pengelola (operator) dengan ekosistem Python dan server sendiri; aplikasi hanya untuk panel sekolah sendiri sehingga tidak ada kebutuhan toko aplikasi atau multi-tenant; keamanan kunci AI menuntut perantara.

---

## 8A. Data Awal & Deployment

### 8A.1 Data awal / migrasi
| Data | Sumber | Cara masuk | Penanggung jawab |
|---|---|---|---|
| Papan bawaan Hisense | — | Tidak dimigrasi | — |
| Kunci API penyedia AI (Ollama, OpenAI, Anthropic, Google, dll.) | Akun masing-masing penyedia milik pemilik/sekolah | Variabel lingkungan di server; daftar penyedia dan model di berkas konfigurasi, bukan di kode | Sukardi |
| PIN admin | Ditentukan admin | Hash di konfigurasi server (atau `python -m app.atur_pin`); dimasukkan sekali di Pengaturan tiap panel | Sukardi |

### 8A.2 Deployment & rollback
- **Lingkungan:** pengembangan lokal (emulator dan perangkat Android) → uji di panel Hisense sekolah. Server: pengembangan lokal → server sekolah (hosting menunggu P-05).
- **Cara deploy aplikasi:** admin memasang APK rilis **langsung ke panel** (sideload manual, tanpa toko aplikasi). Pemasangan dari sumber tidak dikenal harus diizinkan di panel. Pembaruan dipasang dengan cara yang sama di atas versi lama, sehingga papan tersimpan tetap ada. Karena itu APK rilis harus selalu ditandatangani dengan **kunci tanda tangan yang sama**, dan kunci itu dicadangkan admin; kalau kunci berbeda, aplikasi lama harus dihapus dulu dan papan di panel ikut hilang.
- **Cara deploy server:** tarik kode, instal dependensi, jalankan migrasi SQLite, mulai ulang layanan.
- **Sebelum deploy produksi:** cadangkan konfigurasi server.
- **Rencana rollback:** simpan APK versi sebelumnya dan pasang ulang; di server, kembali ke tag rilis sebelumnya.
- **Migrasi database:** hanya yang bisa di-rollback; format penyimpanan papan di panel punya nomor versi agar APK baru tetap membuka papan lama.

---

## 9. Rencana Bertahap (Checkpoints)

> AI mengerjakan satu checkpoint sampai lolos verifikasi sebelum lanjut ke berikutnya.
> Checkpoint yang membuat tampilan hanya boleh dimulai bila kartu layarnya di `docs/ux-flow.md` sudah **Disetujui**.

| # | Checkpoint | Hasil yang bisa dicek | Status |
|---|---|---|---|
| 1 | Setup Flutter dan uji perangkat | Kanvas coretan sederhana terpasang di panel Hisense; model panel, versi Android, ada tidaknya Google Play Services, dan fps menulis tercatat; APK berhasil dipasang langsung ke panel (menutup P-01 dan mengkalibrasi NFR-30) | 🔄 kode & APK uji siap; menunggu uji di panel |
| 2 | Menulis inti | REQ-01 s/d REQ-04 dan NFR-30 lolos di panel | 🔄 test otomatis lolos; menunggu uji di panel |
| 3 | Halaman dan penyimpanan | REQ-05, REQ-06, REQ-18 (bagian lokal), NFR-32 lolos | 🔄 test otomatis lolos; menunggu uji di panel |
| 4 | Konten: gambar, bentuk, latar | REQ-07, REQ-08, REQ-09 lolos | 🔄 test otomatis lolos; menunggu uji di panel |
| 5 | Server AI lokal dan Pengaturan | Server FastAPI (PIN admin, daftar penyedia, adaptor AI + cadangan Ollama, catatan permintaan) dan SCR-06; REQ-17, REQ-19 (bagian server & Pengaturan), NFR-01 lolos. *(Ekspor PDF & QR ditunda — P-12)* | 🔄 test server & aplikasi lolos; server online di papan.karyabangsa.sch.id (2026-10-14); menunggu kunci Ollama + PIN dari pemilik |
| 6 | Tulisan menjadi teks dan asisten AI | REQ-10, REQ-13 s/d REQ-16, REQ-19, REQ-20, NFR-21, NFR-33 (AI) lolos; ketiga aksi AI diuji pada setiap penyedia yang diaktifkan | 🔄 REQ-13–16, REQ-19, REQ-20 selesai di kode (test lolos, pratinjau web); REQ-10 belum; uji AI nyata menunggu server VPS |
| 7 | Menu pintar, Rapikan rumus, Selesaikan | REQ-22 lolos: lingkari → pengenalan otomatis → aksi sesuai jenis; rumus rapi menggantikan tulisan (Undo kembali); penyelesaian persamaan benar | 🔄 selesai di kode (217 test aplikasi, 134 pytest); server 0.7.0 di VPS (uji HTTPS lolos); menunggu uji di panel |
| 8 | Bangun ruang 3D | REQ-23 lolos | 🔄 selesai di kode (geometri 22 test, papan 8 test); menunggu uji di panel |
| 9 | Kimia + video eksperimen | REQ-24 lolos | 🔄 selesai di kode (server 27 test, aplikasi 6 test); katalog video masih kosong — diisi operator; menunggu uji di panel |
| 10 | Rekam kelas + ringkasan | REQ-25 lolos | 🔄 selesai di kode (server 8 test, aplikasi 8 test); menunggu uji di panel |
| 11 | Simulasi fisika (Peraga) | REQ-26 lolos | 🔄 selesai di kode; menunggu uji di panel |
| 12 | Kuis siswa di papan | REQ-27 lolos | 🔄 selesai di kode; menunggu uji di panel |
| 13 | Lab kimia virtual | REQ-28 lolos | 🔄 selesai di kode; menunggu uji di panel |
| 14 | Sketsa → 3D, gaya kapur, tema papan | REQ-23 (sketsa), REQ-29 lolos | 🔄 selesai di kode; menunggu uji di panel |
| 15 | Tabel → grafik | REQ-21 lolos | 🔄 selesai di kode (AC-180–AC-186 lolos, 13 test); menunggu uji di panel (AC-187) |
| 16 | Bahasa Mandarin | REQ-30 lolos (didahului uji akurasi pengenal Hanzi tulisan tangan dan cek suara zh-CN di panel) | ☐ |
| 17 | Uji pengguna dan poles UX | Uji tugas dengan 2 guru nyata (TSK-01, TSK-02, TSK-03) lolos; A11Y dan kepatuhan design system lolos | ☐ |
| 18 | Pasang di panel | APK rilis terpasang di panel sekolah dan dipakai satu pelajaran penuh tanpa kendala besar | ☐ |

---

> Posisi terakhir pengerjaan checkpoint dicatat di `PROGRESS.md`.

---

## 10. Pertanyaan Terbuka

Jangan diasumsikan oleh AI. Yang ditandai ▶ menghambat checkpoint tertentu.

- [ ] **P-01** ▶ (Checkpoint 1) Model panel Hisense, versi Android, resolusi, jumlah titik sentuh, dukungan stylus, dan ada tidaknya Google Play Services. *(Cara pasang sudah diputuskan: APK dipasang langsung ke panel oleh admin.)*
- [x] **P-02** *(Diputuskan 2026-10-14: usulan disetujui — mode Geser eksplisit, semua jari menulis di mode Pena; telapak tangan ditinjau setelah P-01.)* (Checkpoint 2) Aturan gestur: bagaimana menulis oleh banyak jari dibedakan dari geser/zoom dua jari, dan apakah telapak tangan dihapus otomatis. *Usulan:* mode "Geser" yang dipilih eksplisit; saat mode Pena, semua jari menulis; penghapus telapak bila panel melaporkan ukuran sentuhan.
- [x] **P-03** *(Diputuskan 2026-10-14: gambar area terpilih dikirim ke model AI yang bisa membaca gambar; model bergambar Ollama cloud dipilih operator di `penyedia.toml`.)* (Checkpoint 6) Model yang diaktifkan untuk tiap penyedia, mana yang mendukung gambar, batas pemakaian atau biaya, dan cara isi papan dikirim ke AI (teks hasil pengenalan tulisan atau gambar area).
- [ ] **P-04** ▶ (Checkpoint 6) Pengenalan tulisan tangan: di perangkat (ML Kit, butuh Google Play Services) atau lewat server/AI bila panel tanpa layanan Google.
- [x] **P-05** *(Diputuskan 2026-10-14: server di VPS karyabangsa; dikembangkan dan diuji lokal dulu. Masa berlaku tautan PDF ikut ditunda bersama REQ-12.)* (Checkpoint 5) Hosting server FastAPI: di mana dipasang, alamat dan HTTPS, serta masa berlaku tautan PDF (usulan 24 jam).
- [x] **P-06** *(Diputuskan 2026-10-14: dari penyimpanan panel.)* (Checkpoint 4) Cara guru memasukkan gambar dan PDF ke panel: flashdisk, penyimpanan panel, Google Drive, atau kamera.
- [x] **P-07** *(Diputuskan 2026-10-14: keduanya — menu dan dirapikan otomatis.)* (Checkpoint 4) Mekanisme "bentuk": memilih jenis dari menu, dirapikan otomatis dari goresan, atau keduanya.
- [ ] **P-08** (Checkpoint 2–4) Batas ukuran kanvas, jumlah halaman maksimum per papan, serta batas ukuran PDF/gambar.
- [x] **P-09** *(Diputuskan 2026-10-14: SQLite. Cadangan ke berkas tidak diminta, jadi tidak dibuat di versi pertama.)* Penyimpanan di panel: setuju SQLite? Perlu cadangan papan keluar panel (berkas)?
- [x] **P-10** *(Diputuskan 2026-10-14: langsung ke papan terakhir.)* Layar awal: langsung ke papan terakhir (usulan, mulai menulis lebih cepat) atau ke daftar papan.
- [x] **P-11** *(Diputuskan 2026-10-14: tanpa kunci perangkat; panel memakai PIN yang ditentukan admin. Hapus papan dan AI tanpa PIN.)* (Checkpoint 5) Kunci perangkat: cara membuat dan membagikannya, dan apakah Pengaturan, hapus papan, dan AI perlu dilindungi PIN.
- [x] **P-12** *(Sebagian, 2026-10-14: Bagikan PDF + QR ditunda dulu.)* Bila waktu mepet, fitur mana yang ditunda lebih dulu dari versi pertama?
- [ ] **P-12b** Apakah ada kebijakan yayasan yang membatasi pengiriman isi papan ke layanan AI cloud pihak ketiga?
- [x] **P-14** Siapa yang boleh mengganti penyedia/model AI di panel → **admin saja** (lihat Log Keputusan 2026-10-14).
- [x] **P-15** Perilaku bila penyedia gagal → **otomatis pindah ke Ollama cloud**.
- [x] **P-16** Penyedia pertama → **Ollama cloud saja dulu**; penyedia lain disiapkan nonaktif.
- [x] **P-17** Cara mengganti PIN admin bila bocor → **di layar Pengaturan** (dengan PIN lama); operator bisa mengatur ulang lewat server sebagai jalan darurat.
- [x] **P-18** Pemegang PIN admin → **hanya admin (Sukardi, peran Operator)**; PIN tidak dibagikan ke guru.
- [x] **P-13** *(Diputuskan 2026-10-14: PDF jadi banyak halaman papan, paling banyak 5 halaman.)* (Checkpoint 4) PDF latar banyak halaman: otomatis jadi banyak halaman papan (usulan), atau dipilih satu per satu?

---

## 11. Log Keputusan

| Tanggal | Keputusan | Alasan |
|---|---|---|
| 2026-10-14 | Aplikasi dibuat dengan Flutter untuk panel Hisense IFP | Pilihan pemilik; layar sentuh multi-touch berbasis Android |
| 2026-10-14 | Prioritas versi pertama: menulis mulus + penghapus, multi-halaman + kanvas luas, ekspor PDF + QR, tulisan tangan → teks, bentuk, gambar | Dipilih semua oleh pemilik |
| 2026-10-14 | Tugas guru paling sering: menulis materi, membahas soal, mengajar dengan PDF di latar, siswa menulis jawaban | Jawaban wawancara |
| 2026-10-14 | AI via Ollama cloud: pecah soal jadi langkah, buat soal serupa, ringkas papan | Jawaban wawancara; "tulisan tangan → teks" dipisah dari AI (REQ-10) |
| 2026-10-14 | Pengguna hanya sekolah sendiri; dipasang manual lewat APK | Tidak ada kebutuhan toko aplikasi atau lisensi |
| 2026-10-14 | Ambisi: sederhana tetapi sangat mulus | Jawaban wawancara; kualitas menulis jadi tolok ukur utama |
| 2026-10-14 | Tanpa login; papan tersimpan di panel | Alur tercepat untuk guru |
| 2026-10-14 | Server perantara memakai Python FastAPI; kunci Ollama hanya di server | Kunci tidak boleh ada di APK |
| 2026-10-14 | Berbagi PDF: unggah ke server sekolah, QR berisi tautan sementara | Siswa bisa unduh dari HP tanpa kabel |
| 2026-10-14 | Tampilan netral dan minimalis; kanvas jadi fokus | Jawaban wawancara |
| 2026-10-14 | Langkah pertama: SPEC.md dan alur UX dulu, baru kode | Pola SDD |
| 2026-10-14 | Asisten AI multi-penyedia (Ollama cloud, OpenAI, Claude, Gemini, dan layanan kompatibel OpenAI), dipilih di Pengaturan | Permintaan pemilik. Kunci API tetap hanya di server (REQ-16 dipertahankan); panel hanya memilih dari daftar yang diaktifkan operator |
| 2026-10-14 | Penyedia/model AI hanya bisa diganti admin (PIN admin) | Jawaban pemilik (P-14) |
| 2026-10-14 | Penyedia gagal → server otomatis pindah ke Ollama cloud | Jawaban pemilik (P-15) |
| 2026-10-14 | Tahap awal hanya memakai kunci API Ollama cloud | Jawaban pemilik (P-16); penyedia lain dinyalakan belakangan |
| 2026-10-14 | PIN admin hanya dipegang admin (Sukardi); tidak dibagikan ke guru | Jawaban pemilik (P-18) |
| 2026-10-14 | APK dipasang langsung ke panel oleh admin (sideload manual) | Jawaban pemilik (sebagian P-01) |
| 2026-10-14 | SPEC dan ux-flow disetujui; pembangunan dimulai dari Checkpoint 1 | Persetujuan pemilik |
| 2026-10-14 | P-02: geser/zoom hanya lewat alat Geser; di mode Pena semua jari menulis | Pemilik menyetujui usulan ("Lanjutkan") |
| 2026-10-14 | P-09: penyimpanan SQLite; P-10: aplikasi langsung membuka papan terakhir | Jawaban pemilik |
| 2026-10-14 | Bagikan PDF + QR (REQ-11, REQ-12) ditunda; PIN admin menggantikan kunci perangkat; server lokal dulu | Jawaban pemilik (P-12, P-11, P-05) |
| 2026-10-14 | Server dipasang di VPS karyabangsa (P-05) | Jawaban pemilik |
| 2026-10-14 | Subdomain server `papan.karyabangsa.sch.id`, kode disalin langsung | Jawaban pemilik |
| 2026-10-15 | SPEC 1.13: REQ-30 Mandarin disetujui — lingkari tulisan, pinyin & arti dari kamus di server (bukan AI), terjemahan kalimat AI berlabel, TTS panel, kartu di papan; Checkpoint 16 baru (uji → 17, pasang → 18) | Persetujuan pemilik ("Rincian Mandarin 1.13 disetujui") |
| 2026-10-15 | SPEC 1.12: REQ-21 Tabel → grafik disetujui (ketik di sel, guru memilih Garis/Batang/Titik, di panel tanpa AI, grafik terhubung ke tabel; rincian usulan 1.7 ikut disetujui); Checkpoint 15 baru, uji pengguna & pasang jadi 16–17 | Persetujuan pemilik ("kita setujui keduanya") |
| 2026-10-15 | SPEC 1.11: simulasi fisika, kuis, lab kimia virtual, sketsa → 3D, kapur + tema papan (dari prototipe HTML) | Pilihan pemilik |
| 2026-10-15 | SPEC 1.9: susunan fitur mengikuti panduan Smart Blackboard; urutan: menu pintar → 3D → kimia → rekam; tetap Flutter | Pilihan pemilik |
| 2026-10-15 | SPEC naik ke 1.8; server 0.6.0 dipasang di VPS (pengenal rumus + SymPy) | Persetujuan pemilik ("lanjutkan saja pasang di server dulu") |
| 2026-10-15 | Jadikan grafik tanpa AI/LLM: pengenal rumus Pix2Text MFR di VPS + SymPy untuk validasi; grafik tetap penggambar sendiri; aksi teks AI dibahas nanti (usulan 1.8) | Persetujuan pemilik |
| 2026-10-14 | REQ-20 grafik interaktif dari rumus tulisan tangan (dari video referensi); P-03: gambar area ke AI vision | Persetujuan pemilik |
| 2026-10-14 | P-06: berkas dari penyimpanan panel; P-07: bentuk lewat menu dan dirapikan otomatis; P-13: PDF maksimal 5 halaman | Jawaban pemilik |
| 2026-10-14 | PIN admin diganti dari layar Pengaturan bila bocor | Jawaban pemilik (P-17); atur ulang lewat server tetap ada sebagai jalan darurat |

---

## 12. Riwayat Perubahan SPEC

> Setiap perubahan SPEC setelah status "Disepakati" wajib dicatat di sini.
> AI menulis usulan dengan status **Diusulkan**; hanya pemilik yang mengubahnya menjadi **Disetujui**.

| Versi | Tanggal | Bagian | Perubahan | Diusulkan oleh | Status |
|---|---|---|---|---|---|
| 0.1 | 2026-10-14 | Semua | Draft awal hasil wawancara | AI | Draft (menunggu persetujuan pemilik) |
| 0.2 | 2026-10-14 | §1, §2, §3.1, §4.5–4.5b, §5.7, §5.8, §6, §7, §8, §8A, §9, §10, §11 | Tambah REQ-19 multi-penyedia AI; konfigurasi penyedia di server; pilihan penyedia/model di Pengaturan; P-14–P-16 | Pemilik (permintaan), ditulis AI | Draft (menunggu persetujuan pemilik) |
| 0.3 | 2026-10-14 | §3.1, §4.5–4.5a, §5.7, §5.8, §6, §8, §10, §11 | P-14–P-16 diputuskan: hanya admin (PIN) yang mengganti penyedia; cadangan otomatis ke Ollama cloud; awal hanya Ollama cloud. Tambah P-17 | Pemilik (jawaban), ditulis AI | Draft (menunggu persetujuan pemilik) |
| 0.4 | 2026-10-14 | §4.5a, §5.8, §6, §10, §11 | P-17 diputuskan: Ganti PIN admin di Pengaturan; atur ulang darurat lewat server. Tambah P-18 | Pemilik (jawaban), ditulis AI | Draft (menunggu persetujuan pemilik) |
| 0.5 | 2026-10-14 | §2, §10, §11 | P-18 diputuskan: PIN admin hanya dipegang admin | Pemilik (jawaban), ditulis AI | Draft (menunggu persetujuan pemilik) |
| 0.6 | 2026-10-14 | §8A.2, §9, §10, §11 | Cara pasang APK diputuskan: langsung ke panel; syarat kunci tanda tangan tetap sama | Pemilik (jawaban), ditulis AI | Draft (menunggu persetujuan pemilik) |
| 1.0 | 2026-10-14 | Semua | SPEC v0.1–0.6 disetujui pemilik dan berstatus Disepakati; butir bertanda (usulan) dipakai sampai pemilik mengubahnya; pertanyaan terbuka diputuskan saat checkpoint-nya | Pemilik | **Disetujui** |
| 1.1 | 2026-10-14 | §5.1, §10, §11 | P-02 diputuskan (aturan gestur) | Pemilik (persetujuan usulan) | **Disetujui** |
| 1.2 | 2026-10-14 | §5.3, §7, §8, §10, §11 | P-09 (SQLite, tanpa cadangan berkas) dan P-10 (papan terakhir) diputuskan | Pemilik | **Disetujui** |
| 1.4 | 2026-10-14 | §3.1, §5.7, §5.8, §7, §8, §8A, §9, §10, §11 | Bagikan PDF/QR ditunda; PIN admin sebagai kredensial panel→server; server lokal; Checkpoint 5 diganti "Server AI lokal dan Pengaturan"; rincian SCR-06 terkunci-admin (usulan) | Pemilik (keputusan), rincian AI | **Disetujui** (rincian usulan menunggu konfirmasi) |
| 1.5 | 2026-10-14 | §5.8, §8, §10, §11 | Hosting server: VPS karyabangsa lewat Cloudflare Tunnel (P-05) | Pemilik | **Disetujui** |
| 1.6 | 2026-10-14 | §3.1, §4.3, §5.7, §10 | **Usulan dari video referensi ("AI Blackboard", WAIC 2026):** REQ-20 — guru memilih rumus tulisan tangan (mis. y = x² − 3, y = A sin x + B), lalu Asisten AI "Jadikan grafik" mengubahnya menjadi **grafik interaktif** di papan: bidang koordinat, satu kurva berwarna per rumus, dan **penggeser** untuk setiap parameter huruf (A, B, …) yang langsung menggerakkan kurva. Grafik menjadi objek baru (jenis `grafik`) yang bisa dipindah/diubah ukuran dengan Pilih, tersimpan, dan bisa di-Undo. Cara kerja: gambar area terpilih dikirim ke model AI yang bisa membaca gambar (menjawab P-03) lewat server; AI hanya mengembalikan data terstruktur (rumus, parameter, rentang), lalu panel menghitung dan menggambar kurvanya sendiri dengan pengurai rumus yang aman (bukan menjalankan kode dari AI). Pemicu: setelah area dilingkari dengan Pilih, muncul tombol "Asisten AI" seperti di video. | AI (usulan), pemilik | **Disetujui** (pemilik memilih: grafik fungsi dulu + 3 aksi lama; gambar area ke AI vision) |
| 1.3 | 2026-10-14 | §5.4, §10, §11 | P-06, P-07, P-13 diputuskan; alat Pilih untuk memindah/mengubah ukuran/menghapus gambar dan bentuk | Pemilik (jawaban), rincian usulan AI | **Disetujui** sebagian (rincian bertanda usulan menunggu konfirmasi) |
| 1.7 | 2026-10-14 | §3.1, §4.3, §5.4, §9 | **Usulan REQ-21 Tabel → grafik** (permintaan pemilik): (1) Alat **Tabel** di bilah alat: guru memilih jumlah baris dan kolom, tabel muncul sebagai objek baru (jenis `tabel`) yang bisa dipindah/diubah ukuran/dihapus/Undo dan tersimpan. (2) Isi sel **diketik** lewat keyboard layar (ketuk sel → isi); baris pertama = judul kolom (teks), kolom pertama = nilai x atau nama kategori, kolom berikutnya = seri angka (koma desimal diterima). (3) Tabel terpilih → **Jadikan grafik** → guru memilih **Garis**, **Batang**, atau **Titik**; grafik dibuat **di panel tanpa AI dan tanpa internet**. (4) Grafik **terhubung** ke tabel: mengubah angka di tabel langsung mengubah grafik; sumbu menyesuaikan otomatis; legenda dari judul kolom. *Rincian usulan AI:* batas 20 baris × 6 kolom; sel kosong/bukan angka dilewati (titik tidak digambar) dan ditandai di sel; Batang dipakai bila kolom pertama bukan angka; grafik dari tabel tidak punya penggeser; tabel dihapus → grafik tetap dengan data terakhir (tidak terhubung lagi). Butuh kartu layar baru di ux-flow (alat Tabel, pengisian sel, pilihan jenis grafik) dan AC baru; dikerjakan setelah Checkpoint 6. | Pemilik (permintaan + jawaban: ketik di sel, guru memilih jenis, di panel tanpa AI, ikut berubah), rincian AI | **Disetujui** 2026-10-15 (diterapkan di 1.12) |
| 1.8 | 2026-10-15 | §3.1, §5.5, §5.7, §8, §9 | **Usulan: Jadikan grafik tanpa AI/LLM** (permintaan pemilik). REQ-20 tidak lagi memakai model AI vision untuk membaca rumus. Alur baru: (1) **Pengenal rumus** khusus matematika mengubah tulisan tangan di area terpilih menjadi ekspresi LaTeX — usulan: **Pix2Text MFR** (sumber terbuka, ONNX, jalan di CPU VPS karyabangsa, gratis; akurasi tulisan tangan perlu diuji dulu dengan contoh nyata). Alternatif: Mathpix `v3/strokes` (layanan berbayar ±US$0,002/permintaan, menerima koordinat goresan, paling akurat) atau MyScript iink (di panel, offline, lisensi berbayar, harga tidak dipublikasikan). (2) **Mesin matematika SymPy** di server: LaTeX → ekspresi SymPy; validasi (hanya fungsi yang diizinkan, x sebagai peubah, huruf lain menjadi parameter dengan rentang bawaan −5…5, uji hitung pada beberapa titik); bila tidak valid → pesan "tidak menemukan rumus". Server mengirim rumus yang sudah dinormalkan; panel tetap menghitung dengan pengurai amannya sendiri. (3) **Grafik interaktif**: usulan tetap memakai penggambar grafik buatan sendiri (CustomPainter, sudah jadi, offline, ringan di jalur menulis); pembanding: equation_painter (Flutter), JSXGraph di WebView (paling lengkap, tetapi berat dan tidak bisa menyatu dengan kanvas), fl_chart (untuk grafik data/tabel REQ-21, bukan plot fungsi). (4) Aksi teks (Pecah soal, Soal serupa, Ringkas) tetap memakai AI sampai dibahas ulang ("pemanfaatan AI nanti didiskusikan"). Dampak: P-03 (gambar area ke AI vision) dibatalkan untuk Jadikan grafik; AC-83, AC-85, AC-88 ditulis ulang; dependency server baru pix2text/onnxruntime + sympy (+ antlr4-python3-runtime untuk parse LaTeX). | Pemilik (arah), rincian & pilihan pustaka AI | **Disetujui** 2026-10-15 (pemilik memilih Pix2Text di VPS + penggambar grafik sendiri; syarat: lolos uji akurasi dengan tulisan tangan nyata dari panel) |
| 1.9 | 2026-10-15 | §3.1, §9 | **Rombak susunan fitur mengikuti "Panduan Arsitektur Smart Blackboard AI"** (dokumen dari pemilik). Teknologi tetap Flutter + server FastAPI (panduan sendiri menyebut Flutter CustomPainter untuk tablet; React/Tldraw ditolak karena membuang fitur yang sudah jalan). Tambah REQ-22 menu pintar + Rapikan rumus + Selesaikan, REQ-23 bangun ruang 3D, REQ-24 kimia + video, REQ-25 rekam kelas + ringkasan; checkpoint 7–10 baru, uji pengguna & pasang jadi 11–12. Rincian REQ-22 (pilihan pemilik): pengenalan otomatis saat dilingkari; Rapikan mengganti tulisan di tempatnya. Rumus cetak dibuat server (matplotlib mathtext → PNG transparan berwarna tinta) dan masuk papan sebagai objek gambar (pindah/ubah ukuran/hapus/Undo seperti gambar). Efek kapur di papan biasa (panduan §5) tidak relevan: butuh sensor perangkat keras | Pemilik (urutan prioritas & teknologi), rincian AI | **Disetujui** 2026-10-15 |
| 1.10 | 2026-10-15 | §4.3, §9 | **Rincian Checkpoint 8–10 (usulan AI, pemilik meminta "bangun semuanya dulu, uji nanti")**. REQ-23: objek baru jenis `bangun` (bentuk, posisi/ukuran, putar, buka jaring 0–1, bidang potong) di menu Bentuk baris kedua (Kubus, Balok, Prisma segitiga, Limas segiempat, Tabung, Kerucut, Bola); diputar dengan menggeser jari di atasnya dengan alat apa pun kecuali Pilih/Geser (Pilih = pindah/ubah ukuran); tombol di dalam objek "Jaring-jaring"/"Tutup jaring" (animasi engsel, pandangan miring ke atas) dan "Bidang potong" (kubus/balok: bidang diagonal ACGE; prisma/limas: penampang tengah; tabung/kerucut: penampang sumbu; bola: lingkaran besar); label titik sudut; rusuk tersembunyi putus-putus; bola tanpa jaring. REQ-24: pengenal rumus yang sama membaca rumus/reaksi kimia (aturan pembersih Cl/Fe/+), server menghitung kesetaraan (matriks atom, SymPy) — bilah: Rapikan rumus, Setarakan (bila belum setara), Video eksperimen (n); video dari katalog server `video/katalog.toml` yang diisi operator (berkas MP4/WebM di server, diputar di panel lewat video_player dengan PIN). REQ-25: tombol "Rekam" di bilah atas → persetujuan → rekam AAC 16 kHz mono (≤ 90 menit, berhenti otomatis) → kirim → server: Whisper `small` di VPS sendiri (faster-whisper, CPU) lalu ringkasan oleh penyedia AI yang aktif (cadangan Ollama) sebagai teks biasa → "Ringkasan siap" → Tempel ke papan di halaman baru. Audio dihapus di panel setelah terkirim dan di server setelah ditranskrip; transkrip tidak disimpan/dicatat. Juga: jawaban teks AI dibersihkan dari Markdown/LaTeX. Dependency baru: aplikasi `video_player`, `record`; server `faster-whisper`, `av` | AI (rincian), pemilik (arah) | **Diusulkan** (dibangun dulu atas permintaan pemilik; konfirmasi saat uji) |
| 1.11 | 2026-10-15 | §3.1, §4.3, §9 | **Dari prototipe HTML "Spark AI Smart Blackboard" milik pemilik** (pemilik memilih keempatnya, dibangun dulu lalu diuji): REQ-26 simulasi fisika, REQ-27 kuis siswa, REQ-28 lab kimia virtual, REQ-29 gaya kapur + tema papan, dan sketsa → bangun ruang (REQ-23). Rincian usulan AI: tombol bilah alat baru "Peraga" (baris fisika + Kuis, baris kimia); objek baru jenis `peraga` (jenis, posisi/ukuran, nilai penggeser) dan `kuis` (judul, pasangan); status berjalan & progres kuis tidak disimpan; peraga berjalan dan kuis digambar di lapisan hidup terpisah agar tinta ribuan goresan tetap di cache (NFR-30); badan peraga/kuis tidak menerima tinta; menu pintar menawarkan "Peraga: …" untuk rumus periode bandul/pegas dan zat kimia yang cocok, dan "Jadikan Kubus/Balok/Limas/Kerucut/Bola/Tabung" untuk sketsa persegi/segitiga/lingkaran (dikenali di panel, tanpa server); tema papan disimpan di app_state per papan; goresan menyimpan penanda kapur `k` (opsional, data lama tetap terbaca); server: jenis AI `kuis`. Prototipe memakai Gemini untuk menebak kategori dan menaruh kunci API di halaman — tidak ditiru | Pemilik (pilihan), AI (rincian) | **Diusulkan** (dibangun dulu; konfirmasi saat uji) |
| 1.12 | 2026-10-15 | §3.1, §4.3, §5.4, §9, §11 | **REQ-21 Tabel → grafik diterapkan** (usulan 1.7 disetujui): baris REQ-21 di §3.1; jenis objek `tabel` dan grafik-dari-tabel di §4.3; alur, aturan, dan kasus gagal di §5.4; Checkpoint 15 baru (uji pengguna → 16, pasang → 17). Tambahan rincian usulan AI: tombol Tambah baris/Tambah kolom, Batang berkelompok untuk beberapa seri, warna seri dari theme.dart. Kode tempelan dari luar (OCR tabel lewat AI, data contoh saat gagal) **tidak** dipakai karena bertentangan dengan REQ-21 dan aturan gagal. *Diperjelas saat Checkpoint 15 (rincian AI):* isi sel lewat dialog Isi tabel (Simpan = satu Undo, bukan satu Undo per sel); sel kosong tidak ditandai; tombol tabel di bawah tabel; tautan grafik = selama tabel sumber ada di halaman | Pemilik (persetujuan), AI (rincian) | **Disetujui** 2026-10-15 |
| 1.13 | 2026-10-15 | §3.1, §4.3, §5.7, §8, §9 | **Usulan REQ-30 Bahasa Mandarin: pinyin, arti, dan suara** (permintaan pemilik; pilihan pemilik 2026-10-15: lingkari tulisan, kamus di server, TTS di panel, kartu di papan). (1) **Masukan:** guru menulis Hanzi dengan tangan lalu melingkarinya dengan Pilih; menu pintar (REQ-22) mengirim gambar area seperti biasa, dan bila hasil pengenalan berisi aksara Han bilah menawarkan **"Pinyin & arti"**. Pengenal Hanzi tulisan tangan di server — usulan: pengenal teks Pix2Text (CnOCR, sumber terbuka, CPU VPS, satu keluarga dengan pengenal rumus); akurasi tulisan tangan **harus diuji dulu** dengan tulisan nyata guru Mandarin; alternatif bila gagal uji: model AI vision lewat penyedia yang aktif. (2) **Pinyin & arti dari kamus, bukan dikarang AI:** server memecah kalimat menjadi kata (jieba), pinyin bertanda nada dari pypinyin (termasuk perubahan nada 3-3 dan 不/一 bila pustaka mendukung; sisanya ditulis nada asli), arti per kata dari kamus CC-CEDICT (Inggris → Indonesia: usulan diterjemahkan sekali per entri oleh AI lalu disimpan sebagai berkas kamus di server dan bisa diperbaiki operator). Terjemahan **kalimat** utuh memakai penyedia AI yang aktif (cadangan Ollama) dan diberi label "Terjemahan AI — periksa sebelum dipakai"; bila AI gagal, kartu tetap muncul dengan pinyin + arti per kata tanpa terjemahan kalimat (tidak ada data contoh/palsu). (3) **Suara:** mesin TTS Android di panel lewat `flutter_tts` (dependency baru: satu-satunya cara memakai TTS bawaan dari Flutter); tombol "Dengarkan" dan "Pelan" untuk kalimat, ketuk kata di kartu = bunyi kata itu; saat aplikasi dibuka dicek apakah suara zh-CN tersedia — bila tidak, tombol suara disembunyikan dan kartu menampilkan "Suara Mandarin belum terpasang di panel. Pasang paket suara Mandarin di Pengaturan Android." Suara tidak butuh internet. (4) **Hasil = objek baru jenis `mandarin`** di samping area: Hanzi, pinyin, arti per kata, terjemahan kalimat (bila ada); pindah/ubah ukuran/hapus/Undo seperti gambar, tersimpan, badan kartu tidak menerima tinta; guru dapat mengoreksi Hanzi yang salah terbaca dengan mengetik ulang (opsional, bila keyboard Mandarin terpasang). Gagal (di bilah menu pintar, papan tidak berubah): pesan menu pintar yang sudah ada; tak ada Hanzi dikenali "Tidak ada aksara Mandarin yang dikenali. Tulis lebih jelas, lalu lingkari lagi." Dependency server baru: pypinyin, jieba, berkas CC-CEDICT (lisensi CC BY-SA, dicantumkan di README), model teks Pix2Text (ukuran dicek sebelum dipasang di VPS). NFR-21 berlaku: isi teks tidak dicatat di log. Butuh kartu ux-flow, AC baru, dan checkpoint baru (usulan 16, setelah Tabel; uji pengguna & pasang bergeser). Kode tempelan dari luar tidak dipakai (data contoh saat gagal, pinyin dari LLM, tanpa PIN) *Diperjelas saat Checkpoint 16 (2026-10-15, rincian AI):* pengenal Hanzi = model PP-OCRv4 (PaddleOCR, Apache-2.0, ±11 MB) dijalankan langsung dengan onnxruntime, tiap baris tanpa pendeteksi teks — bukan CnOCR/rapidocr (tanpa paket baru; opencv ±113 MB tidak perlu). Bacaan ditolak bila keyakinan < 0,7 atau tercampur huruf Latin/kana/angka. Uji awal dengan 100 gambar dari 5 font: tulisan rapi 60/60 benar; semi-kursif 15 benar / 2 ditolak / 3 salah; 草书 4 / 10 / 6 | Pemilik (permintaan + 4 pilihan), AI (rincian) | **Disetujui** 2026-10-15 (syarat: lolos uji akurasi Hanzi tulisan tangan dan cek suara zh-CN di panel Hisense) |
