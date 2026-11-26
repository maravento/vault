<?php
// SORI migration tool: loads one client from a legacy Access (.mdb) database
// FILE: tools/sorimigrate.php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    exit(1);
}
// Installed layout has app/ next to tools/; the repository keeps it under web/
require is_file(__DIR__ . '/../app/lib.php') ? __DIR__ . '/../app/lib.php' : __DIR__ . '/../web/app/lib.php';

const BATCH = 500;
const USAGE = <<<TXT
Usage: sudo php sorimigrate.php --client SLUG --name "NAME" --mdb FILE
                                [--empresa N] [--anonymize] [--replace]

  --client     Client code: lowercase letters and digits, 2 to 30 (database sori_SLUG)
  --name       Client display name
  --mdb        Legacy database file (.mdb)
  --empresa    Company code to keep (default 1); rows of other companies are skipped
  --anonymize  For demonstrations only: replace third-party identity and contact data,
               blank secrets and skip logins, audit log and report tables.
               Without it, every table is copied as it is.
  --replace    Delete the client database first if it already exists

TXT;

// A normal migration copies every table. Only --anonymize skips these: legacy logins
// and passwords, the audit log and the report work tables hold names or secrets.
const SKIP_ANON = ['CUSUARIO', 'CAUDITORIA', 'CGRUPOSXUSUARIO'];
const SKIP_ANON_RE = '/^(RPT_|TOTALES_UPD$)/';
const BLOB_TYPES = ['blob', 'tinyblob', 'mediumblob', 'longblob', 'binary', 'varbinary'];

// Columns that hold a third-party id (NIT or similar) and keep their joins
const ID_RE = '/(Nit|CodTercero|CodProveedor|CodCliente|Tercero|TerceroAdic|TerceroRemite|TerceroDestino|NitBeneficiario|Infractor|Documento)$/i';
// Columns with the legacy login of the person who typed a record
const USER_RE = '/Digita$/i';
const NOT_ID_RE = '/(Clase|Tipo|Califica)/i';
// Columns blanked with --anonymize
const BLANK_RE = '/(NomOtroTercero|ObservaOtroTercero|NomNit|NombreCheque|Telefono|Celular|EMail|Correo|Fax|Foto|Huella|Logotipo)/i';
// Secrets of the company row, blanked with --anonymize
const SECRETS = ['T10ClaveTecnica', 'T10ClaveTecnicaF', 'T10Licencia', 'T10LicenciaFact', 'T10Token', 'T10POS', 'T10NCPOS', 'T10NDPOS'];

function out(string $s): void
{
    echo $s, "\n";
}

function stop(string $s): never
{
    fwrite(STDERR, "ERROR: $s\n");
    exit(1);
}

// The Access reader comes from the mdbtools package
function need_command(string $cmd): void
{
    foreach (explode(':', (string) getenv('PATH')) as $dir) {
        if (is_executable("$dir/$cmd")) {
            return;
        }
    }
    stop("$cmd not found; install the package mdbtools");
}

// Run a command without a shell and return its output lines
function run_lines(array $cmd): array
{
    $p = proc_open($cmd, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    if (!is_resource($p)) {
        stop('cannot run ' . $cmd[0]);
    }
    $text = stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    if (proc_close($p) !== 0) {
        stop($cmd[0] . ' failed');
    }
    return $text === '' ? [] : explode("\n", rtrim($text, "\n"));
}

function admin_pdo(?string $dbname): PDO
{
    $c = env();
    $dsn = 'mysql:host=' . ($c['DB_HOST'] ?? '127.0.0.1') . ';charset=utf8mb4';
    if (!empty($c['DB_SOCKET'])) {
        $dsn = 'mysql:unix_socket=' . $c['DB_SOCKET'] . ';charset=utf8mb4';
    }
    if ($dbname !== null) {
        $dsn .= ';dbname=' . $dbname;
    }
    return new PDO($dsn, getenv('SORI_ADMIN_USER') ?: 'root', getenv('SORI_ADMIN_PASS') ?: '', [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
}

// ----------------------------------------------------------------------------
// Anonymization
// ----------------------------------------------------------------------------

$salt = random_bytes(16);

function anon_num(string $v): int
{
    global $salt;
    return (int) hexdec(substr(hash('sha256', $salt . $v), 0, 10));
}

// Same input gives the same output in every table, so joins keep working
function anon_id(string $v): string
{
    return (string) (1000000000 + anon_num($v) % 8999999999);
}

// $lens: maximum length of each text column. Columns shorter than an id hold flags.
function anon_row(string $table, array $cols, array $row, string $client_name, array $lens): array
{
    $first = ['ANA', 'LUIS', 'MARIA', 'JOSE', 'CARLOS', 'LAURA', 'JUAN', 'SOFIA', 'PEDRO', 'LUCIA',
              'ANDRES', 'PAULA', 'DIEGO', 'CAMILA', 'MIGUEL', 'VALERIA', 'JORGE', 'DANIELA', 'FELIPE', 'NATALIA'];
    $last = ['GARCIA', 'RODRIGUEZ', 'MARTINEZ', 'LOPEZ', 'GOMEZ', 'PEREZ', 'SANCHEZ', 'RAMIREZ', 'TORRES', 'DIAZ',
             'VARGAS', 'CASTRO', 'ROJAS', 'MORENO', 'JIMENEZ', 'ORTIZ', 'SILVA', 'RUIZ', 'MEDINA', 'HERRERA'];
    $idx = array_flip($cols);
    // The legacy system stores a space for an empty value, so values are trimmed
    $get = static fn(string $c): string => isset($idx[$c]) ? trim($row[$idx[$c]]) : '';
    $set = static function (string $c, string $v) use (&$row, $idx): void {
        if (isset($idx[$c])) {
            $row[$idx[$c]] = $v;
        }
    };

    // Table-specific rules run on the original values, before the generic ones
    if ($table === 'T12TERCERO') {
        $n = anon_num($get('T12Nit') . $get('T12Nombre') . $get('T12RazonSocial'));
        $company = $get('T12RazonSocial') !== '';
        $set('T12RazonSocial', $company ? 'EMPRESA ' . substr((string) $n, 0, 6) : '');
        $set('T12Nombre', $company ? '' : $first[$n % 20]);
        $set('T12Nombre2', $company ? '' : $first[intdiv($n, 8000) % 20]);
        $set('T12Apellido', $company ? '' : $last[intdiv($n, 20) % 20]);
        $set('T12Apellido2', $company ? '' : $last[intdiv($n, 400) % 20]);
        $set('T12Direccion', $get('T12Direccion') === '' ? '' : 'CALLE ' . ($n % 90 + 1) . ' # ' . ($n % 50 + 1) . '-' . ($n % 99 + 1));
        $set('T12EMail', $get('T12EMail') === '' ? '' : 'tercero' . ($n % 1000000) . '@example.com');
        foreach (['T12Telefono', 'T12Telefono2', 'T12Celular1', 'T12Celular2'] as $c) {
            $set($c, $get($c) === '' ? '' : '300' . str_pad((string) ($n % 10000000), 7, '0', STR_PAD_LEFT));
        }
        foreach (['T12Dv', 'T12LibretaMil', 'T12MatriProf', 'T12WebSite', 'T12Observacion', 'T12CodAlterno',
                  'T12NombreDe', 'T12FechaNace'] as $c) {
            $set($c, '');
        }
    } elseif ($table === 'T10EMPRESA') {
        $set('T10Nombre', $client_name);
        foreach (['T10Direccion', 'T10Observacion', 'T10WebSite', 'T10NomRepresentante', 'T10NomContador',
                  'T10NomRevisor', 'T10NomTesorero'] as $c) {
            $set($c, '');
        }
        foreach (['T10IdeRepresentante', 'T10IdeContador', 'T10IdeRevisor', 'T10IdeTesorero'] as $c) {
            $set($c, $get($c) === '' ? '' : anon_id($get($c)));
        }
        foreach (SECRETS as $c) {
            $set($c, '');
        }
    } elseif (in_array($table, ['T100CUENTA', 'T100CUENTANIIF'], true)) {
        // Account names of a third party carry its name
        $tercero = $get('T100Nit');
        if ($tercero !== '') {
            $set('T100Nombre', 'TERCERO ' . anon_id($tercero));
            $set('T100NombreNIIF', 'TERCERO ' . anon_id($tercero));
        }
    } elseif (in_array($table, ['T625VENDEDOR', 'T665COBRADOR', 'T656CONDUCTOR'], true)) {
        $col = preg_replace('/^(T\d+).*$/', '$1', $table) . 'Nombre';
        $set($col, 'PERSONA ' . substr((string) anon_num($get($col)), 0, 4));
    } elseif ($table === 'T698PAGO') {
        foreach (['T698Nombre', 'T698Nombre1', 'T698Apellido', 'T698Apellido1'] as $c) {
            $set($c, '');
        }
    }

    // Generic rules
    foreach ($cols as $i => $c) {
        // Ids map from the raw value: ids that differ only by spaces stay different
        $v = $row[$i];
        if (trim($v) === '') {
            continue;
        }
        if (preg_match(BLANK_RE, $c)) {
            $row[$i] = '';
        } elseif (preg_match(USER_RE, $c)) {
            $row[$i] = 'USR' . substr((string) anon_num($v), 0, 3);
        } elseif (preg_match(ID_RE, $c) && !preg_match(NOT_ID_RE, $c) && ($lens[$c] ?? 0) >= 10) {
            $row[$i] = anon_id($v);
        }
    }
    return $row;
}

// ----------------------------------------------------------------------------
// Arguments
// ----------------------------------------------------------------------------

$o = getopt('', ['client:', 'name:', 'mdb:', 'empresa:', 'anonymize', 'replace', 'help']);
if ($o === false || isset($o['help']) || !isset($o['client'], $o['name'], $o['mdb'])) {
    echo USAGE;
    exit(isset($o['help']) ? 0 : 1);
}
$slug = (string) $o['client'];
$name = trim((string) $o['name']);
$mdb = (string) $o['mdb'];
$empresa = (string) ($o['empresa'] ?? '1');
$anon = isset($o['anonymize']);

if (!preg_match(SORI_SLUG_RE, $slug)) {
    stop('invalid client code; use lowercase letters and digits');
}
if (!preg_match('/^.{1,100}$/us', $name)) {
    stop('invalid client name');
}
need_command('mdb-tables');
need_command('mdb-export');
if (!is_file($mdb) || !is_readable($mdb)) {
    stop('database file not readable');
}
if (!preg_match('/^[0-9]{1,5}$/', $empresa)) {
    stop('invalid company code');
}
$mdb_tables = run_lines(['mdb-tables', '-1', $mdb]);

// ----------------------------------------------------------------------------
// Client database
// ----------------------------------------------------------------------------

$dbname = 'sori_' . $slug;
$ctl = env()['DB_NAME'] ?? 'sori';
$root = admin_pdo(null);

$exists = (bool) $root->query("SHOW DATABASES LIKE '" . $dbname . "'")->fetch();
if ($exists && !isset($o['replace'])) {
    stop("database $dbname already exists; use --replace to delete it first");
}
if ($exists) {
    $root->exec("DROP DATABASE `$dbname`");
    out("Deleted old database $dbname");
}
$root->exec("CREATE DATABASE `$dbname` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");

$pdo = admin_pdo($dbname);
$sql = file_get_contents(__DIR__ . '/../db/schema.sql');
foreach (preg_split('/;\s*\n/', $sql) as $stmt) {
    $stmt = trim((string) preg_replace('/^--.*$/m', '', $stmt));
    if ($stmt !== '') {
        $pdo->exec($stmt);
    }
}
out('Schema created');

// ----------------------------------------------------------------------------
// Data
// ----------------------------------------------------------------------------

$pdo->exec('SET SESSION foreign_key_checks = 0, unique_checks = 0');
$target = $pdo->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN);
$total = 0;
$failed = [];
$incomplete = [];

foreach ($mdb_tables as $table) {
    if ($anon && (in_array($table, SKIP_ANON, true) || preg_match(SKIP_ANON_RE, $table))) {
        continue;
    }
    if (!in_array($table, $target, true)) {
        $incomplete[] = "table $table is not in the schema; its data was not loaded";
        continue;
    }
    $types = [];
    $lens = [];
    $st = $pdo->prepare('SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH AS len FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?');
    $st->execute([$dbname, $table]);
    foreach ($st->fetchAll() as $c) {
        $types[$c['COLUMN_NAME']] = $c['DATA_TYPE'];
        $lens[$c['COLUMN_NAME']] = (int) $c['len'];
    }

    $p = proc_open(['mdb-export', '-D', '%Y-%m-%d', '-T', '%Y-%m-%d %H:%M:%S', '-b', 'hex', $mdb, $table],
        [1 => ['pipe', 'w'], 2 => ['file', '/dev/null', 'w']], $pipes);
    $cols = fgetcsv($pipes[1], 0, ',', '"', '');
    if (!is_array($cols) || $cols === [null]) {
        proc_close($p);
        continue;
    }
    $cols = array_map('strval', $cols);
    $ncols = count($cols);
    // Another program version may have columns this schema lacks: skip them and say so
    $keep = array_keys(array_filter($cols, static fn($c) => isset($types[$c])));
    $dropped = $ncols - count($keep);
    if ($dropped > 0) {
        $incomplete[] = "table $table: $dropped column(s) not in the schema were not loaded";
    }
    $bad = 0;
    $all_cols = $cols;
    $cols = array_map(static fn($i) => $all_cols[$i], $keep);
    $text = array_map(static fn($c) => in_array($types[$c] ?? 'varchar', ['varchar', 'char', 'text', 'longtext', 'mediumtext', 'tinytext'], true), $cols);
    $emp = null;
    foreach ($cols as $i => $c) {
        if (preg_match('/CodEmpresa$/i', $c)) {
            $emp = $i;
            break;
        }
    }

    $colsql = '`' . implode('`,`', $cols) . '`';
    // Binary columns arrive as hexadecimal text
    $one = '(' . implode(',', array_map(static fn($c) => in_array($types[$c], BLOB_TYPES, true) ? 'UNHEX(?)' : '?', $cols)) . ')';
    $batch = [];
    $n = 0;
    $flush = static function () use (&$batch, $pdo, $table, $colsql, $one): void {
        if (!$batch) {
            return;
        }
        $args = [];
        foreach ($batch as $r) {
            array_push($args, ...$r);
        }
        $pdo->prepare("INSERT INTO `$table` ($colsql) VALUES " . implode(',', array_fill(0, count($batch), $one)))->execute($args);
        $batch = [];
    };

    try {
        $pdo->beginTransaction();
        while (($row = fgetcsv($pipes[1], 0, ',', '"', '')) !== false) {
            if (count($row) !== $ncols) {
                $bad++;
                continue;
            }
            if ($dropped > 0) {
                $row = array_map(static fn($i) => $row[$i], $keep);
            }
            if ($emp !== null && $row[$emp] !== $empresa) {
                continue;
            }
            if ($anon) {
                $row = anon_row($table, $cols, $row, $name, $lens);
            }
            foreach ($row as $i => $v) {
                if ($v === '' && !$text[$i]) {
                    $row[$i] = null;
                }
            }
            $batch[] = $row;
            $n++;
            if (count($batch) >= BATCH) {
                $flush();
            }
        }
        $flush();
        $pdo->commit();
    } catch (PDOException $ex) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        $failed[$table] = substr($ex->getMessage(), 0, 120);
        $n = 0;
    }
    fclose($pipes[1]);
    proc_close($p);
    if ($bad > 0) {
        $incomplete[] = "table $table: $bad malformed row(s) were not loaded";
    }
    if ($n > 0) {
        out(sprintf('%-28s %9d rows', $table, $n));
        $total += $n;
    }
}
out("Rows loaded: $total");
foreach ($incomplete as $note) {
    fwrite(STDERR, "WARNING: $note\n");
}
foreach ($failed as $t => $msg) {
    fwrite(STDERR, "ERROR: table $t failed: $msg\n");
}

// ----------------------------------------------------------------------------
// Client and first user
// ----------------------------------------------------------------------------

$ctlpdo = admin_pdo($ctl);
$ctlpdo->prepare('INSERT INTO sori_clientes (slug, nombre) VALUES (?, ?) ON DUPLICATE KEY UPDATE nombre = VALUES(nombre), activo = 1')
    ->execute([$slug, $name]);
$cid = (int) $ctlpdo->query("SELECT id FROM sori_clientes WHERE slug = " . $ctlpdo->quote($slug))->fetchColumn();

$st = $ctlpdo->prepare('SELECT COUNT(*) FROM sori_usuarios WHERE usuario = ?');
$st->execute([$slug]);
if ((int) $st->fetchColumn() === 0) {
    $alphabet = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    $pass = '';
    for ($i = 0; $i < 16; $i++) {
        $pass .= $alphabet[random_int(0, strlen($alphabet) - 1)];
    }
    $ctlpdo->prepare("INSERT INTO sori_usuarios (cliente_id, usuario, nombre, hash, rol) VALUES (?, ?, ?, ?, 'admin')")
        ->execute([$cid, $slug, 'Administrador ' . $name, password_hash($pass, PASSWORD_DEFAULT)]);
    out('');
    out("Client user: $slug");
    out("Password:    $pass");
    out('Shown only now. Store it in a safe place.');
} else {
    out("User $slug already exists; password unchanged");
}

// A non-zero status means some data was not loaded
exit($failed || $incomplete ? 1 : 0);
