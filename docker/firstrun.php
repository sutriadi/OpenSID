<?php

/**
 * First run (dijalankan entrypoint di latar belakang setelah Apache start):
 *  1. memicu permintaan HTTP pertama agar OpenSID membuat tabel + data awal (seeder) sendiri,
 *  2. mengganti password admin bawaan ("sid304") yang terkenal publik.
 *
 * Password baru diambil dari OPENSID_ADMIN_PASSWORD (atau _FILE). Bila kosong/tidak memenuhi kebijakan OpenSID
 * (8-20 karakter, ada angka, huruf kecil, huruf besar, simbol; tanpa spasi), dibuat acak dan dicetak SEKALI
 * ke log container. Hanya berlaku bila password admin masih "sid304": tidak pernah menimpa password yang sudah Anda ubah.
 */
function say(string $msg): void
{
    fwrite(STDERR, "[opensid] {$msg}\n");
}

function env(string $key): ?string
{
    $file = getenv($key . '_FILE');
    if ($file !== false && $file !== '' && is_readable($file)) {
        return rtrim((string) file_get_contents($file), "\r\n");
    }
    $v = getenv($key);

    return ($v === false || $v === '') ? null : $v;
}

function policy_ok(string $p): bool
{
    return (bool) preg_match('/^(?=.*\d)(?=.*[a-z])(?=.*[A-Z])(?=.*[^a-zA-Z0-9])(?!.*\s).{8,20}$/', $p);
}

function random_password(): string
{
    $sets = ['ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '#%+=@_-'];
    $pw   = '';
    foreach ($sets as $set) {
        $pw .= $set[random_int(0, strlen($set) - 1)];
    }
    $all = implode('', $sets);
    while (strlen($pw) < 16) {
        $pw .= $all[random_int(0, strlen($all) - 1)];
    }

    return str_shuffle($pw);
}

/** Host untuk permintaan pemicu: lolos pemeriksaan trusted_hosts bila diaktifkan. */
function trigger_host(): string
{
    $config = [];
    $file   = '/var/www/html/desa/config/config.php';
    if (is_file($file)) {
        try {
            (static function () use (&$config, $file): void {
                include $file;
            })();
        } catch (Throwable) {
        }
    }
    foreach ((array) ($config['trusted_hosts'] ?? []) as $h) {
        $host = parse_url(trim((string) $h))['host'] ?? '';
        if ($host !== '' && $host !== '0') {
            return $host;
        }
    }

    return 'localhost';
}

// --- Koneksi DB -----------------------------------------------------------------------------------------------
// Dari OPENSID_DB_* bila diberikan. Jika tidak, dari desa/config/database.php (OpenSID menyimpan password di sana dalam
// bentuk terenkripsi setelah migrasi pertama; konfigurasi seperti itu tidak bisa dibaca di sini, jadi first-run dilewati).
if (env('OPENSID_DB_HOST') !== null) {
    $c = [
        'hostname' => env('OPENSID_DB_HOST'),
        'username' => env('OPENSID_DB_USER') ?? 'opensid',
        'password' => env('OPENSID_DB_PASSWORD') ?? '',
        'database' => env('OPENSID_DB_NAME') ?? 'opensid',
        'port'     => env('OPENSID_DB_PORT') ?? 3306,
    ];
} else {
    $db = [];
    include '/var/www/html/desa/config/database.php';
    $c = $db['default'] ?? null;
    if (! $c || strlen((string) ($c['password'] ?? '')) > 80) {
        say('first-run dilewati: kredensial database tidak tersedia di environment (OPENSID_DB_*).');
        exit(0);
    }
}

mysqli_report(MYSQLI_REPORT_OFF);
$connect = static function () use ($c): ?mysqli {
    $l = mysqli_init();
    $l->options(MYSQLI_OPT_CONNECT_TIMEOUT, 3);

    return @$l->real_connect($c['hostname'], $c['username'], $c['password'], $c['database'], (int) ($c['port'] ?? 3306)) ? $l : null;
};

// --- 1. Tunggu Apache, lalu picu seeder --------------------------------------------------------------------
$ctx = stream_context_create(['http' => [
    'method'          => 'GET',
    'timeout'         => 240,
    'ignore_errors'   => true,
    'follow_location' => 1,
    'max_redirects'   => 5,
    'header'          => 'Host: ' . trigger_host() . "\r\n",
]]);

$ready = false;
for ($i = 0; $i < 60 && ! $ready; $i++) {
    $fp = @fsockopen('127.0.0.1', 8080, $errno, $errstr, 1);
    if ($fp) {
        fclose($fp);
        $ready = true;
    } else {
        sleep(1);
    }
}

$hasAdmin = static function () use ($connect): bool {
    $l = $connect();
    if (! $l) {
        return false;
    }
    $r  = $l->query("SELECT 1 FROM `user` WHERE username = 'admin' LIMIT 1");
    $ok = $r && $r->num_rows > 0;
    $l->close();

    return $ok;
};

if (! $hasAdmin()) {
    say('first-run: memicu pembuatan tabel dan data awal (bisa memakan waktu beberapa menit)...');
    @file_get_contents('http://127.0.0.1:8080/', false, $ctx);
}

for ($i = 0; $i < 180 && ! $hasAdmin(); $i++) {
    sleep(2);
    if ($i === 30) {
        // coba sekali lagi bila permintaan pertama gagal/terputus
        @file_get_contents('http://127.0.0.1:8080/', false, $ctx);
    }
}

if (! $hasAdmin()) {
    say('PERINGATAN: akun admin belum ada setelah menunggu. Buka aplikasi sekali lalu restart container agar password awal diganti.');
    exit(0);
}

// --- 2. Ganti password admin bawaan ----------------------------------------------------------------------------
$l = $connect();
$r = $l->query("SELECT id, password FROM `user` WHERE username = 'admin' ORDER BY id LIMIT 1");
$u = $r->fetch_assoc();

if (! $u || ! password_verify('sid304', (string) $u['password'])) {
    say('first-run: password admin sudah bukan bawaan; tidak diubah.');
    $l->close();
    exit(0);
}

$new      = env('OPENSID_ADMIN_PASSWORD');
$printed  = false;
if ($new === null || ! policy_ok($new)) {
    if ($new !== null) {
        say('PERINGATAN: OPENSID_ADMIN_PASSWORD tidak memenuhi kebijakan (8-20 karakter; angka, huruf kecil, huruf besar, simbol; tanpa spasi). Memakai password acak.');
    }
    $new     = random_password();
    $printed = true;
}

$hash = password_hash($new, PASSWORD_BCRYPT, ['cost' => 12]);
$st   = $l->prepare('UPDATE `user` SET password = ? WHERE id = ?');
$id   = (int) $u['id'];
$st->bind_param('si', $hash, $id);
$st->execute();

if ($st->affected_rows !== 1) {
    say('KESALAHAN: gagal mengganti password admin bawaan. Segera ganti sendiri (login admin / sid304) atau restart container.');
    $l->close();
    exit(1);
}
$l->close();

if ($printed) {
    say('==================================================================');
    say('Password awal admin DIBUAT ACAK (ditampilkan sekali ini saja):');
    say('  username: admin');
    say("  password: {$new}");
    say('Segera login dan ganti. Untuk menentukan sendiri, set OPENSID_ADMIN_PASSWORD pada instalasi baru.');
    say('==================================================================');
} else {
    say('Password admin diganti sesuai OPENSID_ADMIN_PASSWORD.');
}
