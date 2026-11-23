# OpenSID di container (Alpine + Apache 2 + PHP 8.4, non-root)

Image ini membungkus OpenSID (branch `umum`) lengkap dengan `vendor/`, di atas **Alpine**, **Apache 2.4 (mod_php, prefork)** dan **PHP 8.4**.
Satu proses web saja (tanpa nginx/php-fpm); TLS diakhiri reverse proxy di depan container.

- Image dibangun otomatis oleh GitHub Actions dan dipush ke `ghcr.io/<akun>/opensid` (tag `latest`, nama branch, `sha-…`, dan semver untuk tag `v*`).
  Paket GHCR bawaannya **privat**; ubah visibilitas di *Packages → opensid → Package settings* bila ingin publik.
- Database tidak ikut di image: gunakan MariaDB 10.11 / MySQL 8 (lihat `docker-compose.yml`).

## Mulai cepat

```bash
cp docker/.env.example docker/.env      # isi DB_ROOT_PASSWORD, DB_PASSWORD, OPENSID_IMAGE (dan opsional OPENSID_ADMIN_PASSWORD)
docker compose -f docker/docker-compose.yml --env-file docker/.env up -d
docker compose -f docker/docker-compose.yml logs -f web       # tunggu baris "Password admin ..." (instalasi otomatis ±1–3 menit)
```

Buka `http://127.0.0.1:8080` dan masuk dengan `admin`. Password awal diambil dari `OPENSID_ADMIN_PASSWORD`; bila kosong, dibuat acak dan dicetak **sekali** di log.
Password bawaan upstream (`sid304`) otomatis diganti pada first-run, sehingga halaman instalasi web tidak bisa dipakai orang lain untuk mengambil alih admin.

> Jangan membuka situs saat first-run belum selesai (log belum menampilkan "Password admin …"): permintaan pertama menjalankan seeder database.

Port hanya di-bind ke `127.0.0.1` secara bawaan. Pasang reverse proxy TLS (Caddy, Traefik, nginx, Cloudflare Tunnel, dst.) di depannya.
Proxy **wajib** menimpa `X-Forwarded-Proto` dan `X-Forwarded-For` (jangan meneruskan nilai dari klien).

## Variabel lingkungan

Setiap variabel `OPENSID_*` juga bisa diberikan sebagai `OPENSID_*_FILE` (path berkas, mis. Docker/Kubernetes secret). Nilai dari `_FILE` didahulukan.

| Variabel | Bawaan | Keterangan |
|---|---|---|
| `OPENSID_DB_HOST` | – | Host database. Bila kosong, `desa/config/database.php` yang sudah ada dipakai apa adanya. |
| `OPENSID_DB_PORT` / `_NAME` / `_USER` | `3306` / `opensid` / `opensid` | |
| `OPENSID_DB_PASSWORD` | kosong | Maksimal 80 karakter (batas OpenSID). |
| `OPENSID_DB_WAIT` | `60` | Detik menunggu database siap sebelum lanjut. |
| `OPENSID_ADMIN_PASSWORD` | acak | Password admin awal; hanya dipakai bila password admin masih `sid304`. 8–20 karakter, ada angka, huruf kecil, huruf besar, simbol, tanpa spasi. |
| `OPENSID_TRUSTED_HOSTS` | kosong | Daftar domain (pisah koma) yang diizinkan di header `Host`, mis. `sid.desa.id,www.desa.id`. Sangat dianjurkan di produksi. |
| `OPENSID_COOKIE_SECURE` | `auto` | `auto` = cookie `Secure` bila permintaan lewat HTTPS (dari `X-Forwarded-Proto`); `true` / `false` untuk memaksa. |
| `OPENSID_ENCRYPTION_KEY` | acak | Kunci tanda-tangan tautan verifikasi; dibuat acak dan dipertahankan di `desa/config/config.php`. |
| `CI_ENV` | `production` | `production` \| `testing` \| `development` (jangan `development` di produksi). |

`desa/config/database.php` selalu ditulis ulang dari `OPENSID_DB_*` saat start. `desa/config/config.php` ditulis ulang hanya selama masih memuat penanda `OPENSID-DOCKER-GENERATED`;
hapus baris penanda itu bila ingin mengeditnya sendiri (tidak akan ditimpa lagi).

## Direktori yang bisa di-mount untuk data

Semua kode aplikasi bersifat **hanya-baca** (dimiliki root). Hanya path berikut yang perlu/boleh ditulis. Container berjalan sebagai **uid/gid 82** (`www-data`);
untuk *bind mount* jalankan dulu `chown -R 82:82 <folder-host>` (atau gunakan named volume, yang otomatis benar).

### Tingkat 1 – yang sebaiknya di-mount

| Path di container | Isi | Status | Catatan |
|---|---|---|---|
| `/var/www/html/desa` | **Seluruh data desa**: `config/` (database & konfigurasi), `upload/` (foto, dokumen, galeri), `logo/`, `arsip/`, `themes/`, `template-surat/`, `pengaturan/`, `widgets/`, `anjungan/`, `cache/`, `app_key`, `favicon.ico` | **Wajib** | Tanpa mount, data hilang saat container dibuat ulang. Hilangnya `desa/app_key` sementara DB tetap ada membuat aplikasi menolak masuk (kunci tidak cocok): cadangkan bersama DB. |
| `/var/www/html/backup_inkremental` | Cadangan inkremental yang dihasilkan aplikasi | Dianjurkan | Folder ini tidak pernah disajikan lewat web. |
| `/var/www/html/storage/logs` | Log aplikasi (`opensid.log`, `query.log`) | Dianjurkan | Bila tidak di-mount, log hilang saat container diganti. |

### Tingkat 2 – opsional

| Path di container | Fungsi | Saran |
|---|---|---|
| `/tmp` | Sesi login (CI session `files`), berkas sementara ekspor/impor | Gunakan **tmpfs** (sudah di compose). Sesi hilang saat container restart → pengguna login ulang. Gunakan volume bila ingin sesi bertahan. |
| `/var/www/html/storage/framework` | Cache Blade yang dikompilasi + cache aplikasi | Gunakan **tmpfs** (sudah di compose). Harus bisa ditulis (rootfs read-only). |
| `/var/www/html/storage/app` | Template surat/ekspor-impor bawaan dan tema sistem | Biasanya **tidak** di-mount (bagian dari image, hanya-baca). Mount hanya bila Anda sengaja menimpa/menambah template atau tema sistem; salin isi bawaan image dulu agar tidak kosong. |

### Tingkat 3 – mount lebih rinci (sebagai ganti satu volume `desa/`)

Berguna bila ingin memisahkan penyimpanan (mis. unggahan di disk besar, konfigurasi sebagai secret). Subfolder yang tidak di-mount tetap tersimpan di volume `desa/`.

| Path | Isi | Saran |
|---|---|---|
| `desa/upload` | Foto/lampiran/galeri/media/dokumen unggahan pengguna | Bagian terbesar & paling sering berubah: cocok untuk disk/NAS terpisah |
| `desa/arsip` | Arsip surat/dokumen | Tidak disajikan langsung lewat web |
| `desa/logo`, `desa/pengaturan`, `desa/anjungan` | Logo, latar login, ikon anjungan | Kecil, aman di volume utama |
| `desa/themes`, `desa/widgets`, `desa/template-surat` | Tema, widget, template surat ubahan desa | Bisa dibuat read-only bila tidak ada perubahan lewat admin |
| `desa/config` | `database.php`, `config.php` | Bisa dibuat **read-only** setelah first-run (*belum diuji; aplikasi dapat menulis ulang berkas ini dari menu pengaturan tertentu*) |
| `desa/cache` | Cache CodeIgniter | Boleh tmpfs |

Contoh `docker run` tanpa compose:

```bash
docker run -d --name opensid -p 127.0.0.1:8080:8080 \
  --read-only --cap-drop ALL --security-opt no-new-privileges --pids-limit 256 \
  --tmpfs /tmp:size=256m,mode=1777,uid=82,gid=82 \
  --tmpfs /var/www/html/storage/framework:size=128m,mode=0750,uid=82,gid=82 \
  -v opensid_desa:/var/www/html/desa \
  -v opensid_backup:/var/www/html/backup_inkremental \
  -v opensid_logs:/var/www/html/storage/logs \
  -e OPENSID_DB_HOST=db.internal -e OPENSID_DB_NAME=opensid -e OPENSID_DB_USER=opensid \
  -e OPENSID_DB_PASSWORD_FILE=/run/secrets/db_password \
  -e OPENSID_TRUSTED_HOSTS=sid.desa.id \
  ghcr.io/<akun>/opensid:latest
```

## Keamanan

Yang sudah dikerjakan image/compose:

- **Non-root & minimal hak**: proses berjalan sebagai `www-data` (uid 82) di port 8080; `cap_drop: ALL`, `no-new-privileges`, `pids_limit`, rootfs `read_only` (tulis hanya di volume/tmpfs), database di jaringan internal tanpa port terbuka, port web di-bind ke `127.0.0.1`.
- **Kode tak bisa diubah aplikasi**: seluruh source dimiliki root; folder tulis hanya `desa/`, `backup_inkremental/`, `storage/logs`, `storage/framework`.
- **Eksekusi PHP dibatasi**: hanya `/index.php` dan `/rfm/*.php`. Berkas `.php/.phtml/.phar/…` lain **selalu 403**, termasuk di `desa/upload`. `.htaccess` tidak dibaca (`AllowOverride None`), jadi `.htaccess` hasil unggahan tidak bisa mengaktifkan PHP; mesin PHP juga dimatikan di `desa/`.
- **Jalur sensitif diblokir**: `vendor`, `app`, `donjo-app`, `Modules`, `config`, `bootstrap`, `resources`, `storage`, `backup_inkremental`, `desa/{config,cache,template-surat}`, dotfile, `composer.*`, arsip (`.zip/.sql/.log/.ini/…`); dokumen privat (`desa/arsip`, `desa/upload/dokumen`) tidak bisa diunduh langsung.
- **Header**: `X-Content-Type-Options`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy`, `Permissions-Policy`, HSTS (hanya bila lewat HTTPS), CSP *sandbox* untuk SVG/HTML unggahan; versi Apache/PHP tidak dibocorkan; `TRACE` dimatikan; batas ukuran/waktu permintaan (slowloris).
- **PHP**: `expose_php=Off`, `display_errors=Off`, sesi `use_strict_mode`/`SameSite=Lax`, `disable_functions` (`exec`, `shell_exec`, `system`, `passthru`, `proc_open`, `popen`, `pcntl_*`, `dl`, `symlink`, `link`, `show_source`).
- **Kredensial**: password admin bawaan `sid304` diganti saat first-run; kunci enkripsi acak; dukungan `*_FILE`; rahasia dihapus dari environment proses sebelum Apache jalan; `cookie_secure` otomatis di belakang HTTPS.
- **CI**: setiap build menguji jalur sensitif (403/404), eksekusi PHP di folder unggahan, header, proses non-root, rootfs hanya-baca, rotasi password admin, lalu memindai image (Trivy) dan dependensi (`composer audit`) secara informasional.

Yang **menjadi tanggung jawab Anda** / keterbatasan yang diketahui:

- **TLS & pembatasan laju login** (brute-force) harus dipasang di reverse proxy/WAF di depan. Image tidak membatasi percobaan login. Pastikan proxy menimpa `X-Forwarded-*`.
- `disable_functions` ikut mematikan fitur yang memakai `exec`: mis. tombol *kill job* dan konversi gambar lewat ImageMagick CLI di file manager (rfm). Jika memang perlu, hapus entri terkait di `docker/php/opensid-security.ini` lalu bangun ulang image.
- `cookie_httponly` dibiarkan `false` karena JavaScript OpenSID membaca cookie CSRF. Cookie sesi tetap `SameSite=Lax` dan `Secure` di belakang HTTPS.
- CSP untuk halaman aplikasi tidak dipasang (OpenSID memakai skrip inline); gunakan CSP di proxy bila sudah Anda uji.
- Cadangkan `desa/` **dan** database bersamaan (termasuk `desa/app_key`). Perbarui image secara berkala (build mingguan otomatis menarik patch Alpine); `vendor/` ikut upstream, periksa `composer audit` di artefak CI.
- Bila `OPENSID_TRUSTED_HOSTS` kosong, header `Host` tidak divalidasi.

## Membangun sendiri

```bash
docker build -f docker/Dockerfile -t opensid:local .                         # PHP 8.4 (bawaan)
docker build -f docker/Dockerfile --build-arg PHP_VERSION=8.3 -t opensid:php83 .
```

Batas versi PHP di kode OpenSID: `donjo-app/config/constants.php` (`minPhpVersion` 8.1, `maxPhpVersion` 8.4.99 pada fork ini).

## Pemecahan masalah

- `desa ... tidak bisa ditulis oleh uid 82` → jalankan `chown -R 82:82` pada folder bind mount (atau pakai named volume / jalankan sekali sebagai root: entrypoint akan merapikan kepemilikan lalu turun ke www-data).
- Halaman putih / error database → cek `docker compose logs web db`; pastikan `OPENSID_DB_*` benar dan database sudah sehat.
- Diminta "koneksi database/config" setelah memindahkan data → `desa/app_key` tidak cocok dengan database; kembalikan `desa/` yang sesuai.
- Link/aset bercampur `http://` di belakang proxy → proxy belum mengirim `X-Forwarded-Proto: https`.
