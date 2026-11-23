<?php

/**
 * Membuat desa/config/database.php dan desa/config/config.php dari environment, lalu menunggu database siap.
 * Dijalankan entrypoint (sebagai www-data) sebelum Apache start.
 *
 * Variabel (setiap OPENSID_X juga bisa diberikan sebagai OPENSID_X_FILE berisi path berkas rahasia/Docker secret):
 *   OPENSID_DB_HOST, OPENSID_DB_PORT (3306), OPENSID_DB_NAME (opensid), OPENSID_DB_USER (opensid), OPENSID_DB_PASSWORD
 *   OPENSID_DB_WAIT          detik menunggu database (60)
 *   OPENSID_TRUSTED_HOSTS    daftar host tepercaya dipisah koma
 *   OPENSID_ENCRYPTION_KEY   kunci tanda-tangan tautan verifikasi (acak & dipertahankan bila tidak diisi)
 *   OPENSID_COOKIE_SECURE    auto (default: ikuti HTTPS dari proxy) | true | false
 *
 * Bila OPENSID_DB_HOST tidak diisi, desa/config/database.php yang sudah ada dipakai apa adanya.
 * config.php hanya ditulis ulang bila belum ada atau masih berpenanda OPENSID-DOCKER-GENERATED;
 * berkas yang sudah Anda edit sendiri (tanpa penanda) tidak pernah ditimpa.
 */
const MARKER = '// OPENSID-DOCKER-GENERATED';
const DIR    = '/var/www/html/desa/config';

function say(string $msg): void
{
    fwrite(STDERR, "[opensid] {$msg}\n");
}

/** Baca env; mendukung varian _FILE. */
function env(string $key, ?string $default = null): ?string
{
    $file = getenv($key . '_FILE');
    if ($file !== false && $file !== '') {
        if (! is_readable($file)) {
            say("KESALAHAN: {$key}_FILE menunjuk ke berkas yang tidak bisa dibaca: {$file}");
            exit(1);
        }

        return rtrim((string) file_get_contents($file), "\r\n");
    }

    $v = getenv($key);

    return ($v === false || $v === '') ? $default : $v;
}

function write_atomic(string $path, string $content, int $mode = 0640): void
{
    $tmp = $path . '.tmp' . getmypid();
    if (file_put_contents($tmp, $content) === false) {
        say("KESALAHAN: gagal menulis {$tmp}");
        exit(1);
    }
    chmod($tmp, $mode);
    rename($tmp, $path);
}

if (! is_dir(DIR) && ! mkdir(DIR, 0750, true) && ! is_dir(DIR)) {
    say('KESALAHAN: gagal membuat ' . DIR);
    exit(1);
}

$host = env('OPENSID_DB_HOST');

if ($host === null) {
    if (! is_file(DIR . '/database.php')) {
        say('KESALAHAN: OPENSID_DB_HOST belum diisi dan desa/config/database.php tidak ada.');
        exit(1);
    }
    say('Memakai desa/config/database.php yang sudah ada.');
    $port = $name = $user = $pass = null;
} else {
    $port = (int) env('OPENSID_DB_PORT', '3306');
    $name = env('OPENSID_DB_NAME', 'opensid');
    $user = env('OPENSID_DB_USER', 'opensid');
    $pass = env('OPENSID_DB_PASSWORD', '');

    if (strlen($pass) > 80) {
        // donjo-app/config/database.php menganggap kata sandi > 80 karakter sebagai terenkripsi
        say('KESALAHAN: kata sandi database lebih dari 80 karakter tidak didukung OpenSID.');
        exit(1);
    }
    if ($pass === '') {
        say('PERINGATAN: OPENSID_DB_PASSWORD kosong.');
    }

    $database = "<?php\n"
        . "// Dibuat otomatis oleh entrypoint container dari OPENSID_DB_*. Hapus OPENSID_DB_HOST dari environment\n"
        . "// bila ingin mengelola berkas ini secara manual.\n"
        . '$db[\'default\'][\'hostname\'] = ' . var_export($host, true) . ";\n"
        . '$db[\'default\'][\'username\'] = ' . var_export($user, true) . ";\n"
        . '$db[\'default\'][\'password\'] = ' . var_export($pass, true) . ";\n"
        . '$db[\'default\'][\'port\']     = ' . $port . ";\n"
        . '$db[\'default\'][\'database\'] = ' . var_export($name, true) . ";\n"
        . '$db[\'default\'][\'dbcollat\'] = \'utf8mb4_general_ci\';' . "\n"
        . '$db[\'default\'][\'stricton\'] = true;' . "\n"
        . '$db[\'default\'][\'options\']  = [];' . "\n";

    write_atomic(DIR . '/database.php', $database);
}

// ---------------------------------------------------------------------------------------------------
// config.php
// ---------------------------------------------------------------------------------------------------
$configFile = DIR . '/config.php';
$existing   = is_file($configFile) ? (string) file_get_contents($configFile) : null;

if ($existing === null || str_contains($existing, MARKER)) {
    $hosts = array_values(array_filter(array_map('trim', explode(',', (string) env('OPENSID_TRUSTED_HOSTS', '')))));
    // OpenSID memeriksa host lewat parse_url(): nama host polos (tanpa skema) dianggap kosong dan ditolak.
    $hosts = array_map(static fn (string $h): string => str_contains($h, '://') ? $h : 'https://' . $h, $hosts);

    $key = env('OPENSID_ENCRYPTION_KEY');
    if ($key === null && $existing !== null && preg_match('/\$config\[\'encryption_key\'\]\s*=\s*\'([^\']+)\'/', $existing, $m)) {
        $key = $m[1];
    }
    $key ??= bin2hex(random_bytes(32));

    $mode = strtolower((string) env('OPENSID_COOKIE_SECURE', 'auto'));
    if ($mode === 'true' || $mode === '1') {
        $secure = 'true';
    } elseif ($mode === 'false' || $mode === '0') {
        $secure = 'false';
    } else {
        // Aman di belakang proxy TLS (X-Forwarded-Proto -> HTTPS=on) dan tetap jalan di HTTP untuk uji lokal
        $secure = "(isset(\$_SERVER['HTTPS']) && \$_SERVER['HTTPS'] === 'on')";
    }

    $config = "<?php\n"
        . MARKER . "\n"
        . "// Dibuat otomatis oleh entrypoint container; ditulis ulang tiap start selama penanda di atas masih ada.\n"
        . "// Untuk mengubah manual: hapus baris penanda lalu edit bebas (tidak akan ditimpa lagi).\n"
        . '$config[\'user_admin\']     = 0;' . "\n"
        . '$config[\'trusted_hosts\']  = ' . var_export($hosts, true) . ";\n"
        . '$config[\'encryption_key\'] = ' . var_export($key, true) . ";\n"
        . '$config[\'cookie_secure\']  = ' . $secure . ";\n";

    write_atomic($configFile, $config);
}

// ---------------------------------------------------------------------------------------------------
// Tunggu database siap
// ---------------------------------------------------------------------------------------------------
if ($host === null) {
    exit(0);
}

$wait     = (int) env('OPENSID_DB_WAIT', '60');
$deadline = time() + $wait;
$lastErr  = '';

mysqli_report(MYSQLI_REPORT_OFF);

do {
    $link = mysqli_init();
    $link->options(MYSQLI_OPT_CONNECT_TIMEOUT, 3);
    if (@$link->real_connect($host, $user, $pass, $name, $port)) {
        $link->close();
        say('Database siap.');
        exit(0);
    }
    $lastErr = $link->connect_error ?: 'tidak diketahui';
    sleep(2);
} while (time() < $deadline);

say("PERINGATAN: database belum bisa dihubungi setelah {$wait} detik: {$lastErr}");
exit(0);
