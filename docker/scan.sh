#!/bin/sh
# Pemindai forensik READ-ONLY untuk instalasi OpenSID -- sudah terpasang di image ini sebagai
# /usr/local/bin/opensid-scan. Tidak mengunggah, mengeksekusi, atau mengubah apa pun -- hanya membaca
# dan melaporkan.
#
# Pemakaian (dari host, container sedang berjalan):
#   docker compose exec -T web opensid-scan | tee laporan.txt
#   podman exec -it desa_kopandakansatu opensid-scan | tee laporan.txt
#   podman exec -it desa_kopandakansatu opensid-scan /path/lain/di/dalam/container   # override lokasi
#
# Opsional, untuk ikut memeriksa tabel `user` (cari akun admin siluman):
#   podman exec -it -e DB_HOST=db -e DB_USER=opensid -e DB_PASS=... -e DB_NAME=opensid \
#     desa_kopandakansatu opensid-scan | tee laporan.txt
#
# Bisa juga dijalankan berdiri sendiri di luar image ini (bukan di dalam container) terhadap folder
# OpenSID mana pun di server:
#   sudo sh scan.sh /path/ke/root/opensid | tee laporan.txt
set -eu

ROOT="${1:-${ROOT:-/var/www/html}}"
cd "$ROOT" 2>/dev/null || { echo "Tidak bisa masuk ke $ROOT"; exit 2; }
ROOT="$(pwd)"

echo "=============================================================================="
echo " Pemindai forensik OpenSID -- READ ONLY -- $(date)"
echo " Root  : $ROOT"
echo " (simpan output ini dengan: sh scan-kompromi-opensid.sh $ROOT | tee laporan.txt)"
echo "=============================================================================="

sect() { echo; echo "## $*"; echo "--------------------------------------------------------------------------------"; }

# -----------------------------------------------------------------------------------
sect "1. Berkas PHP/eksekusi di folder yang SEHARUSNYA cuma data (paling umum berisi webshell)"
# Folder ini seharusnya tidak pernah berisi .php/.phtml/.phar/.cgi dst. Lihat donjo-app/config/installer.php
# dan docker/apache/httpd.conf untuk daftar resmi folder data OpenSID.
# Catatan: "assets/" dan "storage/app/" TIDAK dimasukkan -- keduanya bagian sah dari kode OpenSID
# yang memang berisi .php (mis. assets/fonts/*.php dari TCPDF, storage/app/template/.../view.php
# untuk template surat). Memasukkannya di sini hanya menghasilkan alarm palsu.
DATA_DIRS="desa/upload desa/arsip desa/logo desa/pengaturan desa/anjungan desa/widgets desa/cache desa/themes desa/template-surat backup_inkremental"
found=0
for d in $DATA_DIRS; do
    [ -d "$d" ] || continue
    out=$(find "$d" -type f \( \
        -iname '*.php' -o -iname '*.php[0-9]' -o -iname '*.phtml' -o -iname '*.pht' \
        -o -iname '*.phar' -o -iname '*.phps' -o -iname '*.cgi' -o -iname '*.pl' \
        -o -iname '*.py' -o -iname '*.asp*' -o -iname '*.jsp' -o -iname '.htaccess' \
        -o -iname '*.sh' -o -iname '*.exe' \
    \) 2>/dev/null)
    if [ -n "$out" ]; then
        found=1
        echo "!! DITEMUKAN di $d:"
        echo "$out" | while IFS= read -r f; do
            printf '     %-60s  %6d bytes  diubah %s\n' "$f" "$(stat -c%s "$f" 2>/dev/null || echo ?)" "$(stat -c%y "$f" 2>/dev/null | cut -d. -f1)"
        done
    fi
done
[ "$found" = 0 ] && echo "(bersih: tidak ada berkas eksekusi di folder data)"

# Nama file double-extension umum dipakai menyamarkan webshell, mis. gambar.jpg.php
sect "1b. Nama berkas mencurigakan (ekstensi ganda / nama khas webshell)"
find . -xdev -type f \( \
    -iregex '.*\.\(jpg\|jpeg\|png\|gif\|pdf\|txt\|zip\)\.\(php[0-9]?\|phtml\|phar\)$' \
    -o -iname 'wso*.php' -o -iname 'c99*.php' -o -iname 'r57*.php' -o -iname 'b374k*' \
    -o -iname 'FilesMan*' -o -iname '*shell*.php' -o -iname '*adminer*.php' -o -iname 'alfa*.php' \
    -o -iname '*.suspected' -o -iname '*.x' -o -iname '*.bak.php' \
    \) 2>/dev/null | grep -v '^\./vendor/' | sed 's/^/  CURIGA: /' || echo "(tidak ada)"

# -----------------------------------------------------------------------------------
sect "2. Tanda tangan kode webshell di SEMUA berkas .php (termasuk yang disisipkan ke berkas sah)"
# Pola ini umum dipakai webshell/backdoor untuk menyamarkan payload atau menjalankan perintah OS.
PATTERN='eval\s*\(\s*(base64_decode|gzinflate|gzuncompress|str_rot13)\s*\(|assert\s*\(\s*\$_(GET|POST|REQUEST|COOKIE)|create_function\s*\(|\bshell_exec\s*\(|\bsystem\s*\(\s*\$_|\bpassthru\s*\(\s*\$_|\bproc_open\s*\(|@\s*\$_(GET|POST|REQUEST)\[.{0,30}\]\s*\(|\bFilesMan\b|preg_replace\s*\(.{0,40}/e[^a-zA-Z]'
grep -rlEI "$PATTERN" --include='*.php' --include='*.phtml' --include='*.phar' . 2>/dev/null \
  | grep -vE '^\./(vendor|node_modules)/' \
  | while IFS= read -r f; do
      echo "!! POLA MENCURIGAKAN: $f"
      grep -nEI "$PATTERN" "$f" 2>/dev/null | head -2 | sed 's/^/       /' | cut -c1-160
    done || echo "(tidak ada pola yang cocok di luar vendor/)"
echo "(Catatan: vendor/ TIDAK diperiksa di atas karena isinya besar & banyak false-positive legit."
echo " Bila curiga pada vendor/, bandingkan hash dengan composer.lock / instalasi bersih.)"

# -----------------------------------------------------------------------------------
sect "3. .htaccess yang bisa MENGAKTIFKAN eksekusi PHP di folder data (celah klasik upload)"
find desa storage backup_inkremental assets -iname '.htaccess' -type f 2>/dev/null | while IFS= read -r f; do
    if grep -qiE 'SetHandler\s+application/x-httpd-php|AddType\s+application/x-httpd-php|AddHandler\s+.*php|php_flag\s+engine\s+on|php_admin_flag\s+engine\s+on|Allow from all' "$f" 2>/dev/null; then
        echo "!! $f MENGAKTIFKAN PHP / melonggarkan akses -- isi:"
        sed 's/^/       /' "$f"
    fi
done
echo "(selesai; tidak ada baris di atas = tidak ditemukan .htaccess yang melonggarkan PHP)"

# -----------------------------------------------------------------------------------
sect "4. Izin berkas yang longgar (world-writable) di kode & folder data"
find . -xdev -type f -perm -002 2>/dev/null | grep -vE '^\./(storage/framework|storage/logs)/' | head -40
echo "(berkas di atas bisa ditulis SIAPA SAJA di sistem -- seharusnya kosong/sangat sedikit)"

# -----------------------------------------------------------------------------------
sect "5. Berkas yang diubah paling baru (fokus ke luar folder data normal -- indikasi backdoor baru)"
echo "(Catatan: tepat setelah image baru dibangun/di-deploy, SEMUA berkas kode wajar muncul di sini --"
echo " tanggalnya adalah waktu build, bukan tanda apa pun. Bagian ini baru berarti setelah container"
echo " berjalan >14 hari tanpa pembaruan image: kode seharusnya sudah tidak berubah sama sekali karena"
echo " rootfs hanya-baca -- berkas kode yang muncul di sini pada kondisi itu patut dicurigai.)"
find . -xdev -type f -mtime -14 2>/dev/null \
  | grep -vE '^\./(storage/(logs|framework)|backup_inkremental|desa/(cache|upload|arsip|logo|pengaturan|anjungan|widgets|themes|template-surat))/' \
  | grep -vE '^\./\.git/' \
  | xargs -r stat -c '%y %n' 2>/dev/null | sort | tail -60

# -----------------------------------------------------------------------------------
sect "6. Cron job (user www-data/root dan /etc/cron*) -- backdoor sering memasang entri cron"
for u in root www-data "$(id -un 2>/dev/null)"; do
    c=$(crontab -l -u "$u" 2>/dev/null) && [ -n "$c" ] && { echo "crontab $u:"; echo "$c" | sed 's/^/   /'; }
done
[ -d /etc/cron.d ] && { echo "/etc/cron.d:"; grep -rH . /etc/cron.d 2>/dev/null | grep -v '^#' | sed 's/^/   /'; }
true

# -----------------------------------------------------------------------------------
sect "7. Proses & koneksi jaringan yang sedang berjalan (reverse shell / miner umumnya terlihat di sini)"
ps aux 2>/dev/null | grep -vE '^\s*(root|www-data).*\b(httpd|apache2|php-fpm|mysqld|mariadbd|tini|su-exec|ps|grep)\b' | head -30 || ps -ef 2>/dev/null | head -30
echo "---- koneksi keluar yang sedang terbuka ----"
( ss -tnp 2>/dev/null || netstat -tnp 2>/dev/null || echo "(ss/netstat tidak tersedia di container minimal)" ) | grep -v '127.0.0.1\|ESTAB.*:80 \|ESTAB.*:443 ' | head -30

# -----------------------------------------------------------------------------------
sect "8. Modul/plugin PHP tak terduga & fungsi berbahaya yang masih aktif"
php -v 2>/dev/null | head -1 || echo "(php CLI tidak tersedia)"
php -r 'foreach (["exec","shell_exec","system","passthru","proc_open","popen","assert","create_function"] as $f) if (function_exists($f)) echo "  AKTIF (seharusnya nonaktif di produksi): $f\n";' 2>/dev/null || true

# -----------------------------------------------------------------------------------
if [ -n "${DB_HOST:-}" ]; then
sect "9. Akun di tabel 'user' (periksa akun yang tidak Anda kenal / dibuat belakangan)"
    php -r '
        $h=getenv("DB_HOST"); $u=getenv("DB_USER")?:"opensid"; $p=getenv("DB_PASS")?:""; $n=getenv("DB_NAME")?:"opensid";
        $l=@new mysqli($h,$u,$p,$n);
        if ($l->connect_errno) { fwrite(STDERR,"Gagal konek DB: {$l->connect_error}\n"); exit(0); }
        $r=$l->query("SELECT id,username,email,active,last_login FROM user ORDER BY id");
        while ($row=$r->fetch_assoc()) printf("  id=%-4s user=%-20s email=%-30s aktif=%s login_terakhir=%s\n",
            $row["id"],$row["username"],$row["email"]??"-",$row["active"],$row["last_login"]??"-");
    ' 2>&1
else
    sect "9. (dilewati) Akun di tabel user -- isi DB_HOST/DB_USER/DB_PASS/DB_NAME untuk ikut memeriksa"
fi

echo
echo "=============================================================================="
echo " SELESAI."
echo " Baris berawalan '!!' adalah temuan yang paling perlu diperiksa dulu."
echo " Bila belum disimpan ke berkas, jalankan ulang dengan: ... | tee laporan.txt"
echo "=============================================================================="
