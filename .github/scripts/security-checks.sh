#!/bin/sh
# Pemeriksaan keamanan terhadap stack yang sedang berjalan (dipanggil dari workflow).
#   BASE      URL dasar (default http://127.0.0.1:8080)
#   COMPOSE   perintah docker compose lengkap (untuk exec ke container web)
# Keluar dengan kode 1 bila ada pemeriksaan yang gagal.
BASE="${BASE:-http://127.0.0.1:8080}"
fail=0
ok()   { echo "  OK    $*"; }
bad()  { echo "  GAGAL $*"; fail=1; }

code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@"; }

echo "== 1. Jalur sensitif harus ditolak (403/404)"
for p in \
    /desa/config/database.php /desa/config/config.php /desa/config/ /desa/app_key /desa/cache/ \
    /vendor/autoload.php /vendor/composer/installed.json /composer.json /composer.lock /package.json \
    /donjo-app/config/database.php /donjo-app/controllers/Web.php /app/Models/User.php /Modules/ /bootstrap/ /config/app.php \
    /storage/logs/ /storage/app/themes/natra/config.json /storage/framework/ /backup_inkremental/ /resources/views/ \
    /.htaccess /.env /.git/config /artisan /phpunit.xml /rector.php \
    /rfm/config/config.php /rfm/include/utils.php /rfm/UploadHandler.php /assets/fonts/times.php /index.php/../vendor/autoload.php
do
    c=$(code "$BASE$p")
    case "$c" in 403|404) ok "$p -> $c" ;; *) bad "$p -> $c (seharusnya 403/404)" ;; esac
done

echo "== 2. PHP tidak boleh dieksekusi di folder unggahan (meski ada .htaccess jahat)"
$COMPOSE exec -T web sh -c '
  mkdir -p desa/upload/ci-uji &&
  printf "<?php echo \"PWNED-\".(6*7);" > desa/upload/ci-uji/shell.php &&
  printf "<?php echo \"PWNED-\".(6*7);" > desa/upload/ci-uji/shell.phtml &&
  printf "<?php echo \"PWNED-\".(6*7);" > desa/upload/ci-uji/gambar.jpg &&
  printf "AddType application/x-httpd-php .jpg\nSetHandler application/x-httpd-php\n" > desa/upload/ci-uji/.htaccess' || bad "gagal menyiapkan berkas uji"
for f in shell.php shell.phtml gambar.jpg; do
    body=$(curl -s --max-time 30 "$BASE/desa/upload/ci-uji/$f"); c=$(code "$BASE/desa/upload/ci-uji/$f")
    case "$body" in *PWNED-42*) bad "desa/upload/ci-uji/$f DIEKSEKUSI sebagai PHP ($c)" ;; *) ok "desa/upload/ci-uji/$f tidak dieksekusi ($c)" ;; esac
done
c=$(code "$BASE/desa/upload/ci-uji/.htaccess"); case "$c" in 403|404) ok ".htaccess unggahan tidak bisa dibaca ($c)" ;; *) bad ".htaccess unggahan terbaca ($c)" ;; esac
$COMPOSE exec -T web rm -rf desa/upload/ci-uji

echo "== 3. Header keamanan"
h=$(curl -s -D - -o /dev/null --max-time 30 "$BASE/robots.txt")
echo "$h" | grep -qi '^x-content-type-options: nosniff' && ok "X-Content-Type-Options" || bad "X-Content-Type-Options hilang"
echo "$h" | grep -qi '^x-frame-options: SAMEORIGIN'     && ok "X-Frame-Options"        || bad "X-Frame-Options hilang"
echo "$h" | grep -qi '^referrer-policy:'                && ok "Referrer-Policy"        || bad "Referrer-Policy hilang"
echo "$h" | grep -qi '^permissions-policy:'             && ok "Permissions-Policy"     || bad "Permissions-Policy hilang"
echo "$h" | grep -qi '^strict-transport-security'       && bad "HSTS muncul pada HTTP polos" || ok "HSTS tidak dikirim di HTTP polos"
echo "$h" | grep -qiE '^server: Apache/[0-9]'           && bad "versi Apache bocor di header Server" || ok "versi Apache tidak bocor"
echo "$h" | grep -qi '^x-powered-by'                    && bad "X-Powered-By bocor" || ok "X-Powered-By tidak ada"
h=$(curl -s -D - -o /dev/null --max-time 30 -H 'X-Forwarded-Proto: https' "$BASE/robots.txt")
echo "$h" | grep -qi '^strict-transport-security' && ok "HSTS dikirim saat di belakang proxy HTTPS" || bad "HSTS tidak dikirim di belakang proxy HTTPS"

echo "== 4. Metode berbahaya"
c=$(curl -s -o /dev/null -w '%{http_code}' -X TRACE --max-time 30 "$BASE/")
case "$c" in 405|403|400|501) ok "TRACE -> $c" ;; *) bad "TRACE -> $c" ;; esac

echo "== 5. Proses & filesystem container"
[ "$($COMPOSE exec -T web id -u)" = "82" ] && ok "container berjalan sebagai uid 82 (www-data)" || bad "container tidak berjalan sebagai uid 82"
procs=$($COMPOSE exec -T web ps -o user,comm | grep -E 'httpd' | awk '{print $1}' | sort -u | tr '\n' ' ')
[ "$procs" = "www-data " ] && ok "semua proses httpd milik www-data" || bad "proses httpd milik: $procs"
$COMPOSE exec -T web sh -c 'touch /var/www/html/uji-tulis 2>/dev/null' && bad "kode aplikasi BISA ditulis" || ok "kode aplikasi hanya-baca"
$COMPOSE exec -T web sh -c 'touch /var/www/html/index.php 2>/dev/null' && bad "index.php BISA ditulis" || ok "index.php hanya-baca"
$COMPOSE exec -T web sh -c 'touch /var/www/html/desa/uji-tulis && rm /var/www/html/desa/uji-tulis' && ok "desa/ bisa ditulis" || bad "desa/ tidak bisa ditulis"
$COMPOSE exec -T web sh -c 'touch /var/www/html/backup_inkremental/uji && rm /var/www/html/backup_inkremental/uji' && ok "backup_inkremental/ bisa ditulis" || bad "backup_inkremental/ tidak bisa ditulis"
$COMPOSE exec -T web sh -c 'touch /var/www/html/storage/logs/uji && rm /var/www/html/storage/logs/uji' && ok "storage/logs bisa ditulis" || bad "storage/logs tidak bisa ditulis"
cap=$($COMPOSE exec -T web grep '^CapEff' /proc/self/status | tr -d '\r' | awk '{print $2}')
[ "$cap" = "0000000000000000" ] && ok "tanpa capability Linux (CapEff=$cap)" || bad "capability Linux masih ada (CapEff=$cap)"
$COMPOSE exec -T web sh -c 'php -r "exit(function_exists(\"shell_exec\") || function_exists(\"exec\") ? 1 : 0);"' && ok "exec/shell_exec dinonaktifkan di PHP" || bad "fungsi exec masih aktif"

echo "== 6. Log mengalir ke stdout/stderr container"
$COMPOSE logs --no-color web 2>&1 | grep -qE '"(GET|POST|HEAD) ' && ok "access log terlihat di docker logs" || bad "access log tidak muncul di docker logs"

exit $fail
