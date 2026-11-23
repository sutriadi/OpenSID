<?php

// Dijalankan DI DALAM container web:  docker compose exec -T web php < .github/scripts/verify-admin.php
// Memastikan password admin bawaan "sid304" sudah diganti dan password dari OPENSID_ADMIN_PASSWORD berlaku.
$expected = getenv('EXPECT_ADMIN_PASSWORD') ?: '';
$db       = [];
include '/var/www/html/desa/config/database.php';
$c = $db['default'];
mysqli_report(MYSQLI_REPORT_OFF);
$l = mysqli_init();
$l->options(MYSQLI_OPT_CONNECT_TIMEOUT, 5);
if (! @$l->real_connect($c['hostname'], $c['username'], $c['password'], $c['database'], (int) $c['port'])) {
    echo "DB: {$l->connect_error} (host={$c['hostname']} user={$c['username']} db={$c['database']} port={$c['port']} panjang_pw=" . strlen((string) $c['password']) . ")\n";
    exit(2);
}
$h = $l->query("SELECT password FROM `user` WHERE username='admin' ORDER BY id LIMIT 1")->fetch_row()[0] ?? '';
$fail = 0;
if ($h === '') {
    echo "GAGAL: akun admin tidak ditemukan\n";
    exit(1);
}
if (password_verify('sid304', $h)) {
    echo "GAGAL: password bawaan sid304 MASIH berlaku\n";
    $fail = 1;
} else {
    echo "OK: sid304 tidak lagi berlaku\n";
}
if ($expected !== '') {
    if (password_verify($expected, $h)) {
        echo "OK: password dari OPENSID_ADMIN_PASSWORD berlaku\n";
    } else {
        echo "GAGAL: password dari OPENSID_ADMIN_PASSWORD tidak cocok\n";
        $fail = 1;
    }
}
exit($fail);
