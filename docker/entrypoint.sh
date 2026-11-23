#!/bin/sh
# Entrypoint image OpenSID (Alpine + Apache). POSIX sh.
#
#   serve (default)  siapkan konfigurasi lalu jalankan Apache di foreground
#   perintah lain    dijalankan apa adanya, mis. `docker run IMAGE php -v` atau `sh`
set -eu

cd /var/www/html

log() { echo "[opensid] $*" >&2; }

if [ "${1:-serve}" != "serve" ]; then
    exec "$@"
fi

export CI_ENV="${CI_ENV:-production}"

# Jalankan sebagai root hanya untuk membereskan kepemilikan volume, lalu turun ke www-data (uid 82).
# Dengan `user: "82:82"` (disarankan) bagian ini dilewati sepenuhnya.
if [ "$(id -u)" = "0" ]; then
    log "Berjalan sebagai root: merapikan kepemilikan direktori data lalu turun ke www-data."
    mkdir -p desa backup_inkremental storage/logs storage/framework
    for d in desa backup_inkremental storage/logs storage/framework; do
        if [ "$(stat -c %u "$d")" != "82" ]; then
            chown -R 82:82 "$d"
        fi
    done
    exec su-exec 82:82 "$0" "$@"
fi

# --- Pastikan direktori data bisa ditulis ---------------------------------------------------------------
mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views 2>/dev/null || true

fail=0
for d in desa backup_inkremental storage/logs storage/framework /tmp; do
    if [ ! -d "$d" ] || [ ! -w "$d" ]; then
        log "KESALAHAN: $d tidak bisa ditulis oleh uid $(id -u). Jika memakai bind mount, jalankan di host: chown -R 82:82 <folder>"
        fail=1
    fi
done
[ "$fail" = "0" ] || exit 1

# --- Runtime Apache & log ---------------------------------------------------------------------------------
# Apache non-root tidak bisa membuka /proc/self/fd/{1,2} milik pipe root, jadi log ditulis ke FIFO
# lalu dialirkan oleh `cat` (mewarisi stdout/stderr container).
rm -rf /tmp/httpd
mkdir -p /tmp/httpd
mkfifo /tmp/httpd/error.log /tmp/httpd/access.log
# `<>` membuka FIFO baca-tulis: pembaca tidak pernah menerima EOF saat Apache menutup/membuka ulang log
# (mis. pada restart/graceful), dan Apache tidak pernah terblokir menunggu pembaca.
cat <> /tmp/httpd/error.log  >&2 &
cat <> /tmp/httpd/access.log     &

# --- Konfigurasi aplikasi dari environment ------------------------------------------------------------------
mkdir -p desa/config
# favicon.ico di root adalah symlink ke desa/favicon.ico (aplikasi menulis ulang saat logo diganti)
if [ ! -e desa/favicon.ico ] && [ -f assets/files/logo/favicon.ico ]; then
    cp assets/files/logo/favicon.ico desa/favicon.ico
fi

php /usr/local/bin/opensid-init-config.php

# --- First run: picu seeder lalu ganti password admin bawaan -----------------------------------------------------
# Berjalan di latar belakang agar Apache bisa langsung melayani permintaan.
(
    php /usr/local/bin/opensid-firstrun.php
) &

# Rahasia tidak perlu lagi ada di environment proses web (PHP tidak membacanya; config.php sudah ditulis).
unset OPENSID_DB_PASSWORD OPENSID_ADMIN_PASSWORD OPENSID_ENCRYPTION_KEY
unset OPENSID_DB_PASSWORD_FILE OPENSID_ADMIN_PASSWORD_FILE OPENSID_ENCRYPTION_KEY_FILE

exec httpd -D FOREGROUND -f /etc/apache2/httpd.conf
