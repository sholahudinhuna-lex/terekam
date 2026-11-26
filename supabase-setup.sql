-- ============================================================================
-- Terekam Studio — setup database Supabase
-- Cara pakai: Supabase → SQL Editor → New query → tempel seluruh file ini → Run
-- Aman dijalankan ulang (tidak menggandakan data).
-- ============================================================================

-- 0) GANTI email di bawah dengan email akun admin yang kamu buat di Authentication → Users
create table if not exists public.admin_emails (email text primary key);
insert into public.admin_emails (email) values ('admin@terekam.web.id') on conflict do nothing;
alter table public.admin_emails enable row level security;   -- tanpa policy = tidak bisa dibaca dari browser

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.admin_emails
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- 1) Tabel
create table if not exists public.packages (
  id text primary key,
  name text not null,
  price integer not null check (price >= 0),
  descr text not null default '',
  features text[] not null default '{}',
  sort integer not null default 0
);

create table if not exists public.portfolio (
  id text primary key default ('p' || substr(md5(random()::text), 1, 8)),
  title text not null,
  category text not null check (category in ('Wisuda','Wedding & Couple','Video Reels / Cinematic','Brand & Produk')),
  is_video boolean not null default false,
  duration integer not null default 0,
  image text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.bookings (
  code text primary key,
  name text not null,
  wa text not null,
  ig text not null default '',
  pkg_key text not null,
  pkg_name text not null,
  addons text[] not null default '{}',
  total integer not null,
  paid integer not null,
  pay_mode text not null check (pay_mode in ('dp','full')),
  session_date date not null,
  session_time text not null,
  location text not null,
  status text not null default 'menunggu' check (status in ('menunggu','terjadwal','selesai','batal')),
  proof_name text not null default '',
  proof_path text not null default '',
  source text not null default 'web',
  ip_hash text not null default '',
  created_at timestamptz not null default now()
);

-- 2) Keamanan (Row Level Security)
alter table public.packages  enable row level security;
alter table public.portfolio enable row level security;
alter table public.bookings  enable row level security;

drop policy if exists "packages: publik baca" on public.packages;
create policy "packages: publik baca" on public.packages for select to anon, authenticated using (true);
drop policy if exists "packages: admin kelola" on public.packages;
create policy "packages: admin kelola" on public.packages for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "portfolio: publik baca" on public.portfolio;
create policy "portfolio: publik baca" on public.portfolio for select to anon, authenticated using (true);
drop policy if exists "portfolio: admin kelola" on public.portfolio;
create policy "portfolio: admin kelola" on public.portfolio for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Booking: pengunjung TIDAK bisa membaca/menulis langsung. Hanya admin, atau lewat fungsi create_booking di bawah.
drop policy if exists "bookings: admin kelola" on public.bookings;
create policy "bookings: admin kelola" on public.bookings for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 3) Fungsi booking publik: memvalidasi data dan menghitung harga di server
create or replace function public.create_booking(
  p_pkg text, p_name text, p_wa text, p_ig text, p_date date, p_time text, p_loc text, p_pay text,
  p_addons text[] default '{}', p_proof_name text default '', p_proof_path text default ''
) returns json
language plpgsql security definer set search_path = public as $$
declare
  v_pkg public.packages%rowtype;
  v_name text := btrim(coalesce(p_name, ''));
  v_wa   text := regexp_replace(coalesce(p_wa, ''), '[[:space:]().+-]', '', 'g');
  v_ig   text := btrim(coalesce(p_ig, ''));
  v_loc  text := btrim(coalesce(p_loc, ''));
  v_total integer;
  v_paid integer;
  v_code text;
  v_tries integer := 0;
  v_key text;
  v_names text[] := '{}';
  v_allowed text[];
  v_hdr text;
  v_xff text;
  v_ip text := '';
  v_cnt integer;
begin
  if char_length(v_name) < 3 or char_length(v_name) > 80 then raise exception 'Nama minimal 3 huruf.'; end if;
  if v_wa !~ '^(62|0)8[0-9]{7,11}$' then raise exception 'Nomor WhatsApp tidak valid.'; end if;
  v_wa := regexp_replace(v_wa, '^0', '62');
  if v_ig <> '' then
    if v_ig !~ '^@?[A-Za-z0-9._]{1,30}$' then raise exception 'Username Instagram tidak valid.'; end if;
    v_ig := '@' || ltrim(v_ig, '@');
  end if;
  if p_date is null or p_date < (now() at time zone 'Asia/Jakarta')::date then raise exception 'Tanggal acara tidak valid.'; end if;
  if p_time not in ('Golden Hour Pagi (06.00–09.00)', 'Siang (10.00–14.00)', 'Golden Hour Sore (15.30–18.00)') then
    raise exception 'Sesi tidak valid.';
  end if;
  if char_length(v_loc) < 3 or char_length(v_loc) > 120 then raise exception 'Lokasi wajib diisi.'; end if;
  if p_pay not in ('dp', 'full') then raise exception 'Metode pembayaran tidak valid.'; end if;
  if coalesce(p_proof_path, '') <> '' and p_proof_path !~ '^[A-Za-z0-9._-]{1,80}$' then raise exception 'Bukti transfer tidak valid.'; end if;

  select * into v_pkg from public.packages where id = p_pkg;
  if not found then raise exception 'Paket tidak ditemukan.'; end if;

  v_allowed := case p_pkg when 'photo' then array['reels','hour','exp'] else array['hour','exp','print'] end;
  v_total := v_pkg.price;
  for v_key in select distinct x from unnest(coalesce(p_addons, '{}'::text[])) as x order by x loop
    if v_key = any(v_allowed) then
      v_total := v_total + case v_key when 'reels' then 250000 when 'hour' then 150000 when 'exp' then 100000 else 85000 end;
      v_names := v_names || case v_key when 'reels' then 'Tambah Video Reels 30 Detik' when 'hour' then 'Extra Jam' when 'exp' then 'Express Edit 24 Jam' else 'Cetak 10 Foto 4R' end;
    end if;
  end loop;
  v_paid := case p_pay when 'dp' then round(v_total / 2.0)::integer else v_total end;

  -- batasi spam: maks 10 booking/jam per perangkat dan 5/jam per nomor WA
  begin
    v_hdr := current_setting('request.headers', true);
    if v_hdr is not null and v_hdr <> '' then v_xff := (v_hdr::json) ->> 'x-forwarded-for'; end if;
  exception when others then
    v_xff := null;
  end;
  if coalesce(v_xff, '') <> '' then
    v_ip := md5(v_xff);
    select count(*) into v_cnt from public.bookings where ip_hash = v_ip and created_at > now() - interval '1 hour';
    if v_cnt >= 10 then raise exception 'Terlalu banyak booking dari perangkat ini. Coba lagi nanti.'; end if;
  end if;
  select count(*) into v_cnt from public.bookings where wa = v_wa and created_at > now() - interval '1 hour';
  if v_cnt >= 5 then raise exception 'Terlalu banyak booking dengan nomor ini. Coba lagi nanti.'; end if;

  loop
    v_tries := v_tries + 1;
    v_code := 'TRK-2026-' || case when v_tries <= 60 then (10 + floor(random() * 90))::integer else (100 + floor(random() * 900))::integer end;
    exit when not exists (select 1 from public.bookings where code = v_code);
  end loop;

  insert into public.bookings (code, name, wa, ig, pkg_key, pkg_name, addons, total, paid, pay_mode,
                               session_date, session_time, location, status, proof_name, proof_path, source, ip_hash)
  values (v_code, v_name, v_wa, v_ig, v_pkg.id, v_pkg.name, v_names, v_total, v_paid, p_pay,
          p_date, p_time, v_loc, 'menunggu', left(coalesce(p_proof_name, ''), 120), coalesce(p_proof_path, ''), 'web', v_ip);

  return json_build_object('code', v_code, 'total', v_total, 'paid', v_paid, 'pkg', v_pkg.name);
end;
$$;
revoke all on function public.create_booking(text,text,text,text,date,text,text,text,text[],text,text) from public;
grant execute on function public.create_booking(text,text,text,text,date,text,text,text,text[],text,text) to anon, authenticated;

-- 4) Penyimpanan file: bukti transfer (privat) dan foto portofolio (publik)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('proofs', 'proofs', false, 4194304, array['image/jpeg','image/png','image/webp','image/gif','application/pdf']),
  ('portfolio', 'portfolio', true, 4194304, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do nothing;

drop policy if exists "proofs: pengunjung boleh upload" on storage.objects;
create policy "proofs: pengunjung boleh upload" on storage.objects for insert to anon, authenticated with check (bucket_id = 'proofs');
drop policy if exists "proofs: admin boleh lihat" on storage.objects;
create policy "proofs: admin boleh lihat" on storage.objects for select to authenticated using (bucket_id = 'proofs' and public.is_admin());
drop policy if exists "proofs: admin boleh hapus" on storage.objects;
create policy "proofs: admin boleh hapus" on storage.objects for delete to authenticated using (bucket_id = 'proofs' and public.is_admin());
drop policy if exists "portfolio: admin boleh upload" on storage.objects;
create policy "portfolio: admin boleh upload" on storage.objects for insert to authenticated with check (bucket_id = 'portfolio' and public.is_admin());
drop policy if exists "portfolio: admin boleh hapus" on storage.objects;
create policy "portfolio: admin boleh hapus" on storage.objects for delete to authenticated using (bucket_id = 'portfolio' and public.is_admin());

-- 5) Data awal paket & portofolio (supaya landing page langsung terisi)
insert into public.packages (id, name, price, descr, features, sort) values
  ('photo', 'Photo Session', 350000, 'Wisuda, personal, atau couple.', array['Durasi 1 jam, 1 fotografer','30 foto hasil edit','File via Google Drive','Konsultasi konsep & lokasi'], 1),
  ('combo', 'Photo + Video Reels', 950000, 'Satu sesi, dua jenis konten.', array['Durasi 2 jam','30 foto hasil edit','1 video cinematic vertikal 60 detik','Siap upload IG Reels / TikTok','Transisi & color grading estetik'], 2),
  ('event', 'Full Cinematic Event', 2200000, 'Wedding, engagement, atau event.', array['1 fotografer + 1 videografer','Video highlight 3–5 menit','Teaser 1 menit untuk sosmed','Foto hasil edit tanpa batas jumlah','Backup file di cloud 6 bulan'], 3)
on conflict (id) do nothing;

insert into public.portfolio (id, title, category, is_video, duration, image, created_at) values
  ('p1',  'Showreel 2026',           'Video Reels / Cinematic', true,  48, '1492684223066-81342ee5ff30', now() - interval '1 minute'),
  ('p2',  'Toga & Golden Hour',      'Wisuda',                  false,  0, 'dl:QfrTfjHzQIU',             now() - interval '2 minutes'),
  ('p3',  'Janji di Taman',          'Wedding & Couple',        false,  0, '1519741497674-611481863552', now() - interval '3 minutes'),
  ('p4',  'Graduation Day Reels',    'Video Reels / Cinematic', true,  30, '1541339907198-e08756dedf3f', now() - interval '4 minutes'),
  ('p5',  'Watch Series',            'Brand & Produk',          false,  0, '1523275335684-37898b6baf30', now() - interval '5 minutes'),
  ('p6',  'Lempar Topi',             'Wisuda',                  false,  0, '1627556704302-624286467c65', now() - interval '6 minutes'),
  ('p7',  'Couple Cinematic Teaser', 'Video Reels / Cinematic', true,  45, '1511285560929-80b456fea0bc', now() - interval '7 minutes'),
  ('p8',  'Bridal Soft Light',       'Wedding & Couple',        false,  0, '1465495976277-4387d4b0b4c6', now() - interval '8 minutes'),
  ('p9',  'Skincare Flatlay',        'Brand & Produk',          false,  0, '1556228720-195a672e8a03',    now() - interval '9 minutes'),
  ('p10', 'Brand Launch Reel',       'Video Reels / Cinematic', true,  25, '1522335789203-aabd1fc54bc9', now() - interval '10 minutes'),
  ('p11', 'Wedding Highlight',       'Wedding & Couple',        true,  52, '1529634806980-85c3dd6d34ac', now() - interval '11 minutes'),
  ('p12', 'Sneaker Drop',            'Brand & Produk',          false,  0, '1542291026-7eec264c27ff',    now() - interval '12 minutes')
on conflict (id) do nothing;
