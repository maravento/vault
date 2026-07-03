<?php
/**
 * Samba Audit Log Reader API
 * File: smbapi.php
 */

header('Content-Type: application/json');

$server_ip = '';
$smb_net   = '';
$env_file  = '/var/www/smbstack/smbstack.env';
if (file_exists($env_file)) {
    foreach (file($env_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (strpos($line, 'SERVER_IP=') === 0) {
            $server_ip = str_replace(array('"', "'"), '', trim(substr($line, strlen('SERVER_IP='))));
        } elseif (strpos($line, 'SMB_NET=') === 0) {
            $smb_net = str_replace(array('"', "'"), '', trim(substr($line, strlen('SMB_NET='))));
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
    $bits        = (int)$bits;
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
        || ($smb_net && ip_in_cidr($remote_addr, $smb_net));
if (!$allowed) {
    http_response_code(403);
    echo json_encode(['success' => false, 'error' => 'Forbidden']);
    exit;
}

// Configuration - READ MULTIPLE FILES
define('LOG_FILES', [
    '/var/log/samba/log.audit',      // Current file
    '/var/log/samba/log.audit.1.gz', // Rotated logs
    '/var/log/samba/log.audit.2.gz',
    '/var/log/samba/log.audit.3.gz',
    '/var/log/samba/log.audit.4.gz',
    '/var/log/samba/log.audit.5.gz',
    '/var/log/samba/log.audit.6.gz',
    '/var/log/samba/log.audit.7.gz'
]);
define('MAX_LINES', 50000);

class SambaLogReader {
    private $logFiles;
    
    public function __construct($logFiles) {
        $this->logFiles = $logFiles;
    }
    
    /**
     * Read log files and return parsed records
     */
    public function getLogs($limit = 50000) {
        $allLogs = [];
        
        foreach ($this->logFiles as $logFile) {
            if (!file_exists($logFile)) {
                continue;
            }
            
            if (!is_readable($logFile)) {
                error_log("Cannot read log file: $logFile");
                continue;
            }
            
            try {
                $remaining = $limit - count($allLogs);
                $fileLogs = $this->readSingleFile($logFile, $remaining);
                $allLogs = array_merge($allLogs, $fileLogs);
                
                // Stop if we have enough logs
                if (count($allLogs) >= $limit) {
                    break;
                }
            } catch (Exception $e) {
                error_log("Error reading $logFile: " . $e->getMessage());
            }
        }
        
        // Sort by timestamp (newest first)
        usort($allLogs, function($a, $b) {
            return strcmp($b['timestamp'], $a['timestamp']);
        });
        
        return array_slice($allLogs, 0, $limit);
    }
    
    /**
     * Read a single file (normal or compressed)
     */
    private function readSingleFile($filename, $limit = 50000) {
        $logs = [];
        
        if (substr($filename, -3) === '.gz') {
            // Compressed file - gzip doesn't support seeking to the end, so
            // stream through it line by line but only keep a sliding window
            // of the most recent $limit entries (oldest ones are dropped as
            // newer ones come in), instead of stopping at the first $limit
            // lines from the start of the (oldest) rotated file.
            $gz = gzopen($filename, 'r');
            if ($gz === false) {
                throw new Exception("Cannot read gzip file: $filename");
            }
            $window = new SplQueue();
            while (!gzeof($gz)) {
                $line = gzgets($gz, 16384);
                if ($line === false) break;
                $parsed = $this->parseLine(trim($line));
                if ($parsed) {
                    $window->enqueue($parsed);
                    if (count($window) > $limit) {
                        $window->dequeue();
                    }
                }
            }
            gzclose($gz);
            $logs = iterator_to_array($window, false);
        } else {
            // Normal file - read from end (most recent logs)
            $file = new SplFileObject($filename);
            $file->seek(PHP_INT_MAX);
            $totalLines = $file->key();
            
            $startLine = max(0, $totalLines - $limit);
            $file->seek($startLine);
            
            while (!$file->eof() && count($logs) < $limit) {
                $line = trim($file->current());
                if (!empty($line)) {
                    $parsed = $this->parseLine($line);
                    if ($parsed) {
                        $logs[] = $parsed;
                    }
                }
                $file->next();
            }
        }
        
        return $logs;
    }
    
    /**
     * Parse a Samba log line
     */
    private function parseLine($line) {
        // Format: 2025-11-24T09:25:38.103362-05:00 user smbd_audit: 192.168.10.124|foo|shared|unlinkat|ok|/path/file
        
        $pattern = '/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+[+-]\d{2}:\d{2})\s+\S+\s+smbd_audit:\s+(.+?)\|(.+?)\|(.+?)\|(.+?)\|(.+?)\|(.+)$/';
        
        if (preg_match($pattern, $line, $matches)) {
            return [
                'timestamp' => $matches[1],
                'ip' => trim($matches[2]),
                'user' => trim($matches[3]),
                'share' => trim($matches[4]),
                'action' => trim($matches[5]),
                'status' => trim($matches[6]) === 'ok' ? 'success' : 'denied',
                'file' => trim($matches[7])
            ];
        }
        
        return null;
    }
}

// Request handling
try {
    $action = $_GET['action'] ?? 'getLogs';
    $reader = new SambaLogReader(LOG_FILES);
    
    if ($action === 'getLogs') {
        $limit = min((int)($_GET['limit'] ?? 50000), 50000);
        $logs = $reader->getLogs($limit);
        
        echo json_encode([
            'success' => true,
            'data' => array_values($logs),
            'count' => count($logs)
        ]);
    } else {
        throw new Exception("Invalid action");
    }
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => 'Internal server error'
    ]);
}
?>
