#!/bin/sh
# Lint kompilasi semua file PHP aplikasi dengan error_reporting penuh.
# Mencetak hanya pesan (Deprecated/Warning/Fatal/Parse); file bersih tidak dicetak.
cd "${APP_ROOT:-/var/www/html}" || exit 2
find app donjo-app Modules config bootstrap rfm index.php artisan -name '*.php' | sort | while read -r f; do
    out=$(php -d display_errors=1 -d log_errors=0 -d error_reporting=-1 -l "$f" 2>&1)
    printf '%s\n' "$out" | grep -vE '^(No syntax errors detected|$)' | sed "s#^#[$f] #"
done
