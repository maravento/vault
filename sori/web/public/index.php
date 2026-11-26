<?php
// SORI front controller: every request that is not a static file lands here
// FILE: public/index.php
declare(strict_types=1);

$path = rtrim(parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/', '/') ?: '/';

// PHP built-in server (tests): let it serve static files itself
if (PHP_SAPI === 'cli-server' && $path !== '/' && is_file(__DIR__ . $path)
    && !str_ends_with($path, '.php')) {
    return false;
}

require __DIR__ . '/../app/lib.php';

header('X-Content-Type-Options: nosniff');
header('Vary: Accept-Language');
header('X-Frame-Options: DENY');
header('Referrer-Policy: same-origin');
header("Content-Security-Policy: default-src 'self'; style-src 'self' https://cdnjs.cloudflare.com; font-src https://cdnjs.cloudflare.com; img-src 'self' data:; frame-ancestors 'none'; form-action 'self'");

start_session();
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$modules = require __DIR__ . '/../app/modules.php';

// Login and logout
if ($path === '/login') {
    $error = null;
    if ($method === 'POST') {
        if (!csrf_ok()) {
            $error = t('Sesión caducada. Intente de nuevo.');
        } else {
            $error = login(trim((string) ($_POST['usuario'] ?? '')), (string) ($_POST['clave'] ?? ''));
            if ($error === null) {
                redirect('/');
            }
        }
    }
    view('login', ['error' => $error]);
    exit;
}
if ($path === '/logout' && $method === 'POST') {
    if (csrf_ok()) {
        $_SESSION = [];
        session_destroy();
    }
    redirect('/login');
}

$u = require_login();
$is_super = $u['slug'] === null;

// Platform administrator: manages clients, has no client data
if ($path === '/admin') {
    if (!$is_super) {
        fail(403, 'Forbidden');
    }
    $clientes = db()->query(
        'SELECT c.slug, c.nombre, c.activo, c.creado,
                (SELECT COUNT(*) FROM sori_usuarios u WHERE u.cliente_id = c.id) AS usuarios
         FROM sori_clientes c ORDER BY c.nombre'
    )->fetchAll();
    view('admin', ['u' => $u, 'clientes' => $clientes]);
    exit;
}
if ($is_super) {
    redirect('/admin');
}

if ($path === '/') {
    $count = static function (string $tabla): ?int {
        try {
            return (int) tenant()->query('SELECT COUNT(*) FROM `' . $tabla . '`')->fetchColumn();
        } catch (PDOException) {
            return null;
        }
    };
    view('home', ['u' => $u, 'modules' => $modules, 'count' => $count]);
    exit;
}

if (preg_match('#^/modulo/([a-z]+)(/ver)?$#', $path, $m)) {
    $vistas = require __DIR__ . '/../app/vistas.php';
    foreach ($modules as $mod) {
        if ($mod['id'] !== $m[1]) {
            continue;
        }
        $vista = $vistas[$mod['id']] ?? null;
        if ($vista === null) {
            view('pendiente', ['u' => $u, 'mod' => $mod]);
        } elseif (isset($m[2])) {
            // The detail needs the key of the record, so a module without one has none
            $vista['pk'] ?? fail(404, 'Not found');
            view('detalle', ['u' => $u, 'mod' => $mod, 'vista' => $vista]);
        } else {
            view('listado', ['u' => $u, 'mod' => $mod, 'vista' => $vista]);
        }
        exit;
    }
}

fail(404, 'Not found');
