# Server Papan Tulis

Server perantara FastAPI untuk aplikasi panel: memeriksa PIN admin, menyimpan
daftar penyedia AI, meneruskan permintaan AI (dengan cadangan otomatis ke
Ollama cloud), dan mencatat permintaan **tanpa isi papan**. Lihat `SPEC.md`
§5.7, §5.8, dan §8.

## Menjalankan lokal

```bash
cd server
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt -r requirements-dev.txt
copy penyedia.contoh.toml penyedia.toml
copy .env.example .env          # isi OLLAMA_API_KEY
.venv/Scripts/python -m app.cli atur-pin
.venv/Scripts/uvicorn app.main:app --reload --port 3030
```

Test dan lint:

```bash
.venv/Scripts/python -m pytest
.venv/Scripts/ruff check .
```

## Endpoint

Semua endpoint kecuali `/sehat` butuh header `X-PIN-Admin`. PIN salah 5 kali
dari satu alamat → semua permintaan dari alamat itu ditolak 429 selama 5 menit.

| Metode | Path | Fungsi |
|---|---|---|
| GET | `/sehat` | Cek hidup (tanpa PIN) |
| GET | `/koneksi` | Tes koneksi dari Pengaturan panel |
| GET | `/ai/penyedia` | Daftar penyedia & model aktif (tanpa kunci API) |
| POST | `/ai/tes` | Tes AI ke satu penyedia, tanpa cadangan |
| POST | `/rumus/kenali` | Menu pintar (REQ-22), **tanpa AI**: jenis isi area (fungsi/persamaan/ekspresi), data grafik, rumus cetak PNG (`rapi`), penyelesaian SymPy (`penyelesaian`) |
| GET | `/video/{id}` | Video eksperimen dari katalog (REQ-24), mendukung Range |
| POST | `/kelas/ringkas` | Rekam kelas (REQ-25): badan = rekaman AAC/M4A, header `X-Rumus` (base64 JSON) opsional → `{id}` |
| GET | `/kelas/ringkas/{id}` | Status ringkasan: antri/mentranskrip/meringkas/selesai/gagal |
| POST | `/ai/jalankan` | Aksi AI (`pecah_soal`, `soal_serupa`, `ringkas`) dengan cadangan Ollama cloud; `grafik` **tanpa AI**: pengenal rumus + SymPy |
| POST | `/admin/pin` | Ganti PIN admin (`pin_lama`, `pin_baru` di body) |

## Jadikan grafik tanpa AI (SPEC 1.8)

`jenis=grafik` tidak memanggil model bahasa. Gambar area dipotong per baris
tulisan, dibaca oleh **Pix2Text MFR 1.5** (model gambar→LaTeX, lisensi MIT,
jalan dengan onnxruntime di CPU, ±0,5 detik per baris), lalu **SymPy**
mengurai dan memeriksa LaTeX-nya dengan daftar putih (x, parameter satu huruf,
angka, + − × ÷ ^, sin, cos, tan, akar, log, ln, exp, abs). Baris yang tidak
lolos dibuang; tidak ada yang lolos → `422 tanpa_rumus`.

Model (±120 MB) **tidak ikut disalin**; unduh sekali ke `models/pix2text-mfr-1.5`:

```bash
mkdir -p models/pix2text-mfr-1.5 && cd models/pix2text-mfr-1.5
for f in encoder_model.onnx decoder_model.onnx tokenizer.json config.json; do
  curl -fsSLO https://huggingface.co/breezedeus/pix2text-mfr-1.5/resolve/main/$f
done
```

SHA-256 yang diuji: encoder `080a3f66…610b`, decoder `917deb98…2f2a`,
tokenizer `4ffbeb21…758a`. Lokasi lain: `PAPAN_MODEL_RUMUS` di `.env`.

## Video eksperimen (REQ-24)

Taruh berkas MP4/WebM di folder `video/` (atau `PAPAN_VIDEO`) dan daftarkan di
`video/katalog.toml`; dibaca ulang tiap permintaan (tanpa restart):

```toml
[[video]]
id = "natrium-klorin"              # huruf kecil, angka, tanda minus
judul = "Reaksi natrium dengan gas klorin"
berkas = "natrium-klorin.mp4"      # di dalam folder video
kata_kunci = ["Na", "Cl2", "NaCl"] # rumus seperti ditulis di papan
```

## Rekam kelas (REQ-25)

Ucapan → teks dengan **faster-whisper** di CPU server (model `small`,
±480 MB, diunduh sekali ke `models/whisper` atau `PAPAN_MODEL_SUARA`; ganti ke
`base` lewat `PAPAN_WHISPER=base` bila terlalu lambat). Satu transkripsi pada
satu waktu, 2 thread CPU. Ringkasan memakai penyedia AI aktif (cadangan Ollama).
Rekaman dihapus setelah ditranskrip; transkrip tidak disimpan atau dicatat.

## Konfigurasi operator

- `penyedia.toml` — daftar penyedia (salin dari `penyedia.contoh.toml`).
  Kunci API **tidak** ditulis di sini; isi nama variabelnya di `kunci_api_env`.
- `.env` — kunci API dan pengaturan (`PAPAN_DATA`, `PAPAN_PENYEDIA`,
  `PAPAN_PERCAYA_PROXY=1` bila di belakang nginx/Cloudflare Tunnel).
- Cek berkas penyedia: `python -m app.cli cek-penyedia`.
- **Atur ulang PIN darurat** (PIN lupa atau diganti orang lain):
  `python -m app.cli atur-pin`. Setelah itu masukkan PIN baru di Pengaturan
  setiap panel.

## Pemasangan di VPS karyabangsa (P-05)

Pola yang sama dengan aplikasi lain di VPS: layanan systemd milik `sukardi`
di `127.0.0.1:3030`, nginx berdasarkan `server_name`, HTTPS lewat Cloudflare
Tunnel. **Konfirmasi pemilik sebelum setiap langkah di VPS** — server produksi.

1. Kode di `/var/www/papan.karyabangsa.sch.id` (milik `sukardi:www-data`).
2. Sebagai `sukardi`: `cd server && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt`.
3. `penyedia.toml` dan `.env` (izin `640`), isi `OLLAMA_API_KEY` sendiri di server.
   Unduh model pengenal rumus ke `server/models/` (lihat bagian di atas).
4. `sudo -u sukardi .venv/bin/python -m app.cli atur-pin` — PIN diketik langsung di server.
5. `deploy/papan.service` → `/etc/systemd/system/`, lalu `systemctl enable --now papan`.
6. `deploy/nginx-papan.conf` → `/etc/nginx/sites-available/` + symlink, `nginx -t`, reload.
7. Cloudflare Tunnel: tambah ingress `papan.karyabangsa.sch.id → http://localhost:80`
   (dengan `httpHostHeader`) di `/etc/cloudflared/config.yml` (cadangkan dulu),
   `cloudflared tunnel route dns <tunnel> papan.karyabangsa.sch.id`, restart `cloudflared`.
8. Cek: `curl https://papan.karyabangsa.sch.id/sehat` → `{"status":"ok"}`.

Data server (SQLite: hash PIN, catatan) ada di `server/data/`; cadangkan
bersama `.env` dan `penyedia.toml`.

**Memperbarui kode:** salin ulang tanpa `.venv`, `data`, `models`, `.env`,
`penyedia.toml`; `pip install -r requirements.txt`; `systemctl restart papan`.
