#!/bin/sh
set -eu

cd /var/www/html

# Direktori yang harus ada dan bisa ditulis (volume baru biasanya dimiliki root)
mkdir -p desa/config backup_inkremental \
    storage/logs storage/framework/cache storage/framework/sessions storage/framework/views

if [ "$(id -u)" = "0" ]; then
    php /usr/local/bin/opensid-init-config.php || { echo "[opensid] Konfigurasi database gagal dibuat." >&2; exit 1; }

    for d in desa backup_inkremental storage; do
        if [ "$(stat -c %U "$d")" != "www-data" ]; then
            chown -R www-data:www-data "$d"
        fi
    done
    chown -R www-data:www-data desa/config
fi

exec docker-php-entrypoint "$@"
