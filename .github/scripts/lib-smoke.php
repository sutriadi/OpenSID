<?php
// Uji asap library kunci OpenSID (xlsx, PDF, gambar, zip, tanggal) dengan semua deprecation ditampung.
// Jalankan dari root aplikasi:  php .github/scripts/lib-smoke.php
$root = getenv('APP_ROOT') ?: getcwd();
chdir($root);
error_reporting(E_ALL);
$dep = [];
set_error_handler(static function ($no, $str, $file, $line) use (&$dep, $root) {
    if ($no & (E_DEPRECATED | E_USER_DEPRECATED)) {
        $k = str_replace($root . '/', '', $file) . ' :: ' . substr($str, 0, 120);
        $dep[$k] = ($dep[$k] ?? 0) + 1;

        return true;
    }

    // TCPDF dan Html2Pdf sama-sama mendefinisikan konstanta; di proses uji keduanya dimuat bersamaan
    if (($no & E_WARNING) && str_contains($str, 'already defined')) {
        return true;
    }

    return false;
});
require $root . '/vendor/autoload.php';

$ok = $gagal = [];
$t = static function (string $nama, callable $f) use (&$ok, &$gagal) {
    try {
        $r = $f();
        $ok[] = $nama . ($r ? " ({$r})" : '');
    } catch (Throwable $e) {
        $gagal[] = "{$nama}: " . get_class($e) . ': ' . substr($e->getMessage(), 0, 200) . ' @ ' . basename($e->getFile()) . ':' . $e->getLine();
    }
};

$t('iconv //TRANSLIT (musl vs gnu-libiconv)', static function () {
    $r = iconv('UTF-8', 'ASCII//TRANSLIT', "Kecamatan Çıkış Ñandú é");
    if ($r === false || str_contains($r, '?')) {
        throw new RuntimeException('TRANSLIT tidak berfungsi: ' . var_export($r, true));
    }

    return $r;
});

$t('FastExcel/OpenSpout: tulis + baca xlsx', static function () {
    $f = sys_get_temp_dir() . '/uji-' . getmypid() . '.xlsx';
    $rows = collect([['nama' => 'Ani', 'umur' => 30], ['nama' => 'Budi', 'umur' => 25]]);
    (new Rap2hpoutre\FastExcel\FastExcel($rows))->export($f);
    $back = (new Rap2hpoutre\FastExcel\FastExcel())->import($f);
    unlink($f);
    if ($back->count() !== 2 || $back[0]['nama'] !== 'Ani') {
        throw new RuntimeException('isi xlsx tidak cocok');
    }

    return '2 baris';
});

$t('FastExcel/OpenSpout: csv', static function () {
    $f = sys_get_temp_dir() . '/uji-' . getmypid() . '.csv';
    (new Rap2hpoutre\FastExcel\FastExcel(collect([['a' => 1, 'b' => 2]])))->export($f);
    $n = (new Rap2hpoutre\FastExcel\FastExcel())->import($f)->count();
    unlink($f);
    if ($n !== 1) {
        throw new RuntimeException('csv tidak cocok');
    }
});

$t('TCPDF', static function () {
    $pdf = new TCPDF();
    $pdf->AddPage();
    $pdf->writeHTML('<h1>Uji</h1><table border="1"><tr><td>a</td><td>b</td></tr></table>');
    $s = $pdf->Output('', 'S');
    if (strncmp($s, '%PDF', 4) !== 0) {
        throw new RuntimeException('bukan PDF');
    }

    return strlen($s) . ' byte';
});

$t('Html2Pdf', static function () {
    $h = new Spipu\Html2Pdf\Html2Pdf('P', 'A4', 'en');
    $h->writeHTML('<p>uji <b>html2pdf</b></p>');
    $s = $h->output('uji.pdf', 'S');
    if (strncmp($s, '%PDF', 4) !== 0) {
        throw new RuntimeException('bukan PDF');
    }

    return strlen($s) . ' byte';
});

$t('Intervention Image (GD): buat, resize, encode', static function () {
    Intervention\Image\ImageManagerStatic::configure(['driver' => 'gd']);
    $i = Intervention\Image\ImageManagerStatic::canvas(200, 100, '#ff0000')->resize(100, 50);
    $d = (string) $i->encode('jpg', 80);
    if ($i->width() !== 100) {
        throw new RuntimeException('lebar salah');
    }

    return strlen($d) . ' byte';
});

$t('Carbon: tanggal Indonesia', static function () {
    return Carbon\Carbon::create(2026, 11, 23)->locale('id')->translatedFormat('l, d F Y');
});

$t('Illuminate Collection + Str', static function () {
    return Illuminate\Support\Str::slug('Sistem Informasi Desa') . ' / ' . collect([3, 1, 2])->sort()->implode(',');
});

$t('Guzzle', static function () {
    new GuzzleHttp\Client(['timeout' => 1]);
});

$t('ZipArchive', static function () {
    $f = sys_get_temp_dir() . '/uji-' . getmypid() . '.zip';
    $z = new ZipArchive();
    $z->open($f, ZipArchive::CREATE);
    $z->addFromString('a.txt', 'isi');
    $z->close();
    $ok = filesize($f) > 0;
    unlink($f);
    if (! $ok) {
        throw new RuntimeException('zip kosong');
    }
});

$t('tidy', static function () {
    $x = tidy_parse_string('<p>uji', ['show-body-only' => true], 'utf8');
    $x->cleanRepair();

    return trim((string) $x);
});

echo "== UJI LIBRARY (PHP " . PHP_VERSION . ")\n";
foreach ($ok as $x) {
    echo "  OK      {$x}\n";
}
foreach ($gagal as $x) {
    echo "  GAGAL   {$x}\n";
}

$per = [];
foreach ($dep as $k => $n) {
    $lokasi = explode(' :: ', $k)[0];
    $kunci = preg_match('#^vendor/([^/]+/[^/]+)#', $lokasi, $m) ? 'vendor/' . $m[1] : (explode('/', $lokasi)[0] ?: $lokasi);
    $per[$kunci] = ($per[$kunci] ?? 0) + $n;
}
arsort($per);
echo '== DEPRECATION saat uji library: ' . array_sum($dep) . ' kejadian, ' . count($dep) . " pesan unik\n";
foreach (array_slice($per, 0, 10, true) as $k => $n) {
    echo "  {$n}x  {$k}\n";
}
$i = 0;
foreach ($dep as $k => $n) {
    if ($i++ >= 8) {
        break;
    }
    echo "    - {$k}\n";
}
exit($gagal ? 1 : 0);
