<?php
/**
 * Samba Audit Log Diagnostic Tool
 * This script helps diagnose issues with log parsing
 * How to use
 * php /var/www/smbaudit/smbaudit-diagnostic.php
 */

// Configuration
$LOG_FILE = '/var/log/samba/log.audit';

echo "=== SAMBA AUDIT LOG DIAGNOSTIC ===\n\n";

// Check if file exists
if (!file_exists($LOG_FILE)) {
    echo "❌ ERROR: Log file does not exist: $LOG_FILE\n";
    exit(1);
}

// Check if file is readable
if (!is_readable($LOG_FILE)) {
    echo "❌ ERROR: Cannot read log file: $LOG_FILE\n";
    exit(1);
}

// Get file info
$fileSize = filesize($LOG_FILE);
echo "📄 File: $LOG_FILE\n";
echo "📊 File size: " . number_format($fileSize) . " bytes (" . round($fileSize/1024/1024, 2) . " MB)\n\n";

// Count total lines
$totalLines = 0;
$file = new SplFileObject($LOG_FILE);
$file->seek(PHP_INT_MAX);
$totalLines = $file->key() + 1;

echo "📝 Total lines in file: " . number_format($totalLines) . "\n\n";

// Parse pattern
$pattern = '/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+[+-]\d{2}:\d{2})\s+\S+\s+smbd_audit:\s+(.+?)\|(.+?)\|(.+?)\|(.+?)\|(.+?)\|(.+)$/';

// Analyze the file
$parsedLines = 0;
$failedLines = 0;
$emptyLines = 0;
$sampleFailedLines = [];
$actions = [];

echo "🔍 Analyzing log entries...\n";

$file->rewind();
$lineNumber = 0;

while (!$file->eof()) {
    $lineNumber++;
    $line = trim($file->current());
    
    if (empty($line)) {
        $emptyLines++;
    } elseif (preg_match($pattern, $line, $matches)) {
        $parsedLines++;
        $action = trim($matches[5]);
        $actions[$action] = ($actions[$action] ?? 0) + 1;
    } else {
        $failedLines++;
        if (count($sampleFailedLines) < 5) {
            $sampleFailedLines[] = [
                'line' => $lineNumber,
                'content' => substr($line, 0, 200)
            ];
        }
    }
    
    $file->next();
}

echo "\n📊 RESULTS:\n";
echo "✅ Successfully parsed: " . number_format($parsedLines) . " lines\n";
echo "❌ Failed to parse: " . number_format($failedLines) . " lines\n";
echo "⚪ Empty lines: " . number_format($emptyLines) . " lines\n";
echo "📈 Total analyzed: " . number_format($lineNumber) . " lines\n\n";

if ($parsedLines > 0) {
    echo "🎯 Actions found:\n";
    arsort($actions);
    foreach ($actions as $action => $count) {
        echo "   - $action: " . number_format($count) . "\n";
    }
    echo "\n";
}

if (count($sampleFailedLines) > 0) {
    echo "⚠️  Sample of failed lines:\n";
    foreach ($sampleFailedLines as $failed) {
        echo "\n   Line {$failed['line']}:\n";
        echo "   {$failed['content']}\n";
    }
    echo "\n";
}

// Check what the API would return
echo "🔎 Checking API behavior...\n";
$startLine = max(0, $totalLines - 10000);
echo "   - API reads from line: " . number_format($startLine) . " to " . number_format($totalLines) . "\n";
echo "   - That's " . number_format(min(10000, $totalLines)) . " lines being read by the API\n\n";

if ($totalLines > 10000) {
    echo "⚠️  WARNING: Your log file has more than 10,000 lines!\n";
    echo "   The API only reads the last 10,000 lines from the current file.\n";
    echo "   Older entries are not being read unless they're in rotated .gz files.\n\n";
}

// Show last few entries
echo "📋 Last 3 parsed entries:\n";
$file->rewind();
$lastEntries = [];
while (!$file->eof()) {
    $line = trim($file->current());
    if (!empty($line) && preg_match($pattern, $line, $matches)) {
        $lastEntries[] = [
            'timestamp' => $matches[1],
            'ip' => trim($matches[2]),
            'action' => trim($matches[5]),
            'file' => trim($matches[7])
        ];
        if (count($lastEntries) > 3) {
            array_shift($lastEntries);
        }
    }
    $file->next();
}

foreach ($lastEntries as $entry) {
    echo "\n   {$entry['timestamp']} | {$entry['ip']} | {$entry['action']}\n";
    echo "   File: " . substr($entry['file'], 0, 100) . "\n";
}

echo "\n✅ Diagnostic complete!\n";
?>
