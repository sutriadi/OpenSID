<?php
// Membuat desa/config/database.php (dan config.php bila belum ada) dari variabel lingkungan,
// lalu menunggu database siap. Dijalankan oleh entrypoint sebelum Apache start.

$env = static function (string $key, ?string $default = null): ?string {
    $v = getenv($key);

    return ($v === false || $v === '') ? $default : $v;
};

$host = $env('OPENSID_DB_HOST');
$dir  = '/var/www/html/desa/config';

if ($host === null) {
    if (! is_file($dir . '/database.php')) {
        fwrite(STDERR, "[opensid] OPENSID_DB_HOST belum diisi dan desa/config/database.php tidak ada.\n");
        exit(1);
    }
    fwrite(STDERR, "[opensid] Memakai desa/config/database.php yang sudah ada.\n");
    exit(0);
}

$port = (int) $env('OPENSID_DB_PORT', '3306');
$name = $env('OPENSID_DB_NAME', 'opensid');
$user = $env('OPENSID_DB_USER', 'opensid');
$pass = $env('OPENSID_DB_PASSWORD', '');

if (! is_dir($dir) && ! mkdir($dir, 0775, true) && ! is_dir($dir)) {
    fwrite(STDERR, "[opensid] Gagal membuat {$dir}\n");
    exit(1);
}

$database = "<?php\n"
    . "// File ini dibuat otomatis oleh entrypoint container dari variabel OPENSID_DB_*.\n"
    . "// Hapus OPENSID_DB_HOST dari environment jika ingin mengelola file ini secara manual.\n"
    . '$db[\'default\'][\'hostname\'] = ' . var_export($host, true) . ";\n"
    . '$db[\'default\'][\'username\'] = ' . var_export($user, true) . ";\n"
    . '$db[\'default\'][\'password\'] = ' . var_export($pass, true) . ";\n"
    . '$db[\'default\'][\'port\']     = ' . $port . ";\n"
    . '$db[\'default\'][\'database\'] = ' . var_export($name, true) . ";\n"
    . '$db[\'default\'][\'dbcollat\'] = \'utf8mb4_general_ci\'' . ";\n"
    . '$db[\'default\'][\'stricton\'] = true' . ";\n"
    . '$db[\'default\'][\'options\']  = []' . ";\n";

file_put_contents($dir . '/database.php', $database);

if (! is_file($dir . '/config.php')) {
    $hosts = array_values(array_filter(array_map('trim', explode(',', (string) $env('OPENSID_TRUSTED_HOSTS', '')))));
    $config = "<?php\n"
        . "// Konfigurasi tambahan OpenSID. Boleh diedit; tidak ditimpa oleh entrypoint.\n"
        . '$config[\'user_admin\']    = 0' . ";\n"
        . '$config[\'trusted_hosts\'] = ' . var_export($hosts, true) . ";\n";
    file_put_contents($dir . '/config.php', $config);
}

// Tunggu database siap (default 60 detik)
$wait     = (int) $env('OPENSID_DB_WAIT', '60');
$deadline = time() + $wait;
$lastErr  = '';

do {
    try {
        new PDO("mysql:host={$host};port={$port};dbname={$name}", $user, $pass, [PDO::ATTR_TIMEOUT => 3]);
        fwrite(STDERR, "[opensid] Database siap.\n");
        exit(0);
    } catch (Throwable $e) {
        $lastErr = $e->getMessage();
        sleep(2);
    }
} while (time() < $deadline);

fwrite(STDERR, "[opensid] PERINGATAN: database belum bisa dihubungi setelah {$wait} detik: {$lastErr}\n");
exit(0);
