# Design System — Whiteboard IFP

> **Layer 3: Environment (visual).** Aturan tampilan agar setiap layar konsisten.
> AI **hanya boleh** memakai token yang terdaftar di sini. Token diterapkan di `app/lib/ui/theme.dart`.

---

## 0. Mode Desain

| Area | Mode | Alasan |
|---|---|---|
| Semua layar aplikasi panel (SCR-01 s/d SCR-06) | Fungsional | Dipakai di kelas setiap hari; kanvas harus lega dan alat harus cepat dijangkau (SPEC §11: tampilan netral dan minimalis) |
| Halaman unduh di HP (SCR-07) | Fungsional | Satu tugas: unduh PDF |

- **Fungsional:** tema Material 3 bawaan Flutter; yang diubah hanya warna primer, netral, dan ukuran target sentuh untuk layar besar.
- Belum ada identitas visual wajib (logo/warna resmi). Bila pemilik memberikannya, identitas resmi menang.

---

## 1. Identitas Visual

- **Sumber:** belum ada; memakai palet netral.
- **Kesan:** tenang, bersih, tidak mengalihkan perhatian dari isi papan.
- **Hindari:** dekorasi, gradasi, animasi, warna mencolok di bilah alat.

---

## 2. Warna

### 2.1 Warna Utama
| Token | Hex | Pemakaian |
|---|---|---|
| `primary` | #1D4ED8 | Alat aktif, tombol utama, tautan |
| `onPrimary` | #FFFFFF | Teks/ikon di atas `primary` (kontras 6.7:1) |
| `primaryContainer` | #DBEAFE | Latar alat yang sedang aktif |

### 2.2 Warna Netral
| Token | Hex | Pemakaian |
|---|---|---|
| `canvas` | #FFFFFF | Latar kanvas papan |
| `text` | #111827 | Teks utama (kontras 17:1 di putih) |
| `textMuted` | #4B5563 | Teks sekunder (kontras 7.6:1 di putih) |
| `border` | #D1D5DB | Garis, pemisah, batas gambar mini |
| `surface` | #FFFFFF | Bilah alat, dialog, panel |
| `background` | #F3F4F6 | Latar di luar kanvas, daftar papan |

### 2.3 Warna Status
| Token | Hex | Pemakaian |
|---|---|---|
| `success` | #15803D | Berhasil (kontras 5.0:1 di putih) |
| `warning` | #B45309 | Peringatan (kontras 5.0:1 di putih) |
| `danger` | #B91C1C | Gagal, hapus (kontras 6.5:1 di putih) |

### 2.4 Palet Pena (isi papan, bukan antarmuka)
| Token | Hex |
|---|---|
| `penBlack` | #111827 |
| `penBlue` | #1D4ED8 |
| `penRed` | #DC2626 |
| `penGreen` | #15803D |
| `penOrange` | #EA580C |
| `penPurple` | #7C3AED |

Ketebalan pena: tipis 3, sedang 6, tebal 12 (piksel logis dasar).

**Aturan kontras:** teks antarmuka ≥ 4.5:1 terhadap latarnya.

---

## 3. Tipografi

| Peran | Font | Fallback |
|---|---|---|
| Semua teks | Roboto (bawaan Android) | sans-serif |

| Level | Ukuran | Berat |
|---|---|---|
| Judul layar | 28 sp | 600 |
| Judul bagian | 24 sp | 600 |
| Body / label tombol | 20 sp | 400 / 500 |
| Keterangan kecil | 20 sp | 400 (`textMuted`) — tidak ada teks di bawah 20 sp di panel |
| Halaman unduh (HP) | body 16 px, judul 22 px | |

---

## 4. Spasi & Tata Letak

- **Skala spasi:** 4, 8, 12, 16, 24, 32, 48, 64 dp
- **Target sentuh:** tombol utama ≥ 64 dp, tombol lain ≥ 48 dp
- **Bilah alat:** di bawah tengah layar, bisa dipindah ke kiri/kanan
- **Radius sudut:** kecil 8 · sedang 12 · besar 20
- **Bayangan:** satu level untuk bilah alat dan dialog (elevation 2)

---

## 5. Komponen

### Tombol
| Varian | Tampilan | Kapan dipakai |
|---|---|---|
| Primary (FilledButton) | Latar `primary`, teks `onPrimary` | Aksi utama (1 per layar) |
| Secondary (OutlinedButton) | Garis `border`, teks `primary` | Aksi pendamping |
| Ghost (TextButton) | Teks `primary` | Aksi ringan |
| Danger | Latar `danger`, teks putih | Hapus |

### Alat di bilah alat
- Ikon 32 dp + teks label di bawahnya; alat aktif: latar `primaryContainer` + ikon `primary` + label tebal (tidak hanya warna).

### State Kosong, Memuat, Gagal, Berhasil
- **Kosong:** 1 kalimat + 1 tombol Primary
- **Memuat:** indikator kemajuan + keterangan langkah + tombol Batalkan bila proses panjang
- **Gagal:** bilah/teks `danger` menetap sampai ditutup; sebut apa yang terjadi, apakah papan aman, dan tindakan berikutnya
- **Berhasil:** bilah kecil di atas tengah 4 detik, warna `success`

### Dialog Konfirmasi
- Judul menyebut aksi + nama/nomor data ("Hapus halaman 2?"); tombol "Hapus" varian Danger dan "Batal"

---

## 6. Ikon

- Material Symbols bawaan Flutter (`Icons.*`), ukuran 32 dp di bilah alat, 24 dp di daftar.
- Setiap ikon tanpa teks wajib punya `tooltip`/label Semantics berbahasa Indonesia.

---

## 7. Nada Bahasa

- Formal-santai, kalimat pendek, menyapa langsung tanpa "Bapak/Ibu" di tombol.
- Pesan gagal selalu menyebut bahwa papan aman bila memang aman.

---

## 8. Yang Tidak Boleh

- ❌ Warna hex di luar daftar token (semua warna lewat `theme.dart`)
- ❌ Lebih dari 1 keluarga font
- ❌ Status yang hanya dibedakan lewat warna
- ❌ Animasi dekoratif
- ❌ Teks antarmuka < 20 sp di panel
