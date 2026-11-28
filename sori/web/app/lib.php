<?php
// SORI core: configuration, database access, sessions and helpers
// FILE: app/lib.php
declare(strict_types=1);

require_once __DIR__ . '/i18n.php';

const SORI_ENV_DEFAULT = '/etc/sori/sori.env';
const SORI_SLUG_RE = '/^[a-z][a-z0-9]{1,29}$/';

// Stop the request with a plain message. Details never reach the browser.
function fail(int $code, string $msg): never
{
    http_response_code($code);
    header('Content-Type: text/plain; charset=utf-8');
    echo $msg;
    exit;
}

function e(?string $s): string
{
    return htmlspecialchars((string) $s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

// Numeric setting of sori.env; the default is used when the key is missing or not a positive number
function setting(string $key, int $default): int
{
    $v = env()[$key] ?? '';
    return ctype_digit($v) && (int) $v > 0 ? (int) $v : $default;
}

// Read the .env file. Any malformed line aborts.
function env(): array
{
    static $env = null;
    if ($env !== null) {
        return $env;
    }
    $path = getenv('SORI_ENV') ?: SORI_ENV_DEFAULT;
    $lines = @file($path, FILE_IGNORE_NEW_LINES);
    if ($lines === false) {
        error_log("sori: cannot read $path");
        fail(500, 'Configuration error');
    }
    $env = [];
    foreach ($lines as $line) {
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        if (!preg_match('/^([A-Z][A-Z0-9_]*)=(.*)$/', $line, $m)
            || $m[2] !== trim($m[2], " \t\"'")) {
            error_log("sori: malformed line in $path");
            fail(500, 'Configuration error');
        }
        $env[$m[1]] = $m[2];
    }
    return $env;
}

function connect(string $dbname): PDO
{
    $c = env();
    $dsn = 'mysql:host=' . ($c['DB_HOST'] ?? '127.0.0.1') . ';dbname=' . $dbname . ';charset=utf8mb4';
    if (!empty($c['DB_SOCKET'])) {
        $dsn = 'mysql:unix_socket=' . $c['DB_SOCKET'] . ';dbname=' . $dbname . ';charset=utf8mb4';
    }
    try {
        return new PDO($dsn, $c['DB_USER'] ?? '', $c['DB_PASS'] ?? '', [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);
    } catch (PDOException $ex) {
        error_log('sori: database connection failed: ' . $ex->getMessage());
        fail(500, 'Database error');
    }
}

// Control database: clients and users
function db(): PDO
{
    static $pdo = null;
    return $pdo ??= connect(env()['DB_NAME'] ?? 'sori');
}

// Database of the client in the session. The name comes from the session,
// which only login fills, and must match the slug pattern.
function tenant(): PDO
{
    static $pdo = null;
    $slug = $_SESSION['user']['slug'] ?? '';
    if (!preg_match(SORI_SLUG_RE, $slug)) {
        fail(403, 'No client');
    }
    return $pdo ??= connect('sori_' . $slug);
}

function client_ip(): string
{
    $ip = $_SERVER['REMOTE_ADDR'] ?? '';
    // Only the local tunnel connects from loopback, so its header is trusted.
    if (in_array($ip, ['127.0.0.1', '::1'], true)
        && !empty($_SERVER['HTTP_CF_CONNECTING_IP'])
        && filter_var($_SERVER['HTTP_CF_CONNECTING_IP'], FILTER_VALIDATE_IP)) {
        return $_SERVER['HTTP_CF_CONNECTING_IP'];
    }
    return $ip;
}

function start_session(): void
{
    $https = !empty($_SERVER['HTTPS'])
        || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https';
    session_name('sori');
    session_set_cookie_params([
        'lifetime' => 0,
        'path' => '/',
        'secure' => $https,
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
    session_start();
    if (isset($_SESSION['last']) && time() - $_SESSION['last'] > setting('SESSION_TIMEOUT', 7200)) {
        $_SESSION = [];
    }
    $_SESSION['last'] = time();
}

function csrf(): string
{
    return $_SESSION['csrf'] ??= bin2hex(random_bytes(16));
}

function csrf_ok(): bool
{
    return hash_equals(csrf(), (string) ($_POST['csrf'] ?? ''));
}

function user(): ?array
{
    return $_SESSION['user'] ?? null;
}

// Returns an error message, or null when login succeeded.
function login(string $username, string $password): ?string
{
    $ip = client_ip();
    $minutes = setting('LOGIN_WINDOW_MINUTES', 10);
    $st = db()->prepare('SELECT COUNT(*) FROM sori_attempts WHERE ip = ? AND attempted_at > NOW() - INTERVAL ' . $minutes . ' MINUTE');
    $st->execute([$ip]);
    if ((int) $st->fetchColumn() >= setting('LOGIN_MAX_ATTEMPTS', 5)) {
        return str_replace('{n}', (string) $minutes, t('Demasiados intentos. Espere {n} minutos.'));
    }
    $st = db()->prepare(
        'SELECT u.id, u.username, u.name, u.hash, u.role, u.client_id, c.slug, c.name AS client_name, c.active AS client_active
         FROM sori_users u LEFT JOIN sori_clients c ON c.id = u.client_id
         WHERE u.username = ? AND u.active = 1'
    );
    $st->execute([$username]);
    $row = $st->fetch();
    // Verify against a dummy hash when the user does not exist, to keep timing equal
    $hash = $row['hash'] ?? '$2y$10$mmQNATPIXh/msWUnvSlKBu90zEJwbFJDiWk02rSWpXMj.P2bckjca';
    $ok = password_verify($password, $hash) && $row;
    if ($ok && $row['client_id'] !== null && !(int) $row['client_active']) {
        $ok = false;
    }
    if (!$ok) {
        db()->prepare('INSERT INTO sori_attempts (ip) VALUES (?)')->execute([$ip]);
        db()->exec('DELETE FROM sori_attempts WHERE attempted_at < NOW() - INTERVAL ' . setting('LOGIN_ATTEMPTS_KEEP_DAYS', 1) . ' DAY');
        return t('Usuario o contraseña incorrectos.');
    }
    session_regenerate_id(true);
    $_SESSION['user'] = [
        'id' => (int) $row['id'],
        'username' => $row['username'],
        'name' => $row['name'],
        'role' => $row['role'],
        'slug' => $row['slug'],
        'client_name' => $row['client_name'],
    ];
    return null;
}

function redirect(string $to): never
{
    header('Location: ' . $to);
    exit;
}

function require_login(): array
{
    $u = user();
    if ($u === null) {
        redirect('/login');
    }
    return $u;
}

// SQL expression with the full name of a third party, from a T12TERCERO alias
function party_name(string $a): string
{
    return "TRIM(CONCAT_WS(' ', NULLIF(TRIM($a.T12RazonSocial), ''), NULLIF(TRIM($a.T12Nombre), ''), "
         . "NULLIF(TRIM($a.T12Nombre2), ''), NULLIF(TRIM($a.T12Apellido), ''), NULLIF(TRIM($a.T12Apellido2), '')))";
}

// The legacy database stores dates as text dd/mm/yyyy. This makes one sortable.
function date_sql(string $col): string
{
    return "STR_TO_DATE($col, '%d/%m/%Y')";
}

// Format a value for display by its type: text, money or number
function fmt(?string $v, string $type = 'text'): string
{
    $v = (string) $v;
    if ($type === 'money' && is_numeric($v)) {
        $n = (float) $v;
        return num($n, $n == round($n) ? 0 : 2);
    }
    return $v;
}

// Number with the separators of the interface language: 1.234,50 in Spanish, 1,234.50 in English
function num(float|int $n, int $decimals = 0): string
{
    return lang() === 'es' ? number_format($n, $decimals, ',', '.') : number_format($n, $decimals, '.', ',');
}

// Readable label from a legacy column name: T604NumFactura -> Num Factura
function label(string $col): string
{
    $col = preg_replace('/^T\d+/', '', $col);
    return trim((string) preg_replace('/(?<=[a-z])(?=[A-Z])/', ' ', $col));
}

// Render a view inside the layout
function view(string $name, array $vars = []): void
{
    extract($vars, EXTR_SKIP);
    ob_start();
    require __DIR__ . '/views/' . $name . '.php';
    $content = ob_get_clean();
    require __DIR__ . '/views/layout.php';
}
