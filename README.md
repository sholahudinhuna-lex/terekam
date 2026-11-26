# Terekam Studio — versi GitHub Pages + Supabase

GitHub Pages hanya menyajikan halaman statis (tidak bisa PHP dan tidak bisa menyimpan data).
Karena itu, booking disimpan di **Supabase** (database + penyimpanan file gratis), sedangkan
halamannya dihosting di **GitHub Pages**.

```
Pengunjung (siapa pun, tanpa akun) ──► index.html ──► Supabase ◄── admin.html ◄── Admin (login)
                                         (GitHub Pages)                 (GitHub Pages)
```

## File di folder ini
| File | Fungsi |
|---|---|
| `index.html` | Landing page + alur booking |
| `admin.html` | Dashboard admin |
| `config.js` | Alamat dan kunci publik Supabase (**wajib diisi**) |
| `supabase-setup.sql` | Membuat tabel, aturan keamanan, fungsi booking, dan penyimpanan file |

## Langkah 1 — Siapkan Supabase (±10 menit)
1. Daftar di https://supabase.com lalu klik **New project** (pilih region Singapore, catat password database).
2. Buka **SQL Editor → New query**. Tempel seluruh isi `supabase-setup.sql`.
   **Ganti dulu** `admin@terekam.web.id` di baris `insert into public.admin_emails` dengan emailmu, lalu klik **Run**.
3. Buka **Authentication → Users → Add user → Create new user**. Isi email (sama persis dengan di langkah 2) dan password,
   lalu centang **Auto Confirm User**. Ini akun login dashboard.
4. (Disarankan) **Authentication → Sign In / Providers →** matikan **Allow new users to sign up**.
5. Buka **Project Settings → API**. Salin **Project URL** dan **anon public key**.

## Langkah 2 — Isi `config.js`
Ganti `GANTI_DENGAN_PROJECT_URL` dan `GANTI_DENGAN_ANON_KEY` dengan nilai dari langkah 1.5.
Kunci *anon* memang aman berada di kode publik karena data dilindungi aturan RLS di database.
**Jangan pernah** memakai kunci `service_role` di sini.

## Langkah 3 — Publikasikan di GitHub Pages
1. Buat repository baru di GitHub (harus **Public** pada akun gratis).
2. Upload `index.html`, `admin.html`, `config.js` (file `.sql` dan `README.md` boleh ikut).
3. **Settings → Pages →** Source: *Deploy from a branch* → Branch: `main` / `(root)` → Save.
4. Tunggu 1–2 menit. Landing page: `https://USERNAME.github.io/NAMA-REPO/`, dashboard: `.../admin.html`.
5. (Opsional) Domain sendiri: Settings → Pages → Custom domain → `terekam.web.id`, lalu di DNS buat
   record CNAME `www` → `USERNAME.github.io` (untuk domain utama gunakan record A sesuai petunjuk GitHub).

## Cara tes
1. Buka `admin.html`, login dengan akun dari langkah 1.3. Jika dashboard kosong, akan muncul tawaran mengisi data demo.
2. Dari HP lain (atau minta teman), buka landing page dan selesaikan booking sampai tiket muncul.
3. Dalam ±5 detik booking muncul di dashboard beserta toast "Booking baru masuk". Bukti transfer bisa dilihat di modal detail.

## Yang perlu diketahui
- **Harga dihitung di database**, bukan di browser, jadi tidak bisa diakali lewat inspect element.
- **Data klien aman**: pengunjung tidak bisa membaca daftar booking. Hanya akun admin yang bisa.
- **Bukti transfer privat** (bucket `proofs`); foto portofolio publik (bucket `portfolio`).
- Batas spam: maksimal 10 booking/jam per perangkat dan 5/jam per nomor WhatsApp.
- Proyek Supabase gratis **otomatis dijeda jika 7 hari tidak ada aktivitas**. Jika booking mendadak gagal,
  buka dashboard Supabase lalu klik **Restore project**.
- Repo Public berarti kodenya terlihat orang lain. Itu aman selama `config.js` hanya berisi kunci *anon*.

## Masalah umum
| Pesan | Penyebab |
|---|---|
| "config.js belum diisi" | URL/anon key belum diganti |
| "Akun ini bukan admin" | Email login tidak sama dengan yang ada di `admin_emails` (jalankan ulang SQL dengan email yang benar) |
| "Gagal memuat data" | `supabase-setup.sql` belum dijalankan sampai selesai |
| Booking gagal dengan pesan merah | Pesan berasal dari validasi database (mis. tanggal sudah lewat, nomor WA tidak valid) |
