<?php
/**
 * SquidAI Worker — Backend PHP
 * Read local sources from the proxy and return JSON to the frontend
 * Supports any LLM via configurable API key
 *
 * Configurable routes:
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: http://localhost:18080');
header('Cache-Control: no-store');

// Use the time zone configured in the system
$sysTz = trim(shell_exec('cat /etc/timezone 2>/dev/null || timedatectl show --property=Timezone --value 2>/dev/null') ?? '');
if ($sysTz && @timezone_open($sysTz)) {
    date_default_timezone_set($sysTz);
}

// ── LANGUAGE ─────────────────────────────────────────────────────────
$lang = $_GET['lang'] ?? $_POST['lang'] ?? 'en';
$lang = ($lang === 'es') ? 'es' : 'en';

$i18n = [
    'en' => [
        'dataset_not_found' => 'dataset.md not found',
        'api_key_missing' => 'API key not configured in .env',
        'connection_error' => 'Connection error: ',
        'realname_not_found' => 'realname.cfg not found',
        'lightsquid_dir_missing' => 'LightSquid directory not found',
        'no_report' => 'No LightSquid report for this date/IP',
        'blockdomains_not_found' => 'blockdomains.txt not found',
        'cannot_read_log' => 'Cannot read access.log',
        'unknown' => 'Unknown',
    ],
    'es' => [
        'dataset_not_found' => 'dataset.md no encontrado',
        'api_key_missing' => 'API key no configurada en .env',
        'connection_error' => 'Error conectando: ',
        'realname_not_found' => 'realname.cfg no encontrado',
        'lightsquid_dir_missing' => 'Directorio LightSquid no encontrado',
        'no_report' => 'Sin reporte LightSquid para esta fecha/IP',
        'blockdomains_not_found' => 'blockdomains.txt no encontrado',
        'cannot_read_log' => 'No se pudo leer access.log',
        'unknown' => 'Desconocido',
    ]
];

function msg($key, $fallback = null) {
    global $i18n, $lang;
    return $i18n[$lang][$key] ?? $i18n['en'][$key] ?? $fallback ?? $key;
}
// ───────────────────────────────────────────────────────────────────


// ── ROUTE CONFIGURATION ──────────────────────────────────────────
define('REALNAME_CFG',    '/var/www/proxymon/lightsquid/realname.cfg');
define('SKIPUSERS_CFG',   '/var/www/proxymon/lightsquid/skipuser.cfg');
define('LIGHTSQUID_DIR',  '/var/www/proxymon/lightsquid/report');
define('BLOCKDOMAINS',    '/etc/acl/acl_squid/blockdomains.txt');
define('BLOCKTLDS',       '/etc/acl/acl_squid/blocktlds.txt');
define('BLOCKPATTERNS',   '/etc/acl/acl_squid/blockpatterns.txt');
define('SQUID_LOG_DIR',   '/var/log/squid');
define('SQUID_LOG_FILE',  '/var/log/squid/access.log');
define('MAX_LOG_LINES_SCAN',    2000000);
define('MIN_LOG_LINES_REQUEST', 50);
define('MAX_LOG_LINES_REQUEST', 5000);
// ───────────────────────────────────────────────────────────────────

// ── API KEY FROM .env ─────────────────────────────────────────────
function loadEnv(): void {
    $envFile = '/etc/proxymon/.env';
    if (!file_exists($envFile)) return;
    foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') continue;
        if (str_contains($line, '=')) {
            [$key, $val] = explode('=', $line, 2);
            $_ENV[trim($key)] = trim($val);
        }
    }
}
loadEnv();
// ──────────────────────────────────────────────────────────────────

$action = $_GET['action'] ?? 'ping';


try {
    switch ($action) {
        case 'ping':
            echo json_encode(['status' => 'ok', 'version' => '1.0', 'time' => date('c')]);
            break;

        case 'get_dataset':
            $datasetPath = __DIR__ . '/dataset.md';
            if (!file_exists($datasetPath)) {
                http_response_code(404);
                echo json_encode(['error' => msg('dataset_not_found')]);
            } else {
                echo json_encode(['content' => file_get_contents($datasetPath)]);
            }
            break;

        case 'get_users':
            echo json_encode(getUsers());
            break;

        case 'get_available_dates':
            $ip = $_GET['ip'] ?? '';
            echo json_encode(getAvailableDates($ip));
            break;

        case 'get_user_report':
            $ip   = basename(trim($_GET['ip'] ?? ''));
            if (!preg_match('/^\d{1,3}(\.\d{1,3}){3}$/', $ip)) {
                echo json_encode(['error' => 'Invalid IP']); break;
            }
            $date = $_GET['date'] ?? 'today';
            echo json_encode(getUserReport($ip, $date));
            break;

        case 'check_blacklist':
            $ip   = basename(trim($_GET['ip'] ?? ''));
            if (!preg_match('/^\d{1,3}(\.\d{1,3}){3}$/', $ip)) {
                echo json_encode(['error' => 'Invalid IP']); break;
            }
            $date = $_GET['date'] ?? 'today';
            echo json_encode(checkBlacklist($ip, $date));
            break;

        case 'get_blocked_domains':
            echo json_encode(getBlockedByType('domains'));
            break;

        case 'get_blocked_patterns':
            echo json_encode(getBlockedByType('patterns'));
            break;

        case 'get_blocked_tlds':
            echo json_encode(getBlockedByType('tlds'));
            break;

        case 'get_security_incidents': // compatibilidad hacia atrás
            echo json_encode(getBlockedByType('domains'));
            break;

        case 'get_network_summary':
            $date = $_GET['date'] ?? 'today';
            echo json_encode(getNetworkSummary($date));
            break;

        case 'get_report_dates':
            // List all available dates in LightSquid (global report)
            $dirs  = is_dir(LIGHTSQUID_DIR) ? glob(LIGHTSQUID_DIR . '/[0-9]*', GLOB_ONLYDIR) : [];
            rsort($dirs);
            $dates = [];
            foreach ($dirs as $d) {
                $raw = basename($d);
                if (preg_match('/^(\d{4})(\d{2})(\d{2})$/', $raw, $m)) {
                    $dates[] = ['folder' => $raw, 'label' => $m[1] . '-' . $m[2] . '-' . $m[3]];
                }
            }
            echo json_encode(['dates' => $dates]);
            break;
        
        case 'get_api_status':
            // Check that LLM_URL is configured in /etc/proxymon/.env
            $configured = ($_ENV['LLM_URL'] ?? '') !== '';
            echo json_encode(['configured' => $configured]);
            break;

        case 'llm_proxy':
            // ── LLM PROXY ─────────────────────────────────────────────────────
            // Provider-agnostic LLM proxy. All configuration lives in /etc/proxymon/.env
            // The frontend always sends Gemini format and always receives Gemini format.
            // This proxy handles the transformation transparently.
            //
            // Required in .env:
            //   LLM_URL             Full endpoint URL of the provider
            //   LLM_API_KEY         Bearer token (leave empty for local providers)
            //   LLM_MODEL           Model name (leave empty if included in the URL)
            //   LLM_RESPONSE_FORMAT Response format: openai | ollama | gemini
            //
            // LLM_RESPONSE_FORMAT reference:
            //   openai  → standard: choices[0].message.content
            //             also handles wrapped responses: result.choices[0].message.content
            //   ollama  → message.content
            //   gemini  → passthrough (no transformation needed)
            // ─────────────────────────────────────────────────────────────────

            $rawInput = stream_get_contents(fopen('php://input', 'r'), 32768);
            $decoded  = json_decode($rawInput, true);
            if (!$decoded || !isset($decoded['contents'])) {
                http_response_code(400);
                echo json_encode(['error' => 'Invalid request']);
                break;
            }

            $llmUrl    = $_ENV['LLM_URL']             ?? '';
            $llmKey    = $_ENV['LLM_API_KEY']         ?? '';
            $llmModel  = $_ENV['LLM_MODEL']           ?? '';
            $llmFormat = $_ENV['LLM_RESPONSE_FORMAT'] ?? 'openai';

            if (!$llmUrl) {
                http_response_code(503);
                echo json_encode(['error' => msg('api_key_missing')]);
                break;
            }

            $systemText = $decoded['system_instruction']['parts'][0]['text'] ?? '';
            $maxTokens  = $decoded['generationConfig']['maxOutputTokens']    ?? 8192;

            // Transform Gemini conversation history → messages[] (OpenAI-compatible)
            $messages = [];
            if ($systemText !== '') {
                $messages[] = ['role' => 'system', 'content' => $systemText];
            }
            foreach ($decoded['contents'] as $turn) {
                $role    = ($turn['role'] === 'model') ? 'assistant' : 'user';
                $content = $turn['parts'][0]['text'] ?? '';
                if ($content !== '') {
                    $messages[] = ['role' => $role, 'content' => $content];
                }
            }

            // Build payload according to format
            if ($llmFormat === 'gemini') {
                $payload = $rawInput; // passthrough — no transformation needed
            } elseif ($llmFormat === 'ollama') {
                $payload = json_encode([
                    'model'    => $llmModel,
                    'messages' => $messages,
                    'stream'   => false,
                ]);
            } else {
                // openai-compatible (default) — works with most providers
                $body = ['messages' => $messages, 'max_tokens' => $maxTokens, 'stream' => false];
                if ($llmModel !== '') $body['model'] = $llmModel;
                $payload = json_encode($body);
            }

            // Build headers — Authorization is optional (omitted for local providers)
            $headers = ['Content-Type: application/json'];
            if ($llmKey !== '') {
                $headers[] = 'Authorization: Bearer ' . $llmKey;
            }

            $ch = curl_init($llmUrl);
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
            curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_TIMEOUT, 120);

            $resp      = curl_exec($ch);
            $curlError = curl_error($ch);
            curl_close($ch);

            if ($resp === false) {
                http_response_code(502);
                error_log('SquidAI LLM curl error: ' . $curlError);
                echo json_encode(['error' => 'Service unavailable']);
                break;
            }

            $data = json_decode($resp, true);
            if (!$data) {
                http_response_code(502);
                error_log('SquidAI LLM invalid response: ' . $resp);
                echo json_encode(['error' => 'Invalid response from LLM']);
                break;
            }

            // Extract response text according to format
            if ($llmFormat === 'gemini') {
                echo $resp; // passthrough — already in Gemini format
                break;
            } elseif ($llmFormat === 'ollama') {
                $responseText = $data['message']['content'] ?? '';
            } else {
                // openai-compatible
                // Standard path:  choices[0].message.content
                // Wrapped path:   result.choices[0].message.content (some providers add a wrapper object)
                $responseText = $data['choices'][0]['message']['content']
                    ?? $data['result']['choices'][0]['message']['content']
                    ?? $data['result']['response']
                    ?? '';

                $providerError = $data['error']['message']
                    ?? $data['errors'][0]['message']
                    ?? null;
                if ($responseText === '' && $providerError) {
                    http_response_code(502);
                    error_log('SquidAI LLM provider error: ' . $resp);
                    echo json_encode(['error' => $providerError]);
                    break;
                }
            }

            // Return Gemini format — the frontend never needs to change
            echo json_encode([
                'candidates' => [[
                    'content' => [
                        'parts' => [['text' => $responseText]],
                        'role'  => 'model',
                    ],
                    'finishReason' => 'STOP',
                ]],
            ]);
            break;

        default:
            http_response_code(400);
            echo json_encode(['error' => 'Invalid request']);
    }
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => $e->getMessage()]);
}

// ── FUNCTIONS ──────────────────────────────────────────────────────

/**
 * Read realname.cfg and return list of users
 * Format: 192.168.10.73 S-DEMO
 */
function getUsers(): array {
    if (!file_exists(REALNAME_CFG)) {
        return ['error' => msg('realname_not_found'), 'users' => []];
    }

    // Load IPs to exclude from skipuser.cfg
    $skipIps = [];
    $skipFile = SKIPUSERS_CFG;
    if (file_exists($skipFile)) {
        $skipLines = file($skipFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        foreach ($skipLines as $sl) {
            $sl = trim($sl);
            if ($sl && $sl[0] !== '#') {
                $slParts = preg_split('/\s+/', $sl, 2);
                $skipIps[] = $slParts[0]; // solo la IP
            }
        }
    }

    $users = [];
    $lines = file(REALNAME_CFG, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') continue;
        $parts = preg_split('/\s+/', $line, 2);
        if (count($parts) === 2) {
            $ip = $parts[0];
            if (in_array($ip, $skipIps)) continue; // excluir impresoras, APs, etc.
            $users[] = ['ip' => $ip, 'name' => $parts[1]];
        }
    }

    return ['users' => $users, 'count' => count($users)];
}

/**
 * List available dates in LightSquid for an IP
 * Structure: /reports/YYYYMMDD/IP/
 */
function getAvailableDates(string $ip): array {
    if (!$ip) return ['dates' => []];

    // Sanitize and validate IP
    $ip = basename(trim($ip));
    
    // Validar formato de IP válida (IPv4)
    if (!preg_match('/^\d{1,3}(\.\d{1,3}){3}$/', $ip)) {
        return ['dates' => [], 'error' => 'Invalid IP format'];
    }
    
    // Validate that each octet is between 0 and 255
    $octets = explode('.', $ip);
    foreach ($octets as $octet) {
        if ((int)$octet < 0 || (int)$octet > 255) {
            return ['dates' => [], 'error' => 'Invalid IP range'];
        }
    }

    $dates = [];
    $dir   = LIGHTSQUID_DIR;

    if (!is_dir($dir)) {
        return ['dates' => [], 'note' => msg('lightsquid_dir_missing')];
    }

    $dateDirs = glob($dir . '/[0-9]*', GLOB_ONLYDIR);
    if (!$dateDirs) return ['dates' => []];

    rsort($dateDirs);

    foreach ($dateDirs as $dateDir) {
        $dateStr = basename($dateDir);

        if (!preg_match('/^(\d{4})(\d{2})(\d{2})$/', $dateStr, $m)) continue;

        $ipFile = $dateDir . '/' . $ip;

        if (!file_exists($ipFile)) continue;

        $dates[] = $m[1] . '-' . $m[2] . '-' . $m[3];
    }

    return ['dates' => $dates, 'ip' => $ip];
}

/**
 * Obtain traffic report of a user by IP and date
 */
function getUserReport(string $ip, string $date): array {
    if (!$ip) return ['error' => 'IP required'];

    $result = [
        'ip'      => $ip,
        'date'    => $date,
        'domains' => [],
        'total_bytes' => 0,
        'source'  => 'unknown',
    ];

    // Try LightSquid first
    $lightsquidResult = readLightSquidReport($ip, $date);
    if (!empty($lightsquidResult['domains'])) {
        $report = array_merge($result, $lightsquidResult, ['source' => 'lightsquid']);
    } else {
        // Fallback: parser access.log
        $report = array_merge($result, parseAccessLog($ip, $date), ['source' => 'access.log']);
    }

    // Security incidents — added at the end so as not to interfere with normal reporting
    $report['security_incidents'] = getDeniedDirectIps($ip, $date);

    return $report;
}

/**
 * TCP_DENIED account to direct IPv4 for a specific IP and date
 */
function getDeniedDirectIps(string $ip, string $date): array {
    $targetDate = ($date === 'today' || !$date) ? date('Y-m-d') : $date;
    $startTs    = (float) strtotime($targetDate . ' 00:00:00');
    $endTs      = $startTs + 86400;

    $hits      = 0;
    $ipTargets = [];

    $logFile = escapeshellarg(SQUID_LOG_FILE);
    $ipEsc   = escapeshellarg($ip);
    $handle  = popen("grep -a {$ipEsc} {$logFile} | grep 'TCP_DENIED'", 'r');
    if (!$handle) return ['hits' => 0, 'severity' => null];

    while (($line = fgets($handle)) !== false) {
        $parts = preg_split('/\s+/', trim($line));
        if (count($parts) < 7) continue;

        $ts  = (float) $parts[0];
        if ($ts < $startTs || $ts >= $endTs) continue;

        $url = $parts[6] ?? '';
        if (!preg_match('/^(https?:\/\/)?[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/', $url)) continue;

        $hits++;
        $target = preg_replace('#^https?://#', '', $url);
        $ipTargets[$target] = ($ipTargets[$target] ?? 0) + 1;
    }
    pclose($handle);

    if ($hits === 0) return ['hits' => 0, 'severity' => null];

    if ($hits >= 100)    $severity = 'CRITICAL';
    elseif ($hits >= 50) $severity = 'HIGH';
    elseif ($hits >= 10) $severity = 'MEDIUM';
    else                 $severity = 'LOW';

    arsort($ipTargets);

    return [
        'hits'        => $hits,
        'severity'    => $severity,
        'type'        => 'IPv4 directa',
        'top_targets' => array_slice($ipTargets, 0, 5, true),
    ];
}

/**
 * Read LightSquid reports for an IP/date
 * LightSquid saves files by IP within folders by date
 */
function readLightSquidReport(string $ip, string $date): array {
    $dateFormatted = str_replace('-', '', $date); // YYYYMMDD
    $reportFile    = LIGHTSQUID_DIR . '/' . $dateFormatted . '/' . $ip;

    if (!is_file($reportFile)) {
        return ['domains' => [], 'note' => msg('no_report')];
    }

    $domains    = [];
    $totalBytes = 0;

    $lines = file($reportFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        $line = trim($line);
        if (!$line || str_starts_with($line, '#')) continue;

        // Total line: "total: NNNN"
        if (str_starts_with($line, 'total:')) {
            $totalBytes = (int)trim(substr($line, 6));
            continue;
        }

        // Format: domain bytes hits hour_columns...
        $parts = preg_split('/\s+/', $line, 4);
        if (count($parts) < 2) continue;

        $domain = $parts[0];
        $bytes  = (int)$parts[1];
        $hits   = isset($parts[2]) ? (int)$parts[2] : 1;

        if (isset($domains[$domain])) {
            $domains[$domain]['bytes'] += $bytes;
            $domains[$domain]['hits']  += $hits;
        } else {
            $domains[$domain] = ['domain' => $domain, 'bytes' => $bytes, 'hits' => $hits];
        }
    }

    usort($domains, fn($a, $b) => $b['bytes'] - $a['bytes']);
    $all = array_values($domains);
    $top10 = array_slice($all, 0, 10);
    foreach ($top10 as &$d) {
        $d['bytes_human'] = formatBytes($d['bytes']);
    }

    return [
        'domains'      => $top10,
        'all_domains'  => $all,
        'total_bytes'  => $totalBytes,
        'total_human'  => formatBytes($totalBytes),
        'domain_count' => count($domains),
    ];
}

/**
 * Parse Squid access.log filtering by IP and date
 * Format: timestamp elapsed client action/code bytes method url ...
 */
function parseAccessLog(string $ip, string $date): array {
    $domains    = [];
    $totalBytes = 0;

    // Determine range of timestamps
    $targetDate = ($date === 'today') ? date('Y-m-d') : $date;
    $startTs    = strtotime($targetDate . ' 00:00:00');
    $endTs      = $startTs + 86400;

    // Logs posibles: access.log, access.log.1, etc.
    $logFiles = [SQUID_LOG_FILE];
    $rotated  = glob(SQUID_LOG_DIR . '/access.log.*');
    if ($rotated) $logFiles = array_merge($logFiles, $rotated);

    foreach ($logFiles as $logFile) {
        if (!file_exists($logFile)) continue;

        $fh = @fopen($logFile, 'r');
        if (!$fh) continue;

        // For large files, read in chunks
        $lineCount = 0;
        while (($line = fgets($fh)) !== false) {
            $lineCount++;
            if ($lineCount > MAX_LOG_LINES_SCAN) break;

            $line = trim($line);
            if (!$line) continue;

            // Squid format:: "1234567890.123   1234 192.168.1.1 TCP_MISS/200 12345 GET http://domain/path ..."
            $parts = preg_split('/\s+/', $line);
            if (count($parts) < 7) continue;

            $ts      = (float)$parts[0];
            $clientIp = $parts[2];
            $bytes    = (int)$parts[4];
            $url      = $parts[6] ?? '';

            // Filter by IP and date
            if ($clientIp !== $ip) continue;
            if ($ts < $startTs || $ts >= $endTs) {
                // Optimización: si ya pasamos la fecha, salir
                if ($ts >= $endTs && count($domains) > 0) break;
                continue;
            }

            // Extract domain
            $domain = extractDomain($url);
            if (!$domain) continue;

            if (isset($domains[$domain])) {
                $domains[$domain]['bytes'] += $bytes;
                $domains[$domain]['hits']++;
            } else {
                $domains[$domain] = ['domain' => $domain, 'bytes' => $bytes, 'hits' => 1];
            }
            $totalBytes += $bytes;
        }
        fclose($fh);
    }

    usort($domains, fn($a, $b) => $b['bytes'] - $a['bytes']);
    $top10 = array_slice(array_values($domains), 0, 10);
    foreach ($top10 as &$d) {
        $d['bytes_human'] = formatBytes($d['bytes']);
    }

    return [
        'domains'      => $top10,
        'total_bytes'  => $totalBytes,
        'total_human'  => formatBytes($totalBytes),
        'domain_count' => count($domains),
    ];
}

/**
 * Verify access to blacklisted domains for an IP/date
 */
function checkBlacklist(string $ip, string $date): array {
    if (!file_exists(BLOCKDOMAINS)) {
        return ['error' => msg('blockdomains_not_found'), 'hits' => []];
    }

    // Load blacklist
    $blacklist = [];
    $lines = file(BLOCKDOMAINS, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        $line = trim($line);
        if ($line && $line[0] !== '#') {
            $blacklist[] = strtolower($line);
        }
    }

    if (empty($blacklist)) return ['hits' => [], 'blacklist_count' => 0];

    // Get visited domains
    $report = getUserReport($ip, $date);
    $hits   = [];

    $allDomains = $report['all_domains'] ?? $report['domains'];
    foreach ($allDomains as $domainData) {
        $domain = strtolower($domainData['domain']);
        foreach ($blacklist as $blocked) {
            if ($domain === $blocked || str_ends_with($domain, '.' . $blocked)) {
                $hits[] = [
                    'domain'      => $domainData['domain'],
                    'blocked_as'  => $blocked,
                    'bytes'       => $domainData['bytes'],
                    'bytes_human' => formatBytes($domainData['bytes']),
                    'hits'        => $domainData['hits'],
                    'severity'    => 'HIGH',
                ];
                break;
            }
        }
    }

    return [
        'hits'            => $hits,
        'hit_count'       => count($hits),
        'blacklist_count' => count($blacklist),
        'ip'              => $ip,
        'date'            => $date,
        'clean'           => empty($hits),
    ];
}

/**
 * Reads TCP_DENIED from the access.log and filters based on type:
 * - 'domains' → domain in blockdomains.txt
 * - 'patterns' → domain matches locked patterns regex
 * - 'tlds' → Domain TLD in blocktlds.txt
 */
function getBlockedByType(string $type): array {

    $usersData = getUsers();
    $userMap   = [];
    foreach ($usersData['users'] ?? [] as $u) {
        $userMap[$u['ip']] = $u['name'];
    }

    $skipIps = [];
    if (file_exists(SKIPUSERS_CFG)) {
        foreach (file(SKIPUSERS_CFG, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $sl) {
            $sl = trim($sl);
            if ($sl && $sl[0] !== '#') {
                $skipIps[] = preg_split('/\s+/', $sl, 2)[0];
            }
        }
    }

    $incidentMap = [];
    $totalBytes  = 0;

    // 🔹 Load REAL patterns
    $patterns = [];

    // PATTERNS
    if ($type === 'patterns') {
        // IPv4 directa SIEMPRE
        $patterns[] = ['/^(https?:\/\/)?[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/', 'IPv4 directa'];

        if (file_exists(BLOCKPATTERNS)) {
            foreach (file(BLOCKPATTERNS, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
                $line = trim($line);
                if ($line === '' || $line[0] === '#') continue;

                $patterns[] = ['/' . preg_quote($line, '/') . '/i', $line];
            }
        }
    }
    
    // 🔹 Upload blocked domains
    $blockedDomains = [];
    if ($type === 'domains' && file_exists(BLOCKDOMAINS)) {
        foreach (file(BLOCKDOMAINS, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
            $line = trim($line);
            if ($line && $line[0] !== '#') {
                $blockedDomains[] = strtolower($line);
            }
        }
    }

    $logFile = escapeshellarg(SQUID_LOG_FILE);
    $handle  = popen("grep -a 'TCP_DENIED' {$logFile}", 'r');
    if (!$handle) return ['error' => msg('cannot_read_log'), 'incidents' => []];

    $hoy = date('Y-m-d');

    while (($line = fgets($handle)) !== false) {

        $parts = preg_split('/\s+/', trim($line));
        if (count($parts) < 7) continue;

        $ts = (float)$parts[0];
        if (date('Y-m-d', (int)$ts) !== $hoy) continue;

        $client = $parts[2];
        if (!preg_match('/^\d{1,3}(\.\d{1,3}){3}$/', $client)) continue;
        if (in_array($client, $skipIps)) continue;
        $bytes  = (int)$parts[4];
        $url    = $parts[6] ?? '';

        $domain = strtolower(extractDomain($url));
        if (!$domain) $domain = $url;

        // 🔴 FILTRO REAL POR PATRONES
        if ($type === 'patterns') {
            $matched = null;

            foreach ($patterns as [$regex, $label]) {
                if (@preg_match($regex, $url)) {
                    $matched = $label;
                    break;
                }
            }

            if ($matched === null) continue;

            $key = $client . '|' . $matched;

            if (!isset($incidentMap[$key])) {
                $incidentMap[$key] = [
                    'ip'      => $client,
                    'name'    => $userMap[$client] ?? msg('unknown'),
                    'pattern' => $matched,
                    'hits'    => 0,
                ];
            }

            $incidentMap[$key]['hits']++;
            continue;
        }

        // 🔹 FILTER FOR TLDS
        if ($type === 'tlds') {
            static $tlds = null;
            if ($tlds === null) {
                $tlds = [];
                if (file_exists(BLOCKTLDS)) {
                    $tldLines = file(BLOCKTLDS, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
                    foreach ($tldLines as $line) {
                        $line = trim($line);
                        if ($line && $line[0] !== '#') {
                            $tlds[] = strtolower(ltrim($line, '.'));
                        }
                    }
                }
            }
            
            $matchedTld = false;
            foreach ($tlds as $tld) {
                if (str_ends_with($domain, '.' . $tld) || $domain === $tld) {
                    $matchedTld = true;
                    break;
                }
            }
            if (!$matchedTld) continue;
        }

        // 🔹 NORMAL MODE (TCP_DENIED grouped by domain)
        $key = $client . '|' . $domain;

        if (!isset($incidentMap[$key])) {
            $incidentMap[$key] = [
                'ip'     => $client,
                'name'   => $userMap[$client] ?? msg('unknown'),
                'domain' => $domain,
                'hits'   => 0,
                'bytes'  => 0,
            ];
        }

        $incidentMap[$key]['hits']++;
        $incidentMap[$key]['bytes'] += $bytes;
        $totalBytes += $bytes;
    }

    pclose($handle);

    $results = array_values($incidentMap);

    usort($results, fn($a, $b) => $b['hits'] - $a['hits']);

    return [
        'type'      => $type,
        'incidents' => $results,
        'count'     => count($results)
    ];
}

/**
 * Global network summary — read LightSquid (same source as web UI)
 */
function getNetworkSummary(string $date = 'today'): array {
    // Normalizar fecha
    if ($date === 'today' || !$date) {
        $today = date('Y-m-d');
    } else {
        $cleanDate = preg_replace('/[^0-9]/', '', $date);
        if (preg_match('/^\d{8}$/', $cleanDate)) {
            $today = substr($cleanDate,0,4) . '-' . substr($cleanDate,4,2) . '-' . substr($cleanDate,6,2);
        } else {
            $today = date('Y-m-d');
        }
    }
    $dateFormatted = str_replace('-', '', $today);
    $reportBase    = LIGHTSQUID_DIR . '/' . $dateFormatted;

    $usersData = getUsers();
    $userMap   = [];
    foreach ($usersData['users'] ?? [] as $u) {
        $userMap[$u['ip']] = $u['name'];
    }

    $ipStats     = [];
    $domainStats = [];
    $totalBytes  = 0;
    $totalHits   = 0;

    $ipFiles = is_dir($reportBase) ? glob($reportBase . '/*') : [];

    foreach ($ipFiles as $ipFile) {
        if (!is_file($ipFile)) continue;
        $ip   = basename($ipFile);
        $name = $userMap[$ip] ?? msg('unknown');

        if (!isset($ipStats[$ip])) {
            $ipStats[$ip] = ['ip' => $ip, 'name' => $name, 'bytes' => 0, 'hits' => 0];
        }

        $lines = file($ipFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        foreach ($lines as $line) {
            $line = trim($line);
            if (!$line || str_starts_with($line, '#')) continue;

            if (str_starts_with($line, 'total:')) {
                $ipBytes = (int)trim(substr($line, 6));
                $ipStats[$ip]['bytes'] = $ipBytes;
                $totalBytes += $ipBytes;
                continue;
            }

            $parts = preg_split('/\s+/', $line, 4);
            if (count($parts) < 2) continue;

            $domain = $parts[0];
            $bytes  = (int)$parts[1];
            $hits   = isset($parts[2]) ? (int)$parts[2] : 1;

            $ipStats[$ip]['hits'] += $hits;

            if (!isset($domainStats[$domain])) {
                $domainStats[$domain] = ['domain' => $domain, 'bytes' => 0, 'hits' => 0];
            }
            $domainStats[$domain]['bytes'] += $bytes;
            $domainStats[$domain]['hits']  += $hits;

            $totalHits += $hits;
        }
    }

    usort($ipStats, fn($a, $b) => $b['bytes'] - $a['bytes']);
    usort($domainStats, fn($a, $b) => $b['bytes'] - $a['bytes']);

    $topUsers = array_slice(array_values($ipStats), 0, 10);
    foreach ($topUsers as &$u) $u['bytes_human'] = formatBytes($u['bytes']);

    $topDomains = array_slice(array_values($domainStats), 0, 10);
    foreach ($topDomains as &$d) $d['bytes_human'] = formatBytes($d['bytes']);

    return [
        'date'          => $today,
        'total_bytes'   => $totalBytes,
        'total_human'   => formatBytes($totalBytes),
        'total_hits'    => $totalHits,
        'unique_ips'    => count($ipStats),
        'unique_domains'=> count($domainStats),
        'top_users'     => $topUsers,
        'top_domains'   => $topDomains,
    ];
}

// ── HELPERS ──────────────────────────────────────────────────────────

function extractDomain(string $url): string {
    if (!$url || $url === '-') return '';
    
    // Handle CONNECT (HTTPS tunnels): host:port
    if (!str_contains($url, '://') && str_contains($url, ':')) {
        return strtolower(explode(':', $url)[0]);
    }
    
    // Try parse_url first
    $host = parse_url($url, PHP_URL_HOST);
    
    // If it fails, try cleaning up malformed URLs (ej: https:///dominio.com)
    if (!$host) {
        // Delete protocol and clean slashes
        $cleaned = preg_replace('#^[a-z]+:///*#i', '', $url);
        // Extract to first slash or end
        $host = explode('/', $cleaned)[0];
        // Delete port if it exists
        $host = explode(':', $host)[0];
    }
    
    if (!$host) return '';
    
    // Remove www.
    return strtolower(preg_replace('/^www\./', '', $host));
}

function formatBytes(int $bytes): string {
    if ($bytes >= 1073741824) return number_format($bytes / 1073741824, 2) . ' GB';
    if ($bytes >= 1048576)    return number_format($bytes / 1048576, 2) . ' MB';
    if ($bytes >= 1024)       return number_format($bytes / 1024, 2) . ' KB';
    return $bytes . ' B';
}
