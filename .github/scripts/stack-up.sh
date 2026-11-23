#!/bin/sh
# Menjalankan stack docker/docker-compose.yml untuk CI dan menunggu first-run selesai.
#   stack-up.sh IMAGE [production|testing]
# 'testing' memasang CI_ENV=testing (captcha login dimatikan agar login otomatis bisa diuji).
# Mengekspor COMPOSE, ADMIN_PW (dan EXPECT_ADMIN_PASSWORD) ke $GITHUB_ENV bila tersedia.
set -eu
IMAGE="$1"
MODE="${2:-production}"
ADMIN_PW='Ci_Test2026+'

{
    echo "OPENSID_IMAGE=$IMAGE"
    echo "DB_ROOT_PASSWORD=$(openssl rand -hex 12)"
    echo "DB_PASSWORD=$(openssl rand -hex 12)"
    echo "WEB_PORT=8080"
    echo "OPENSID_ADMIN_PASSWORD=$ADMIN_PW"
} > docker/.env

COMPOSE="docker compose -f docker/docker-compose.yml"
if [ "$MODE" = "testing" ]; then
    cat > /tmp/test.override.yml <<'YML'
services:
  web:
    environment:
      CI_ENV: testing
YML
    COMPOSE="$COMPOSE -f /tmp/test.override.yml"
fi
COMPOSE="$COMPOSE --env-file docker/.env"

if [ -n "${GITHUB_ENV:-}" ]; then
    {
        echo "COMPOSE=$COMPOSE"
        echo "ADMIN_PW=$ADMIN_PW"
        echo "EXPECT_ADMIN_PASSWORD=$ADMIN_PW"
    } >> "$GITHUB_ENV"
fi

$COMPOSE up -d
$COMPOSE ps

# 1) Tunggu first-run: seeder + penggantian password admin (dikerjakan entrypoint, bukan oleh curl kita,
#    supaya tidak ada dua permintaan pertama yang menjalankan seeder bersamaan).
echo "Menunggu first-run (seeder + rotasi password admin)..."
ok=0
for i in $(seq 1 72); do
    if $COMPOSE exec -T -e EXPECT_ADMIN_PASSWORD="$ADMIN_PW" web php < .github/scripts/verify-admin.php > /tmp/verify-admin.txt 2>&1; then
        ok=1
        break
    fi
    if [ $((i % 6)) -eq 1 ] && [ "$i" -le 13 ]; then
        echo "  ... belum siap (percobaan $i): $(tr '\n' ' ' < /tmp/verify-admin.txt | cut -c1-300)"
    fi
    sleep 5
done
cat /tmp/verify-admin.txt || true
if [ "$ok" != 1 ]; then
    echo "::error title=First-run gagal::password admin belum diganti / seeder belum selesai"
    echo "--- desa/config (password disamarkan)"
    $COMPOSE exec -T web sh -c 'ls -la desa/config; sed -E "s/(password.*= ).*/\1<disamarkan>/" desa/config/database.php; id' || true
    $COMPOSE logs --no-color --tail=150 web db || true
    exit 1
fi

# 2) Halaman depan harus 200
code=000
for i in $(seq 1 30); do
    code=$(curl -s -o /tmp/home.html -w '%{http_code}' -L --max-time 120 http://127.0.0.1:8080/ || true)
    echo "beranda percobaan $i: HTTP $code"
    [ "$code" = 200 ] && break
    sleep 3
done
if [ "$code" != 200 ]; then
    echo "::error title=Beranda tidak 200::HTTP $code"
    $COMPOSE logs --no-color --tail=150 web || true
    exit 1
fi
echo "Stack siap."
