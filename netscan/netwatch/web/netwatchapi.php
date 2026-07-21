<?php
/**
 * NetWatch - JSON API
 * File: netwatchapi.php
 */

session_start();
header('Content-Type: application/json');

$server_ip = '';
$net_cidr  = '';
$env_file  = '/etc/netwatch/netwatch.env';
if (file_exists($env_file)) {
    foreach (file($env_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (strpos($line, 'SERVER_IP=') === 0) {
            $server_ip = str_replace(array('"', "'"), '', trim(substr($line, strlen('SERVER_IP='))));
        } elseif (strpos($line, 'NET_CIDR=') === 0) {
            $net_cidr = str_replace(array('"', "'"), '', trim(substr($line, strlen('NET_CIDR='))));
        }
    }
}

$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
if ($origin && $server_ip) {
    $origin_host = parse_url($origin, PHP_URL_HOST);
    if ($origin_host === $server_ip || $origin_host === 'localhost') {
        header("Access-Control-Allow-Origin: $origin");
    }
}
header('Access-Control-Allow-Methods: GET, POST');
header('Access-Control-Allow-Headers: Content-Type');

// Restrict access to requests from the configured server IP, localhost, or the LAN subnet.
// CORS headers alone do not protect against direct curl/wget requests.
function ip_in_cidr($ip, $cidr) {
    if (empty($cidr) || strpos($cidr, '/') === false) return false;
    list($subnet, $bits) = explode('/', $cidr, 2);
    $bits        = max(0, min(32, (int)$bits));
    $ip_long     = ip2long($ip);
    $subnet_long = ip2long($subnet);
    if ($ip_long === false || $subnet_long === false) return false;
    $mask = $bits === 0 ? 0 : (~0 << (32 - $bits));
    return ($ip_long & $mask) === ($subnet_long & $mask);
}

$allowed_ips = ['127.0.0.1', '::1'];
if ($server_ip) {
    $allowed_ips[] = $server_ip;
}
$remote_addr = $_SERVER['REMOTE_ADDR'] ?? '';
$allowed = in_array($remote_addr, $allowed_ips, true)
        || ($net_cidr && ip_in_cidr($remote_addr, $net_cidr));
if (!$allowed) {
    http_response_code(403);
    echo json_encode(['success' => false, 'error' => 'Forbidden']);
    exit;
}

define('DB_FILE', '/var/www/netwatch/data/netwatch.db');

function get_db() {
    if (!file_exists(DB_FILE)) {
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => 'Database not found']);
        exit;
    }
    $pdo = new PDO('sqlite:' . DB_FILE);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->exec('PRAGMA busy_timeout=5000;');
    return $pdo;
}

// Validate a hostname or IPv4 address (port_scan_state.host / target IP)
function is_valid_host($host) {
    if ($host === '' || strlen($host) > 253) return false;
    if (filter_var($host, FILTER_VALIDATE_IP)) return true;
    return (bool) preg_match('/^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/', $host);
}

// ports_mode.conf is deliberately separate from netwatch.env (which holds
// the panel's access-control CIDR and lives read-only under /etc/netwatch,
// root:www-data — this process must never write there). ports_mode.conf
// stays www-data:www-data in the data dir, like any other file this
// web-facing process writes.
define('PORTS_MODE_FILE', '/var/www/netwatch/data/ports_mode.conf');

function read_ports_mode() {
    $mode = 'server';
    $target = '';
    if (file_exists(PORTS_MODE_FILE)) {
        foreach (file(PORTS_MODE_FILE, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
            if (strpos($line, 'PORTS_MODE=') === 0) {
                $mode = str_replace(array('"', "'"), '', trim(substr($line, strlen('PORTS_MODE='))));
            } elseif (strpos($line, 'PORTS_TARGET_IP=') === 0) {
                $target = str_replace(array('"', "'"), '', trim(substr($line, strlen('PORTS_TARGET_IP='))));
            }
        }
    }
    return ['mode' => $mode, 'target_ip' => $target];
}

// Atomic write: build the new content in a temp file in the same
// directory, then rename() into place. rename() is atomic on POSIX
// same-filesystem moves, so a concurrent reader (this file or the bash
// daemon) never observes a truncated/partial file — unlike the previous
// ftruncate+fwrite-in-place approach, this doesn't depend on the reader
// also taking a lock.
function write_ports_mode($mode, $target) {
    $dir = dirname(PORTS_MODE_FILE);
    $tmp = tempnam($dir, 'pmode-');
    if ($tmp === false) return false;

    $content = 'PORTS_MODE="' . $mode . "\"\n" . 'PORTS_TARGET_IP="' . $target . "\"\n";
    if (file_put_contents($tmp, $content) === false) {
        @unlink($tmp);
        return false;
    }
    @chmod($tmp, 0664);

    if (!rename($tmp, PORTS_MODE_FILE)) {
        @unlink($tmp);
        return false;
    }
    return true;
}

function csrf_token() {
    if (empty($_SESSION['csrf_token'])) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf_token'];
}

function csrf_valid($token) {
    return !empty($_SESSION['csrf_token']) && is_string($token) && hash_equals($_SESSION['csrf_token'], $token);
}

try {
    $action = $_GET['action'] ?? $_POST['action'] ?? '';
    $pdo = get_db();

    switch ($action) {

        case 'csrfToken':
            echo json_encode(['success' => true, 'data' => ['csrf_token' => csrf_token()]]);
            break;

        case 'listDevices':
            $stmt = $pdo->query('SELECT mac, ip, iface, vendor, hostname, status, first_seen, last_seen FROM devices ORDER BY ip');
            $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
            echo json_encode(['success' => true, 'data' => $rows, 'count' => count($rows)]);
            break;

        case 'deviceEvents':
            $limit = min(max((int)($_GET['limit'] ?? 100), 1), 1000);
            $stmt = $pdo->prepare('SELECT mac, ip, event_type, event_time FROM device_events ORDER BY event_time DESC, id DESC LIMIT :limit');
            $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
            $stmt->execute();
            $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
            echo json_encode(['success' => true, 'data' => $rows, 'count' => count($rows)]);
            break;

        case 'getPortsMode':
            $pm = read_ports_mode();
            $pm['server_ip'] = $server_ip;
            echo json_encode(['success' => true, 'data' => $pm]);
            break;

        case 'setPortsMode':
            if ($_SERVER['REQUEST_METHOD'] !== 'POST' || !csrf_valid($_POST['csrf_token'] ?? '')) {
                http_response_code(403);
                echo json_encode(['success' => false, 'error' => 'Invalid or missing CSRF token']);
                break;
            }
            $mode = trim((string)($_POST['mode'] ?? ''));
            if ($mode === 'server') {
                write_ports_mode('server', '');
                echo json_encode(['success' => true]);
            } elseif ($mode === 'target') {
                $target = trim((string)($_POST['target_ip'] ?? ''));
                if (!is_valid_host($target)) {
                    http_response_code(400);
                    echo json_encode(['success' => false, 'error' => 'Invalid target host']);
                    break;
                }
                write_ports_mode('target', $target);
                echo json_encode(['success' => true]);
            } else {
                http_response_code(400);
                echo json_encode(['success' => false, 'error' => 'Invalid mode']);
            }
            break;

        case 'listPorts':
            $pm = read_ports_mode();
            $host = $pm['mode'] === 'target' ? $pm['target_ip'] : ($server_ip ?: 'localhost');
            $stmt = $pdo->prepare('SELECT host, port, proto, service, status, last_checked, last_changed FROM port_scan_state WHERE source = :source AND host = :host ORDER BY port');
            $stmt->execute([':source' => $pm['mode'], ':host' => $host]);
            $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
            echo json_encode(['success' => true, 'data' => $rows, 'count' => count($rows), 'mode' => $pm['mode'], 'host' => $host]);
            break;

        case 'portEvents':
            $pm = read_ports_mode();
            $host = $pm['mode'] === 'target' ? $pm['target_ip'] : ($server_ip ?: 'localhost');
            $limit = min(max((int)($_GET['limit'] ?? 100), 1), 1000);
            $stmt = $pdo->prepare('SELECT host, port, event_type, event_time FROM port_events WHERE source = :source AND host = :host ORDER BY event_time DESC, id DESC LIMIT :limit');
            $stmt->bindValue(':source', $pm['mode'], PDO::PARAM_STR);
            $stmt->bindValue(':host', $host, PDO::PARAM_STR);
            $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
            $stmt->execute();
            $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
            echo json_encode(['success' => true, 'data' => $rows, 'count' => count($rows)]);
            break;

        default:
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'Invalid action']);
    }
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'error' => 'Internal server error']);
}
