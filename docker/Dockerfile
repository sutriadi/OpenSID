# syntax=docker/dockerfile:1
#
# Image produksi OpenSID: Alpine + Apache 2 + mod_php (PHP dari paket Alpine), non-root.
# Source OpenSID (termasuk vendor/) dibungkus ke dalam image dan dimiliki root (hanya-baca bagi aplikasi);
# hanya direktori data (desa/, backup_inkremental/, storage/) yang bisa ditulis oleh www-data (uid 82).
#
# Build (dari root repo):
#   docker build -f docker/Dockerfile -t opensid:local .
#   docker build -f docker/Dockerfile --build-arg PHP_VERSION=8.3 -t opensid:php83 .
#
# PHP_VERSION harus tersedia di Alpine yang dipakai (3.22: 8.3, 8.4, 8.5). Batas versi di kode OpenSID:
# lihat maxPhpVersion di donjo-app/config/constants.php.

ARG ALPINE_VERSION=3.22

# ---------------------------------------------------------------------------
# Tahap 1: siapkan source (buang file dev, buat penanda .htaccess)
# ---------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION} AS src

COPY . /src

RUN set -eux; \
    cd /src; \
    rm -rf .git .github docker bin tests node_modules \
        package.json package-lock.json tsconfig.json playwright.config.ts .e2e.env.example \
        phpunit.xml rector.php .php-cs-fixer.php .prettierrc.json .gitattributes htaccess.apache.txt; \
    # OpenSID hanya menghilangkan "index.php" dari URL bila file .htaccess ada
    # (donjo-app/config/sid_ini.php). Isinya tidak dipakai (AllowOverride None); aturan ada di httpd.conf.
    printf '%s\n' '# Penanda untuk OpenSID (URL tanpa index.php). Aturan akses web ada di httpd.conf.' > .htaccess; \
    # favicon.ico ditulis ulang aplikasi saat logo diganti; arahkan ke volume desa/ agar root image tetap hanya-baca
    rm -f favicon.ico; \
    ln -s desa/favicon.ico favicon.ico; \
    mkdir -p desa backup_inkremental storage/logs storage/framework/cache storage/framework/sessions storage/framework/views

# ---------------------------------------------------------------------------
# Tahap 2: image akhir
# ---------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION}

ARG PHP_VERSION=8.4

# gnu-libiconv: iconv bawaan musl tidak mendukung //TRANSLIT yang dipakai banyak library (slug, dsb.)
RUN set -eux; \
    MM="$(echo "${PHP_VERSION}" | tr -d .)"; \
    addgroup -g 82 -S www-data 2>/dev/null || true; \
    adduser -u 82 -D -S -G www-data -h /var/www www-data 2>/dev/null || true; \
    apk add --no-cache \
        apache2 curl gnu-libiconv su-exec tini tzdata \
        "php${MM}" "php${MM}-apache2" \
        "php${MM}-bcmath" "php${MM}-ctype" "php${MM}-curl" "php${MM}-dom" "php${MM}-exif" \
        "php${MM}-fileinfo" "php${MM}-gd" "php${MM}-iconv" "php${MM}-intl" "php${MM}-mbstring" \
        "php${MM}-mysqli" "php${MM}-mysqlnd" "php${MM}-opcache" "php${MM}-openssl" "php${MM}-pdo" \
        "php${MM}-pdo_mysql" "php${MM}-phar" "php${MM}-session" "php${MM}-simplexml" "php${MM}-sodium" \
        "php${MM}-tidy" "php${MM}-tokenizer" "php${MM}-xml" "php${MM}-xmlreader" "php${MM}-xmlwriter" \
        "php${MM}-zip"; \
    ln -sf "/usr/bin/php${MM}" /usr/bin/php; \
    ln -sfn "/etc/php${MM}" /etc/php; \
    # Nama berkas modul mod_php berbeda antarversi; tulis Include yang tepat
    mkdir -p /etc/apache2/opensid; \
    MOD="$(find /usr/lib/apache2 -maxdepth 1 -name "*php${MM}*.so" | head -1)"; \
    test -n "$MOD"; \
    echo "LoadModule php_module ${MOD}" > /etc/apache2/opensid/php-module.conf; \
    # Gagal lebih awal bila ada ekstensi yang hilang
    php -r 'foreach (["pdo_mysql","curl","fileinfo","gd","iconv","json","mbstring","mysqli","mysqlnd","tidy","zip","exif","intl","bcmath","opcache"] as $e) { if (!extension_loaded($e)) { fwrite(STDERR, "Ekstensi hilang: $e\n"); exit(1); } }'; \
    php -v | head -1

ENV LD_PRELOAD=/usr/lib/preloadable_libiconv.so

COPY docker/apache/httpd.conf         /etc/apache2/httpd.conf
COPY docker/php/opensid.ini           /etc/php/conf.d/zz-opensid.ini
COPY docker/php/opensid-security.ini  /etc/php/conf.d/zz-opensid-security.ini
COPY docker/init-config.php           /usr/local/bin/opensid-init-config.php
COPY docker/firstrun.php              /usr/local/bin/opensid-firstrun.php
COPY docker/entrypoint.sh             /usr/local/bin/opensid-entrypoint
RUN set -eux; \
    chmod 0755 /usr/local/bin/opensid-entrypoint; \
    test -f /etc/apache2/mime.types

WORKDIR /var/www/html
# Source dimiliki root: aplikasi tidak bisa mengubah kodenya sendiri
COPY --from=src /src/ /var/www/html/
# Hanya direktori data yang bisa ditulis oleh www-data (uid 82)
RUN set -eux; \
    chown -R www-data:www-data /var/www/html/desa /var/www/html/backup_inkremental /var/www/html/storage/logs /var/www/html/storage/framework; \
    chmod 0750 /var/www/html/desa /var/www/html/backup_inkremental

# Pastikan konfigurasi Apache valid dan mod_php termuat (gagal saat build, bukan saat jalan)
RUN set -eux; \
    mkdir -p /tmp/httpd; \
    httpd -t -f /etc/apache2/httpd.conf; \
    httpd -M -f /etc/apache2/httpd.conf 2>&1 | grep -E "php_module|mpm_prefork_module|remoteip_module|headers_module"; \
    rm -rf /tmp/httpd

ARG OPENSID_REF=unknown
ARG OPENSID_REVISION=unknown
ENV OPENSID_REF=${OPENSID_REF} \
    OPENSID_REVISION=${OPENSID_REVISION} \
    CI_ENV=production

LABEL org.opencontainers.image.title="OpenSID" \
      org.opencontainers.image.description="OpenSID (Sistem Informasi Desa): Alpine + Apache + PHP, non-root" \
      org.opencontainers.image.source="https://github.com/OpenSID/OpenSID" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

# Data yang harus dipertahankan antar-container (lihat docker/README.md untuk opsi mount yang lebih rinci)
VOLUME ["/var/www/html/desa", "/var/www/html/backup_inkremental", "/var/www/html/storage/logs"]

USER www-data
EXPOSE 8080
STOPSIGNAL SIGWINCH

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD curl -fsS -o /dev/null http://127.0.0.1:8080/robots.txt || exit 1

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/opensid-entrypoint"]
CMD ["serve"]
