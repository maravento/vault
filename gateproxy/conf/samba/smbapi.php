<?php
/**
 * Samba Audit Log Reader API
 * File: api.php
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST');
header('Access-Control-Allow-Headers: Content-Type');

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
                $fileLogs = $this->readSingleFile($logFile);
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
    private function readSingleFile($filename) {
        $logs = [];
        
        if (substr($filename, -3) === '.gz') {
            // Compressed file
            $lines = gzfile($filename);
            if ($lines === false) {
                throw new Exception("Cannot read gzip file: $filename");
            }
            
            foreach ($lines as $line) {
                $parsed = $this->parseLine(trim($line));
                if ($parsed) {
                    $logs[] = $parsed;
                }
            }
        } else {
            // Normal file - read from end (most recent logs)
            $file = new SplFileObject($filename);
            $file->seek(PHP_INT_MAX);
            $totalLines = $file->key();
            
            $startLine = max(0, $totalLines - 10000);
            $file->seek($startLine);
            
            while (!$file->eof()) {
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
        $limit = isset($_GET['limit']) ? (int)$_GET['limit'] : 50000;
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
        'error' => $e->getMessage()
    ]);
}
?>
