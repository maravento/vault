<?php
// maravento.com
//
////////////////////////////////////////////////////////////////////////////////
//
// smbstack - Shared Folder Browser
// https://github.com/maravento/vault/tree/master/smbstack
//
////////////////////////////////////////////////////////////////////////////////

$base_path = '';
$env_file  = '/var/www/smbstack/smbstack.env';
if (file_exists($env_file)) {
    foreach (file($env_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (strpos($line, 'SHARED_PATH=') === 0) {
            $base_path = str_replace(array('"', "'"), "", trim(substr($line, strlen('SHARED_PATH='))));
            break;
        }
    }
}
if (!$base_path || !is_dir($base_path)) {
    http_response_code(500);
    die('Shared folder not configured. Check /var/www/smbstack/smbstack.env');
}

// Audit log writer
function write_audit($action, $file_path) {
    $log_file  = '/var/log/samba/log.audit';
    $timestamp = date('Y-m-d\TH:i:s.000000P');
    $ip        = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    $user      = 'www-data';
    $share     = 'compartida';
    $env_file  = '/var/www/smbstack/smbstack.env';
    if (file_exists($env_file)) {
        foreach (file($env_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
            if (strpos($line, 'SHARED_NAME=') === 0) {
                $share = str_replace(array('"', "'"), "", trim(substr($line, strlen('SHARED_NAME='))));
                break;
            }
        }
    }
    $entry = "$timestamp $user smbd_audit: $ip|$user|$share|$action|ok|$file_path\n";
    file_put_contents($log_file, $entry, FILE_APPEND | LOCK_EX);
}

$request   = isset($_GET['path']) ? $_GET['path'] : '';
$request   = ltrim(preg_replace('/[\x00\x08\x0B\x0C\x0E-\x1F]/', '', $request), '/');
$full_path = realpath($base_path . '/' . $request);

if (!$full_path || strpos($full_path, realpath($base_path)) !== 0 || !is_dir($full_path)) {
    $full_path = realpath($base_path);
    $request   = '';
}

// Upload handler
$upload_msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['upload'])) {
    $upload_depth = $request === '' ? 0 : substr_count(trim($request, '/'), '/') + 1;
    if ($upload_depth < 1) {
        header('Location: ?path=' . urlencode($request) . '&msg=protected');
        exit;
    }
    $orig_name  = basename($_FILES['upload']['name']);
    $safe_name  = preg_replace('/[^a-zA-Z0-9._\- ]/', '_', $orig_name);
    $safe_name  = preg_replace('/\.php[\d]?$/i', '.txt', $safe_name);
    $safe_name  = trim($safe_name, '. ');
    if ($safe_name === '') $safe_name = 'upload_' . time();
    $target = $full_path . '/' . $safe_name;
    if (move_uploaded_file($_FILES['upload']['tmp_name'], $target)) {
        chmod($target, 0666);
        write_audit('mkdirat', $target);
        $upload_msg = 'success';
    } else {
        $upload_msg = 'error';
    }
    header('Location: ?path=' . urlencode($request) . '&msg=' . $upload_msg);
    exit;
}

// Recycle handler
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['recycle'])) {
    $item_rel  = ltrim(preg_replace('/[\x00\x08\x0B\x0C\x0E-\x1F]/', '', $_POST['recycle']), '/');
    $item_full = realpath($base_path . '/' . $item_rel);
    $recycle   = $base_path . '/.recycle';

    if ($item_full && strpos($item_full, realpath($base_path)) === 0 && $item_full !== realpath($base_path)) {
        // Protect root-level items (files and directories)
        $depth = substr_count(str_replace(realpath($base_path), '', $item_full), DIRECTORY_SEPARATOR);
        if ($depth <= 1) {
            $recycle_msg = 'protected';
        } else {
            if (!is_dir($recycle)) mkdir($recycle, 0775, true);
            $dest = $recycle . '/' . basename($item_full);
            if (file_exists($dest)) $dest .= '_' . time();
            rename($item_full, $dest);
            write_audit('unlinkat', $item_full);
            $recycle_msg = 'recycled';
        }
    } else {
        $recycle_msg = 'error';
    }
    $back = dirname($item_rel) === '.' ? '' : dirname($item_rel);
    header('Location: ?path=' . urlencode($back) . '&msg=' . $recycle_msg);
    exit;
}

$msg = isset($_GET['msg']) ? $_GET['msg'] : '';

$parts = $request ? explode('/', trim($request, '/')) : [];

$items = scandir($full_path);
$dirs  = [];
$files = [];

foreach ($items as $item) {
    if ($item === '.' || $item === '..') continue;
    if ($item[0] === '.') continue;
    if ($item === '.recycle') continue;
    $item_path = $full_path . '/' . $item;
    if (is_dir($item_path)) $dirs[]  = $item;
    else                     $files[] = $item;
}
sort($dirs);
sort($files);

function format_size($bytes) {
    if ($bytes >= 1073741824) return number_format($bytes / 1073741824, 2) . ' GB';
    if ($bytes >= 1048576)    return number_format($bytes / 1048576, 2) . ' MB';
    if ($bytes >= 1024)       return number_format($bytes / 1024, 2) . ' KB';
    return $bytes . ' B';
}

function get_icon($name) {
    $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
    $map = [
        'pdf' => '📄', 'doc' => '📝', 'docx' => '📝', 'xls' => '📊', 'xlsx' => '📊',
        'ppt' => '📋', 'pptx' => '📋', 'txt' => '📃', 'zip' => '📦', 'rar' => '📦',
        '7z'  => '📦', 'tar' => '📦', 'gz'  => '📦', 'jpg' => '🖼️', 'jpeg' => '🖼️',
        'png' => '🖼️', 'gif' => '🖼️', 'svg' => '🖼️', 'mp4' => '🎬', 'mkv'  => '🎬',
        'avi' => '🎬', 'mp3' => '🎵', 'wav' => '🎵', 'sh'  => '⚙️', 'py'   => '🐍',
        'js'  => '📜', 'html'=> '🌐', 'css' => '🎨',
    ];
    return isset($map[$ext]) ? $map[$ext] : '📎';
}

$total_files = count($files);
$total_dirs  = count($dirs);
$total_size  = 0;
foreach ($files as $f) $total_size += filesize($full_path . '/' . $f);
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SMBstack — Shared Folder</title>
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>📁</text></svg>" type="image/svg+xml">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            min-height: 100vh;
        }

        .header {
            background: #2c3e50;
            padding: 0.75rem 1rem;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            display: flex;
            align-items: center;
            justify-content: space-between;
            flex-wrap: wrap;
            gap: 0.5rem;
        }

        .header h1 { color: white; font-size: 1.1rem; font-weight: 600; display: flex; align-items: center; gap: 0.5rem; }
        .header-meta { color: #a0aec0; font-size: 0.8rem; }

        .stats-bar {
            background: white;
            margin: 1rem;
            border-radius: 8px;
            padding: 0.75rem 1rem;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            display: flex;
            align-items: center;
            justify-content: space-between;
            flex-wrap: wrap;
            gap: 0.5rem;
        }

        .stats-info { display: flex; gap: 1.5rem; flex-wrap: wrap; font-size: 0.85rem; color: #475569; }
        .stats-info span { display: flex; align-items: center; gap: 0.3rem; }

        .toolbar {
            display: flex;
            gap: 0.5rem;
            flex-wrap: wrap;
        }

        .btn {
            padding: 0.45rem 0.9rem;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-size: 0.85rem;
            font-weight: 500;
            white-space: nowrap;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            gap: 0.3rem;
            transition: background 0.15s;
        }

        .btn-primary   { background: #2563eb; color: white; }
        .btn-primary:hover { background: #1d4ed8; }
        .btn-success   { background: #16a34a; color: white; }
        .btn-success:hover { background: #15803d; }
        .btn-secondary { background: #64748b; color: white; }
        .btn-secondary:hover { background: #475569; }
        .btn-warning   { background: #d97706; color: white; }
        .btn-warning:hover { background: #b45309; }
        .btn-danger    { background: #dc2626; color: white; }
        .btn-danger:hover { background: #b91c1c; }

        .breadcrumb {
            background: white;
            margin: 0 1rem 1rem;
            border-radius: 8px;
            padding: 0.6rem 1rem;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            font-size: 0.85rem;
            display: flex;
            align-items: center;
            gap: 0.3rem;
            flex-wrap: wrap;
            color: #64748b;
        }

        .breadcrumb a { color: #2563eb; text-decoration: none; }
        .breadcrumb a:hover { text-decoration: underline; }
        .breadcrumb .sep { color: #cbd5e1; }
        .breadcrumb .current { color: #1e293b; font-weight: 500; }

        .alert {
            margin: 0 1rem 1rem;
            padding: 0.75rem 1rem;
            border-radius: 8px;
            font-size: 0.9rem;
        }
        .alert-success { background: #dcfce7; color: #166534; border: 1px solid #bbf7d0; }
        .alert-error   { background: #fee2e2; color: #991b1b; border: 1px solid #fecaca; }

        .upload-area {
            background: white;
            margin: 0 1rem 1rem;
            border-radius: 8px;
            padding: 1rem;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            display: none;
        }
        .upload-area.open { display: block; }
        .upload-area form { display: flex; align-items: center; gap: 0.75rem; flex-wrap: wrap; }
        .upload-area input[type=file] { flex: 1; font-size: 0.85rem; }

        .table-container {
            background: white;
            border-radius: 12px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            overflow-x: auto;
            margin: 0 1rem 1rem;
        }

        table { width: 100%; border-collapse: collapse; min-width: 600px; }

        th {
            background: #f8fafc;
            text-align: left;
            font-weight: 600;
            color: #475569;
            font-size: 0.85rem;
            padding: 0.75rem 1rem;
            border-bottom: 1px solid #e2e8f0;
            position: sticky;
            top: 0;
        }

        td { padding: 0.65rem 1rem; border-bottom: 1px solid #e2e8f0; font-size: 0.85rem; vertical-align: middle; }
        tr:last-child td { border-bottom: none; }
        tr:hover td { background: #f8fafc; }

        .name-cell { display: flex; align-items: center; gap: 0.5rem; }
        .name-cell a { color: #1e293b; text-decoration: none; }
        .name-cell a:hover { color: #2563eb; }
        .dir-link { color: #d97706 !important; font-weight: 500; }
        .dir-link:hover { color: #b45309 !important; }

        .muted { color: #64748b; }

        .action-cell { display: flex; gap: 0.4rem; }

        .no-data { text-align: center; padding: 3rem; color: #64748b; font-size: 0.95rem; }

        footer { text-align: center; padding: 1.5rem; font-size: 0.8rem; color: #94a3b8; }
        footer a { color: #94a3b8; text-decoration: none; }
        footer a:hover { color: #2563eb; }
    </style>
</head>
<body>

<div class="header">
    <h1>📁 SMBstack &mdash; Shared Folder</h1>
    <div class="header-meta"><?= date('Y-m-d H:i:s') ?></div>
</div>

<?php if ($msg === 'success'): ?>
<div class="alert alert-success">✅ File uploaded successfully.</div>
<?php elseif ($msg === 'recycled'): ?>
<div class="alert alert-success">🗑️ Item moved to recycle bin.</div>
<?php elseif ($msg === 'protected'): ?>
<div class="alert alert-error">🔒 Root folders cannot be deleted.</div>
<?php elseif ($msg === 'error'): ?>
<div class="alert alert-error">❌ Operation failed. Check permissions.</div>
<?php endif; ?>

<div class="stats-bar">
    <div class="stats-info">
        <span>📁 <?= $total_dirs ?> folder<?= $total_dirs !== 1 ? 's' : '' ?></span>
        <span>📎 <?= $total_files ?> file<?= $total_files !== 1 ? 's' : '' ?></span>
        <span>💾 <?= format_size($total_size) ?></span>
    </div>
    <div class="toolbar">
        <button class="btn btn-primary" onclick="location.reload()">🔄 Reload</button>
        <button class="btn btn-success" onclick="document.getElementById('upload-area').classList.toggle('open')">⬆️ Upload</button>
        <a class="btn btn-secondary" href="/audit/">📊 Audit</a>
    </div>
</div>

<div class="upload-area" id="upload-area">
    <form method="POST" enctype="multipart/form-data">
        <input type="hidden" name="path" value="<?= htmlspecialchars($request) ?>">
        <input type="file" name="upload" required>
        <button type="submit" class="btn btn-success">Upload</button>
        <button type="button" class="btn btn-secondary" onclick="document.getElementById('upload-area').classList.remove('open')">Cancel</button>
    </form>
</div>

<div class="breadcrumb">
    <a href="?path=">📁 <?= htmlspecialchars(basename($base_path)) ?></a>
    <?php
    $crumb_path = '';
    foreach ($parts as $i => $part) {
        $crumb_path .= ($i ? '/' : '') . $part;
        echo '<span class="sep">/</span>';
        if ($i < count($parts) - 1) {
            echo '<a href="?path=' . urlencode($crumb_path) . '">' . htmlspecialchars($part) . '</a>';
        } else {
            echo '<span class="current">' . htmlspecialchars($part) . '</span>';
        }
    }
    ?>
</div>

<div class="table-container">
    <table>
        <thead>
            <tr>
                <th style="width:45%">Name</th>
                <th style="width:12%">Size</th>
                <th style="width:20%">Modified</th>
                <th style="width:23%">Actions</th>
            </tr>
        </thead>
        <tbody>
        <?php if ($request):
            $parent = dirname($request) === '.' ? '' : dirname($request); ?>
            <tr>
                <td colspan="4">
                    <div class="name-cell">
                        <span>⬆️</span>
                        <a class="dir-link" href="?path=<?= urlencode($parent) ?>">.. (parent folder)</a>
                    </div>
                </td>
            </tr>
        <?php endif; ?>

        <?php foreach ($dirs as $dir):
            $rel   = ($request ? $request . '/' : '') . $dir;
            $mtime = filemtime($full_path . '/' . $dir);
        ?>
            <tr>
                <td>
                    <div class="name-cell">
                        <span>📂</span>
                        <a class="dir-link" href="?path=<?= urlencode($rel) ?>"><?= htmlspecialchars($dir) ?></a>
                    </div>
                </td>
                <td class="muted">&mdash;</td>
                <td class="muted"><?= date('Y-m-d H:i', $mtime) ?></td>
                <td><div class="action-cell">
                    <a class="btn btn-primary" href="?path=<?= urlencode($rel) ?>">📂 Open</a>
                    <?php if (substr_count($rel, '/') >= 1): ?>
                    <form method="POST" style="display:inline" onsubmit="return confirm('Move this folder to recycle bin?')">
                        <input type="hidden" name="recycle" value="<?= htmlspecialchars($rel) ?>">
                        <button type="submit" class="btn btn-danger">🗑️</button>
                    </form>
                    <?php endif; ?>
                </div></td>
            </tr>
        <?php endforeach; ?>

        <?php foreach ($files as $file):
            $file_full = $full_path . '/' . $file;
            $rel       = ($request ? $request . '/' : '') . $file;
            $size      = filesize($file_full);
            $mtime     = filemtime($file_full);
            $dl_url    = '/shared/files/' . ltrim($rel, '/');
        ?>
            <tr>
                <td>
                    <div class="name-cell">
                        <span><?= get_icon($file) ?></span>
                        <a href="<?= htmlspecialchars($dl_url) ?>" target="_blank"><?= htmlspecialchars($file) ?></a>
                    </div>
                </td>
                <td class="muted"><?= format_size($size) ?></td>
                <td class="muted"><?= date('Y-m-d H:i', $mtime) ?></td>
                <td><div class="action-cell">
                    <a class="btn btn-primary" href="<?= htmlspecialchars($dl_url) ?>" target="_blank">👁️ View</a>
                    <a class="btn btn-success" href="<?= htmlspecialchars($dl_url) ?>" download>⬇️ Download</a>
                    <form method="POST" style="display:inline" onsubmit="return confirm('Move this file to recycle bin?')">
                        <input type="hidden" name="recycle" value="<?= htmlspecialchars($rel) ?>">
                        <button type="submit" class="btn btn-danger">🗑️</button>
                    </form>
                </div></td>
            </tr>
        <?php endforeach; ?>

        <?php if (empty($dirs) && empty($files)): ?>
            <tr><td colspan="4"><div class="no-data">📭 Empty folder</div></td></tr>
        <?php endif; ?>
        </tbody>
    </table>
</div>

<footer>
    <a href="https://github.com/maravento/vault/tree/master/smbstack" target="_blank">SMBstack</a>
    &mdash; maravento.com
</footer>

</body>
</html>
