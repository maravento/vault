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
require __DIR__ . '/../app/write.php';
require __DIR__ . '/../app/invoice.php';
require __DIR__ . '/../app/receipt.php';
require __DIR__ . '/../app/sales_return.php';
require __DIR__ . '/../app/purchase.php';
require __DIR__ . '/../app/purchase_return.php';
require __DIR__ . '/../app/third_party.php';
require __DIR__ . '/../app/product.php';
require __DIR__ . '/../app/supplier_payment.php';

// Dates follow the time zone the installer detected on the server
if (!@date_default_timezone_set(env()['TIMEZONE'] ?? 'UTC')) {
    error_log('sori: invalid TIMEZONE in the configuration');
    fail(500, 'Configuration error');
}

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
            $error = login(trim((string) ($_POST['username'] ?? '')), (string) ($_POST['password'] ?? ''));
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
    $clients = db()->query(
        'SELECT c.slug, c.name, c.active, c.created,
                (SELECT COUNT(*) FROM sori_users u WHERE u.client_id = c.id) AS users
         FROM sori_clients c ORDER BY c.name'
    )->fetchAll();
    view('admin', ['u' => $u, 'clients' => $clients]);
    exit;
}
if ($is_super) {
    redirect('/admin');
}

if ($path === '/') {
    $count = static function (string $table): ?int {
        try {
            return (int) tenant()->query('SELECT COUNT(*) FROM `' . $table . '`')->fetchColumn();
        } catch (PDOException) {
            return null;
        }
    };
    view('home', ['u' => $u, 'modules' => $modules, 'count' => $count]);
    exit;
}

// Lookups used by the quote form. Only an editor writes, so only an editor searches.
if ($path === '/api/search') {
    can_write() || fail(403, 'Forbidden');
    $q = trim((string) ($_GET['q'] ?? ''));
    $type = (string) ($_GET['type'] ?? '');
    $res = [];
    if ($q !== '' && text_length($q) <= 60) {
        $res = match ($type) {
            'party' => search_parties(tenant(), $q),
            'item' => search_items(tenant(), $q),
            default => [],
        };
    }
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($res, JSON_UNESCAPED_UNICODE);
    exit;
}

// New quote or new invoice. Only an editor writes.
$new_routes = [
    '/module/quotes/new' => [
        'module' => 'quotes', 'save' => 'quote_save', 'view' => '/module/quotes/view',
        'table' => ['T638COTIZACION', 'T638Prefijo'],
        'doc' => ['route' => '/module/quotes/new', 'title' => 'Nueva cotización', 'items' => 'Ítems de la cotización', 'button' => 'Guardar cotización'],
    ],
    '/module/invoices/new' => [
        'module' => 'invoices', 'save' => 'invoice_save', 'view' => '/module/invoices/view',
        'table' => ['T604FACTURA', 'T604Prefijo'],
        'doc' => ['route' => '/module/invoices/new', 'title' => 'Nueva factura', 'items' => 'Ítems de la factura', 'button' => 'Guardar factura'],
    ],
];
if (isset($new_routes[$path])) {
    can_write() || fail(403, 'Forbidden');
    $new = $new_routes[$path];
    $mod = current(array_filter($modules, static fn($x) => $x['id'] === $new['module']));
    $old = null;
    $error = null;
    if ($method === 'POST') {
        if (!csrf_ok()) {
            $error = t('Sesión caducada. Intente de nuevo.');
            $old = $_POST;
        } else {
            $r = $new['save'](tenant(), $u['username'], $_POST);
            if (isset($r['keys'])) {
                if (!empty($r['notice'])) {
                    $_SESSION['notice'] = $r['notice'];
                }
                redirect($new['view'] . '?' . http_build_query($r['keys']));
            }
            $error = $r['error'];
            $old = $_POST;
        }
    }
    view('document_new', [
        'u' => $u, 'mod' => $mod, 'options' => document_options(tenant(), $new['table'][0], $new['table'][1]),
        'old' => $old, 'error' => $error, 'doc' => $new['doc'],
    ]);
    exit;
}

// New payment received on a credit invoice
if ($path === '/module/receivables/new') {
    can_write() || fail(403, 'Forbidden');
    $mod = current(array_filter($modules, static fn($x) => $x['id'] === 'receivables'));
    $old = null;
    $error = null;
    $q = ['p' => field($_GET['p'] ?? $_POST['prefix'] ?? ''), 'n' => field($_GET['n'] ?? $_POST['number'] ?? '')];
    if ($method === 'POST') {
        if (!csrf_ok()) {
            $error = t('Sesión caducada. Intente de nuevo.');
            $old = $_POST;
        } else {
            $r = receipt_save(tenant(), $u['username'], $_POST);
            if (isset($r['keys'])) {
                $_SESSION['notice'] = $r['notice'] ?? t('El abono quedó registrado.');
                redirect('/module/receivables/view?' . http_build_query($r['keys']));
            }
            $error = $r['error'];
            $old = $_POST;
        }
    }
    $invoice = $q['p'] !== '' && $q['n'] !== '' ? invoice_for_receipt(tenant(), company_code(tenant()), $q['p'], $q['n']) : null;
    view('receipt_new', ['u' => $u, 'mod' => $mod, 'options' => receipt_options(tenant()), 'invoice' => $invoice, 'q' => $q, 'old' => $old, 'error' => $error]);
    exit;
}

// New and edited third party. Only an editor writes.
if ($path === '/module/parties/new' || $path === '/module/parties/edit') {
    can_write() || fail(403, 'Forbidden');
    $mod = current(array_filter($modules, static fn($x) => $x['id'] === 'parties'));
    $edit = $path === '/module/parties/edit';
    $company_id = company_code(tenant());
    $old = null;
    $error = null;
    if ($edit) {
        $tax_id = field($_GET['k1'] ?? $_POST['tax_id'] ?? '');
        $current_row = party_read(tenant(), $company_id, $tax_id);
        $current_row !== null || fail(404, 'Not found');
        $old = $current_row;
    }
    if ($method === 'POST') {
        if (!csrf_ok()) {
            $error = t('Sesión caducada. Intente de nuevo.');
            $old = $_POST;
        } else {
            $r = party_save(tenant(), $u['username'], $_POST, !$edit);
            if (isset($r['keys'])) {
                $_SESSION['notice'] = t('El tercero quedó guardado.');
                redirect('/module/parties/view?' . http_build_query($r['keys']));
            }
            $error = $r['error'];
            $old = $_POST + ($edit ? ['check_digit' => $current_row['check_digit']] : []);
        }
    }
    view('third_party_form', ['u' => $u, 'mod' => $mod, 'options' => party_options(tenant()), 'old' => $old, 'error' => $error, 'edit' => $edit]);
    exit;
}

// New and edited product or service. Only an editor writes.
if ($path === '/module/products/new' || $path === '/module/products/edit') {
    can_write() || fail(403, 'Forbidden');
    $mod = current(array_filter($modules, static fn($x) => $x['id'] === 'products'));
    $edit = $path === '/module/products/edit';
    $old = null;
    $error = null;
    if ($edit) {
        $current_row = product_read(tenant(), company_code(tenant()), field($_GET['k1'] ?? $_POST['code'] ?? ''));
        $current_row !== null || fail(404, 'Not found');
        $old = $current_row;
    }
    if ($method === 'POST') {
        if (!csrf_ok()) {
            $error = t('Sesión caducada. Intente de nuevo.');
            $old = $_POST;
        } else {
            $r = product_save(tenant(), $u['username'], $_POST, !$edit);
            if (isset($r['keys'])) {
                $_SESSION['notice'] = t('El producto quedó guardado.');
                redirect('/module/products/view?' . http_build_query($r['keys']));
            }
            $error = $r['error'];
            $old = $_POST;
        }
    }
    view('product_form', ['u' => $u, 'mod' => $mod, 'options' => product_options(tenant()), 'old' => $old, 'error' => $error, 'edit' => $edit]);
    exit;
}

// New payment to a supplier on a credit purchase
if ($path === '/module/payables/new') {
    can_write() || fail(403, 'Forbidden');
    $mod = current(array_filter($modules, static fn($x) => $x['id'] === 'payables'));
    $old = null;
    $error = null;
    $q = ['y' => field($_GET['y'] ?? $_POST['year'] ?? ''), 't' => field($_GET['t'] ?? $_POST['type'] ?? ''), 'n' => field($_GET['n'] ?? $_POST['number'] ?? '')];
    if ($method === 'POST') {
        if (!csrf_ok()) {
            $error = t('Sesión caducada. Intente de nuevo.');
            $old = $_POST;
        } else {
            $r = supplier_payment_save(tenant(), $u['username'], $_POST);
            if (isset($r['keys'])) {
                $_SESSION['notice'] = $r['notice'] ?? t('El pago quedó registrado.');
                redirect('/module/payables/view?' . http_build_query($r['keys']));
            }
            $error = $r['error'];
            $old = $_POST;
        }
    }
    $purchase = $q['t'] !== '' && $q['n'] !== '' ? purchase_document(tenant(), company_code(tenant()), $q['t'], $q['n'], $q['y']) : null;
    $options = purchase_options(tenant()) + ['accounts' => tenant()->query("SELECT T627Codigo AS code, T627Nombre AS name FROM T627BANCO WHERE T627Activo = 'S' ORDER BY T627Nombre")->fetchAll()];
    view('supplier_payment_new', ['u' => $u, 'mod' => $mod, 'options' => $options, 'purchase' => $purchase, 's' => $purchase ? purchase_balance(tenant(), company_code(tenant()), $purchase) : null, 'q' => $q, 'old' => $old, 'error' => $error]);
    exit;
}

// New purchase from a supplier
if ($path === '/module/purchases/new') {
    can_write() || fail(403, 'Forbidden');
    $mod = current(array_filter($modules, static fn($x) => $x['id'] === 'purchases'));
    $old = null;
    $error = null;
    if ($method === 'POST') {
        if (!csrf_ok()) {
            $error = t('Sesión caducada. Intente de nuevo.');
            $old = $_POST;
        } else {
            $r = purchase_save(tenant(), $u['username'], $_POST);
            if (isset($r['keys'])) {
                redirect('/module/purchases/view?' . http_build_query($r['keys']));
            }
            $error = $r['error'];
            $old = $_POST;
        }
    }
    view('purchase_new', ['u' => $u, 'mod' => $mod, 'options' => purchase_options(tenant()), 'old' => $old, 'error' => $error]);
    exit;
}

// New return of goods to a supplier
if ($path === '/module/purchases/return') {
    can_write() || fail(403, 'Forbidden');
    $mod = current(array_filter($modules, static fn($x) => $x['id'] === 'purchases'));
    $old = null;
    $error = null;
    $q = ['t' => field($_GET['t'] ?? $_POST['type'] ?? ''), 'n' => field($_GET['n'] ?? $_POST['number'] ?? '')];
    if ($method === 'POST') {
        if (!csrf_ok()) {
            $error = t('Sesión caducada. Intente de nuevo.');
            $old = $_POST;
        } else {
            $r = purchase_return_save(tenant(), $u['username'], $_POST);
            if (isset($r['keys'])) {
                $_SESSION['notice'] = $r['notice'] ?? t('La devolución quedó registrada.');
                redirect('/module/purchases/view?' . http_build_query($r['keys']));
            }
            $error = $r['error'];
            $old = $_POST;
        }
    }
    $purchase = $q['t'] !== '' && $q['n'] !== '' ? purchase_document(tenant(), company_code(tenant()), $q['t'], $q['n']) : null;
    $lines = $purchase ? purchase_return_lines(tenant(), company_code(tenant()), $purchase) : [];
    view('purchase_return_new', ['u' => $u, 'mod' => $mod, 'options' => purchase_options(tenant()), 'purchase' => $purchase, 'lines' => $lines, 'q' => $q, 'old' => $old, 'error' => $error]);
    exit;
}

// New customer return on a sales invoice
if ($path === '/module/invoices/return') {
    can_write() || fail(403, 'Forbidden');
    $mod = current(array_filter($modules, static fn($x) => $x['id'] === 'invoices'));
    $old = null;
    $error = null;
    $q = ['p' => field($_GET['p'] ?? $_POST['prefix'] ?? ''), 'n' => field($_GET['n'] ?? $_POST['number'] ?? '')];
    if ($method === 'POST') {
        if (!csrf_ok()) {
            $error = t('Sesión caducada. Intente de nuevo.');
            $old = $_POST;
        } else {
            $r = sales_return_save(tenant(), $u['username'], $_POST);
            if (isset($r['keys'])) {
                $_SESSION['notice'] = $r['notice'] ?? t('La devolución quedó registrada.');
                redirect('/module/invoices/view?' . http_build_query(['k0' => company_code(tenant()), 'k1' => $q['p'], 'k2' => $q['n']]));
            }
            $error = $r['error'];
            $old = $_POST;
        }
    }
    $invoice = $q['p'] !== '' && $q['n'] !== '' ? invoice_for_receipt(tenant(), company_code(tenant()), $q['p'], $q['n']) : null;
    $lines = $invoice ? sales_return_lines(tenant(), company_code(tenant()), $q['p'], $q['n']) : [];
    view('sales_return_new', [
        'u' => $u, 'mod' => $mod, 'options' => document_options(tenant(), 'T604FACTURA', 'T604Prefijo'),
        'invoice' => $invoice, 'lines' => $lines, 'q' => $q, 'old' => $old, 'error' => $error,
    ]);
    exit;
}

// Cancel an invoice. The answer is always a page with a notice: the invoice, or the list when the token failed.
if ($path === '/module/invoices/cancel' && $method === 'POST') {
    can_write() || fail(403, 'Forbidden');
    if (!csrf_ok()) {
        $_SESSION['notice'] = t('Sesión caducada. Intente de nuevo.');
        redirect('/module/invoices');
    }
    $r = invoice_cancel(tenant(), $u['username'], $_POST);
    $_SESSION['notice'] = $r['notice'] ?? $r['error'];
    if (isset($r['keys'])) {
        redirect('/module/invoices/view?' . http_build_query($r['keys']));
    }
    // A failed attempt returns to the invoice when it exists, and to the list when it does not
    $keys = ['k0' => company_code(tenant()), 'k1' => field($_POST['k1'] ?? ''), 'k2' => field($_POST['k2'] ?? '')];
    $st = tenant()->prepare('SELECT COUNT(*) FROM T604FACTURA WHERE T604CodEmpresa = ? AND T604Prefijo = ? AND T604NumFactura = ?');
    $st->execute([$keys['k0'], $keys['k1'], $keys['k2']]);
    redirect((int) $st->fetchColumn() ? '/module/invoices/view?' . http_build_query($keys) : '/module/invoices');
}

if (preg_match('#^/module/([a-z_]+)(/view)?$#', $path, $m)) {
    $screens = require __DIR__ . '/../app/screens.php';
    foreach ($modules as $mod) {
        if ($mod['id'] !== $m[1]) {
            continue;
        }
        $screen = $screens[$mod['id']] ?? null;
        if ($screen === null) {
            view('pending', ['u' => $u, 'mod' => $mod]);
        } elseif (isset($m[2])) {
            // The detail needs the key of the record, so a module without one has none
            $screen['pk'] ?? fail(404, 'Not found');
            view('detail', ['u' => $u, 'mod' => $mod, 'screen' => $screen]);
        } else {
            view('list', ['u' => $u, 'mod' => $mod, 'screen' => $screen]);
        }
        exit;
    }
}

fail(404, 'Not found');
