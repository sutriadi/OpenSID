# syntax=docker/dockerfile:1
#
# Image produksi OpenSID (PHP + Apache).
# Source code OpenSID (termasuk vendor/) di-bake ke dalam image.
# Data desa (konfigurasi, unggahan, app_key) disimpan di volume /var/www/html/desa.
#
# Build (dari root repo):
#   docker build -f docker/Dockerfile -t opensid:local .
#
# Versi PHP: kode di branch ini membatasi PHP >= 8.1.0 dan <= 8.3.0
# (minPhpVersion/maxPhpVersion di donjo-app/config/constants.php, juga dipakai installer dan halaman
# Info Sistem). Karena dibandingkan dengan "8.3.0", hanya 8.1.x, 8.2.x, dan 8.3.0 yang dianggap lolos.
# Default 8.2: masih dalam rentang itu dan sesuai panduan OpenDesa untuk rilis 2605-2606.
# Ganti lewat --build-arg PHP_VERSION=8.1 jika perlu.

ARG PHP_VERSION=8.2

# ---------------------------------------------------------------------------
# Tahap 1: siapkan source (bersihkan file dev, buat .htaccess)
# ---------------------------------------------------------------------------
FROM alpine:3.20 AS src

COPY . /src

RUN set -eux; \
    cd /src; \
    # Buang file yang hanya dipakai pengembang/CI agar tidak ikut terbit di web root
    rm -rf .git .github docker bin tests node_modules \
        package.json package-lock.json tsconfig.json playwright.config.ts .e2e.env.example \
        phpunit.xml rector.php .php-cs-fixer.php .prettierrc.json .gitattributes; \
    # .htaccess dibuat dari template resmi, tanpa redirect HTTPS.
    # TLS diakhiri oleh reverse proxy; header X-Forwarded-Proto ditangani di konfigurasi Apache.
    sed -e '/^RewriteCond %{HTTP:CF-Visitor}/,/^RewriteRule \^(\.\*)\$ https/d' htaccess.apache.txt > .htaccess; \
    if grep -q 'https://%{HTTP_HOST}' .htaccess; then echo "Redirect HTTPS masih ada di .htaccess" >&2; exit 1; fi; \
    grep -q 'RewriteRule \^(\.\*)\$ index.php/\$1' .htaccess; \
    mkdir -p desa backup_inkremental storage/logs storage/framework/cache storage/framework/sessions storage/framework/views

# ---------------------------------------------------------------------------
# Tahap 2: image akhir
# ---------------------------------------------------------------------------
FROM php:${PHP_VERSION}-apache

# Ekstensi yang diperiksa installer OpenSID: pdo_mysql, curl, fileinfo, gd, iconv, json,
# mbstring, mysqli, mysqlnd, tidy, zip, exif. Yang tidak ada di daftar ini sudah
# bawaan image php resmi. intl dan bcmath ditambahkan karena sering dibutuhkan library Laravel/Carbon.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libfreetype6-dev \
        libicu-dev \
        libjpeg-dev \
        libpng-dev \
        libtidy-dev \
        libzip-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" \
        bcmath \
        exif \
        gd \
        intl \
        mysqli \
        opcache \
        pdo_mysql \
        tidy \
        zip; \
    a2enmod rewrite headers expires; \
    rm -rf /var/lib/apt/lists/*; \
    # Gagal lebih awal saat build jika ada ekstensi yang hilang
    php -r 'foreach (["pdo_mysql","curl","fileinfo","gd","iconv","json","mbstring","mysqli","mysqlnd","tidy","zip","exif","intl","bcmath"] as $e) { if (!extension_loaded($e)) { fwrite(STDERR, "Ekstensi hilang: $e\n"); exit(1); } }'

COPY docker/php.ini /usr/local/etc/php/conf.d/zz-opensid.ini
COPY docker/apache-opensid.conf /etc/apache2/conf-available/opensid.conf
COPY docker/init-config.php /usr/local/bin/opensid-init-config.php
COPY docker/entrypoint.sh /usr/local/bin/opensid-entrypoint
RUN chmod +x /usr/local/bin/opensid-entrypoint && a2enconf opensid

WORKDIR /var/www/html
COPY --from=src --chown=www-data:www-data /src/ /var/www/html/

ARG OPENSID_REF=unknown
ARG OPENSID_REVISION=unknown
ENV OPENSID_REF=${OPENSID_REF} \
    OPENSID_REVISION=${OPENSID_REVISION}

LABEL org.opencontainers.image.title="OpenSID" \
      org.opencontainers.image.description="OpenSID (Sistem Informasi Desa) di PHP + Apache" \
      org.opencontainers.image.source="https://github.com/OpenSID/OpenSID" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

# Data yang harus dipertahankan antar-container
VOLUME ["/var/www/html/desa", "/var/www/html/backup_inkremental"]

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS -o /dev/null http://127.0.0.1/robots.txt || exit 1

ENTRYPOINT ["opensid-entrypoint"]
CMD ["apache2-foreground"]
