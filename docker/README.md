# OpenSID di Docker

Image ini membungkus source OpenSID (termasuk `vendor/`) di PHP 8.2 + Apache (cocok dengan MariaDB 10.11 / MySQL 8). Data desa disimpan di volume.

## Menjalankan

```bash
cp docker/.env.example docker/.env      # isi password dan OPENSID_IMAGE
docker compose -f docker/docker-compose.yml --env-file docker/.env up -d
```

Buka `http://localhost:8080`. Permintaan pertama lebih lama karena tabel dan data awal dibuat otomatis.

**Akun awal: `admin` / `sid304`. Ganti segera setelah login.** Jalur ini tidak melewati installer web
(yang memaksa penggantian password), jadi password bawaan tetap aktif sampai Anda mengubahnya.

## Variabel lingkungan

| Variabel | Default | Keterangan |
|---|---|---|
| `OPENSID_DB_HOST` | (wajib) | Host database. Bila kosong, entrypoint memakai `desa/config/database.php` yang sudah ada. |
| `OPENSID_DB_PORT` | `3306` | |
| `OPENSID_DB_NAME` | `opensid` | |
| `OPENSID_DB_USER` | `opensid` | |
| `OPENSID_DB_PASSWORD` | kosong | |
| `OPENSID_TRUSTED_HOSTS` | kosong | Daftar host dipisah koma; ditulis ke `desa/config/config.php` hanya jika file belum ada. |
| `OPENSID_DB_WAIT` | `60` | Detik menunggu database siap. |

`desa/config/database.php` ditulis ulang setiap container start selama `OPENSID_DB_HOST` diisi.

## Volume

- `/var/www/html/desa` : konfigurasi, unggahan, `app_key`. **Jangan hilang**; `app_key` harus cocok dengan yang tersimpan di database.
- `/var/www/html/backup_inkremental` : cadangan inkremental.
- Database (`/var/lib/mysql` pada container MariaDB).

## HTTPS

Container melayani HTTP saja. Pasang reverse proxy (Caddy, Traefik, nginx, Cloudflare) yang mengakhiri TLS dan mengirim
`X-Forwarded-Proto: https`; Apache di image ini meneruskannya ke OpenSID sebagai `HTTPS=on`.

## Memperbarui versi

Tarik image baru (`docker compose pull && docker compose up -d`). Migrasi database dijalankan OpenSID sendiri saat dibuka.
Cadangkan volume `desa` dan database sebelum memperbarui.

## Build lokal

```bash
docker build -f docker/Dockerfile -t opensid:local .
# PHP lain: --build-arg PHP_VERSION=8.1
# Kode branch umum membatasi PHP 8.1.0 - 8.3.0; PHP 8.4 akan ditandai tidak sesuai di Info Sistem
# dan belum teruji untuk branch ini.
```
