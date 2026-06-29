<?php
// maravento.com
//
////////////////////////////////////////////////////////////////////////////////
//
// shared.php
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
function get_client_ip() {
    // Only honor client-supplied IP headers if the direct connection
    // comes from a known/trusted source (e.g. a local Cloudflare Tunnel
    // via cloudflared, whose requests arrive from 127.0.0.1). Configure
    // trusted IPs in smbstack.env as TRUSTED_PROXIES="127.0.0.1,..."
    $remote_addr = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';

    $trusted_proxies = array();
    $env_file = '/var/www/smbstack/smbstack.env';
    if (file_exists($env_file)) {
        foreach (file($env_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
            if (strpos($line, 'TRUSTED_PROXIES=') === 0) {
                $value = str_replace(array('"', "'"), "", trim(substr($line, strlen('TRUSTED_PROXIES='))));
                $trusted_proxies = array_filter(array_map('trim', explode(',', $value)));
                break;
            }
        }
    }

    if (in_array($remote_addr, $trusted_proxies, true)) {
        $forwarded = $_SERVER['HTTP_CF_CONNECTING_IP'] ?? $_SERVER['HTTP_X_FORWARDED_FOR'] ?? null;
        if ($forwarded !== null) {
            // X-Forwarded-For may contain a comma-separated chain; take the first entry
            $first = trim(explode(',', $forwarded)[0]);
            if (filter_var($first, FILTER_VALIDATE_IP)) {
                return $first;
            }
        }
    }

    return $remote_addr;
}

function write_audit($action, $file_path) {
    $log_file  = '/var/log/samba/log.audit';
    $timestamp = date('Y-m-d\TH:i:s.000000P');
    $ip        = get_client_ip();
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
    $file_path = str_replace(["\r", "\n"], '', $file_path);
    $entry = "$timestamp $user smbd_audit: $ip|$user|$share|$action|ok|$file_path\n";
    file_put_contents($log_file, $entry, FILE_APPEND | LOCK_EX);
}

$request   = isset($_GET['path']) ? $_GET['path'] : '';
$request   = ltrim(preg_replace('/[\x00-\x1F]/', '', $request), '/');
$base_real = realpath($base_path);
$full_path = realpath($base_path . '/' . $request);

if (!$full_path || ($full_path !== $base_real && strpos($full_path, $base_real . DIRECTORY_SEPARATOR) !== 0) || !is_dir($full_path)) {
    $full_path = $base_real;
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
    $files     = $_FILES['upload'];
    $count     = is_array($files['name']) ? count($files['name']) : 1;
    $succeeded = 0;
    $failed    = 0;
    for ($i = 0; $i < $count; $i++) {
        $tmp_name  = is_array($files['tmp_name']) ? $files['tmp_name'][$i] : $files['tmp_name'];
        $orig_name = is_array($files['name'])     ? $files['name'][$i]     : $files['name'];
        $error     = is_array($files['error'])    ? $files['error'][$i]    : $files['error'];
        if ($error !== UPLOAD_ERR_OK) { $failed++; continue; }
        $orig_name = basename($orig_name);
        $safe_name = preg_replace('/[^a-zA-Z0-9._\- ]/', '_', $orig_name);
        $safe_name = preg_replace('/\.(php[0-9]?|phtml|pht|phar|cgi|pl|asp|aspx|jsp|sh|htaccess|html?|shtml|svg|xml)(?=\.|$)/i', '.txt', $safe_name);
        $safe_name = trim($safe_name, '. ');
        if ($safe_name === '') $safe_name = 'upload_' . time() . '_' . $i;
        $target = $full_path . '/' . $safe_name;
        if (move_uploaded_file($tmp_name, $target)) {
            chmod($target, 0664);
            @chgrp($target, 'sambashare');
            write_audit('pwrite', $target);
            $succeeded++;
        } else {
            $failed++;
        }
    }
    if ($failed === 0)          $upload_msg = 'success';
    elseif ($succeeded === 0)   $upload_msg = 'error';
    else                        $upload_msg = 'partial';
    header('Location: ?path=' . urlencode($request) . '&msg=' . $upload_msg);
    exit;
}

// Mkdir handler
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['mkdir'])) {
    $mkdir_depth = $request === '' ? 0 : substr_count(trim($request, '/'), '/') + 1;
    if ($mkdir_depth < 1) {
        header('Location: ?path=' . urlencode($request) . '&msg=protected');
        exit;
    }
    $dir_name = basename(trim($_POST['mkdir']));
    $dir_name = preg_replace('/[^a-zA-Z0-9._\- ]/', '_', $dir_name);
    $dir_name = trim($dir_name, '. ');
    if ($dir_name === '') {
        header('Location: ?path=' . urlencode($request) . '&msg=error');
        exit;
    }
    $target = $full_path . '/' . $dir_name;
    if (file_exists($target)) {
        header('Location: ?path=' . urlencode($request) . '&msg=exists');
        exit;
    }
    if (mkdir($target, 0775)) {
        chown($target, 'www-data');
        @chgrp($target, 'sambashare');
        write_audit('mkdirat', $target);
        $mkdir_msg = 'success';
    } else {
        $mkdir_msg = 'error';
    }
    header('Location: ?path=' . urlencode($request) . '&msg=mkdir_' . $mkdir_msg);
    exit;
}

// New file handler (create an empty or text-seeded file directly, no local upload needed)
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['newfile'])) {
    $newfile_depth = $request === '' ? 0 : substr_count(trim($request, '/'), '/') + 1;
    if ($newfile_depth < 1) {
        header('Location: ?path=' . urlencode($request) . '&msg=protected');
        exit;
    }
    $file_name = basename(trim($_POST['newfile']));
    $file_name = preg_replace('/[^a-zA-Z0-9._\- ]/', '_', $file_name);
    // Same dangerous-extension guard as the upload handler, so a "new file"
    // can't be used to plant executable/script content either.
    $file_name = preg_replace('/\.(php[0-9]?|phtml|pht|phar|cgi|pl|asp|aspx|jsp|sh|htaccess|html?|shtml|svg|xml)(?=\.|$)/i', '.txt', $file_name);
    $file_name = trim($file_name, '. ');
    if ($file_name === '') {
        header('Location: ?path=' . urlencode($request) . '&msg=error');
        exit;
    }
    $target = $full_path . '/' . $file_name;
    if (file_exists($target)) {
        header('Location: ?path=' . urlencode($request) . '&msg=exists');
        exit;
    }
    $content = isset($_POST['newfile_content']) ? (string) $_POST['newfile_content'] : '';
    if (file_put_contents($target, $content) !== false) {
        chmod($target, 0664);
        @chgrp($target, 'sambashare');
        write_audit('pwrite', $target);
        $newfile_msg = 'success';
    } else {
        $newfile_msg = 'error';
    }
    header('Location: ?path=' . urlencode($request) . '&msg=newfile_' . $newfile_msg);
    exit;
}


// Recycle handler
//
// Layout: .recycle/www-data/<YYYYMMDD>/<original relative path>
// The date subfolder matches the date-based organization already used by
// this server's other recycle bin (.recycle/20260622/... etc.), and the
// original relative path is preserved underneath it (same idea as Samba's
// recycle:keeptree) so a file from LOCALSEND/foto.jpg ends up at
// .recycle/www-data/20260622/LOCALSEND/foto.jpg instead of losing its
// folder context.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['recycle'])) {
    $item_rel  = ltrim(preg_replace('/[\x00-\x1F]/', '', $_POST['recycle']), '/');
    $item_full = realpath($base_path . '/' . $item_rel);
    $recycle_root = $base_path . '/.recycle/www-data/' . date('Ymd');

    if ($item_full && strpos($item_full, $base_real . DIRECTORY_SEPARATOR) === 0) {
        // Protect root-level items (files and directories)
        $depth = substr_count(str_replace($base_real, '', $item_full), DIRECTORY_SEPARATOR);
        if ($depth <= 1) {
            $recycle_msg = 'protected';
        } else {
            // keeptree: mirror the item's original subfolder path under
            // today's date folder, e.g. "LOCALSEND/foto.jpg" ->
            // .recycle/www-data/20260622/LOCALSEND/foto.jpg
            $item_parent = dirname($item_rel);
            $dest_dir    = $item_parent === '.' ? $recycle_root : $recycle_root . '/' . $item_parent;
            if (!is_dir($dest_dir)) mkdir($dest_dir, 0775, true);

            $dest = $dest_dir . '/' . basename($item_full);
            if (file_exists($dest)) $dest .= '_' . time();

            if (!rename($item_full, $dest)) {
                $recycle_msg = 'error';
            } else {
                @chgrp($dest, 'www-data');
                @chmod($dest, is_dir($dest) ? 0775 : 0664);
                write_audit('unlinkat', $item_full);
                $recycle_msg = 'recycled';
            }
        }
    } else {
        $recycle_msg = 'error';
    }
    $back = dirname($item_rel) === '.' ? '' : dirname($item_rel);
    header('Location: ?path=' . urlencode($back) . '&msg=' . $recycle_msg);
    exit;
}

$msg = isset($_GET['msg']) ? $_GET['msg'] : '';
$allowed_msgs = ['success', 'partial', 'recycled', 'protected', 'mkdir_success', 'mkdir_error', 'newfile_success', 'newfile_error', 'exists', 'error'];
if (!in_array($msg, $allowed_msgs, true)) $msg = '';

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
$rit = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($full_path, RecursiveDirectoryIterator::SKIP_DOTS),
    RecursiveIteratorIterator::LEAVES_ONLY
);
foreach ($rit as $item) {
    if ($item->isFile()) $total_size += $item->getSize();
}
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

        .header h1 { color: white; font-size: 1.1rem; font-weight: 600; display: flex; align-items: center; gap: 0.5rem; margin: 0 auto; }
        .header-meta { display: none; }

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
        .alert-warning { background: #fef9c3; color: #854d0e; border: 1px solid #fde68a; }

        .mkdir-area {
            display: none;
            padding: 0.75rem 1rem;
            background: #f8f9fa;
            border-bottom: 1px solid #dee2e6;
        }
        .mkdir-area.open { display: block; }
        .mkdir-area form { display: flex; align-items: center; gap: 0.75rem; flex-wrap: wrap; }
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
        .dir-link { color: #374151 !important; font-weight: 500; }
        .dir-link:hover { color: #111827 !important; }

        .muted { color: #64748b; }

        .action-cell { display: flex; gap: 0.4rem; }

        .no-data { text-align: center; padding: 3rem; color: #64748b; font-size: 0.95rem; }

        footer { text-align: center; padding: 1.5rem; font-size: 0.8rem; color: #94a3b8; }
        footer a { color: #94a3b8; text-decoration: none; }
        footer a:hover { color: #2563eb; }
    </style>
</head>
<body>

<div class="header" style="display:flex;justify-content:center;">
    <h1>📁 SMBstack &mdash; Shared Folder</h1>
</div>

<?php if ($msg === 'success'): ?>
<div class="alert alert-success">✅ File uploaded successfully.</div>
<?php elseif (($msg ?? '') === 'partial'): ?>
<div class="alert alert-warning">⚠️ Some files were uploaded, but others failed.</div>
<?php elseif ($msg === 'recycled'): ?>
<div class="alert alert-success">🗑️ Item moved to recycle bin.</div>
<?php elseif ($msg === 'protected'): ?>
<div class="alert alert-error">🔒 Root folders cannot be deleted.</div>
<?php elseif ($msg === 'mkdir_success'): ?>
<div class="alert alert-success">✅ Folder created successfully.</div>
<?php elseif ($msg === 'mkdir_error'): ?>
<div class="alert alert-error">❌ Could not create folder. Check permissions.</div>
<?php elseif ($msg === 'newfile_success'): ?>
<div class="alert alert-success">✅ File created successfully.</div>
<?php elseif ($msg === 'newfile_error'): ?>
<div class="alert alert-error">❌ Could not create file. Check permissions.</div>
<?php elseif ($msg === 'exists'): ?>
<div class="alert alert-error">⚠️ A folder with that name already exists.</div>
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
        <button class="btn btn-success" onclick="document.getElementById('upload-area').classList.toggle('open');document.getElementById('mkdir-area').classList.remove('open');document.getElementById('newfile-area').classList.remove('open')">⬆️ Upload</button>
        <button class="btn btn-secondary" onclick="document.getElementById('mkdir-area').classList.toggle('open');document.getElementById('upload-area').classList.remove('open');document.getElementById('newfile-area').classList.remove('open')">📁 New Folder</button>
        <button class="btn btn-secondary" onclick="document.getElementById('newfile-area').classList.toggle('open');document.getElementById('upload-area').classList.remove('open');document.getElementById('mkdir-area').classList.remove('open')">📄 New File</button>
        <a class="btn btn-secondary" href="/audit/">📊 Audit</a>
    </div>
</div>

<div class="upload-area" id="upload-area">
    <form method="POST" enctype="multipart/form-data">
        <label class="btn btn-secondary" style="cursor:pointer;margin:0">
            📂 Select Files
            <input type="file" name="upload[]" required multiple style="display:none" onchange="
                var n = this.files.length;
                this.parentElement.nextElementSibling.textContent = n === 1
                    ? '✔️ ' + this.files[0].name.substring(0,40)
                    : '✔️ ' + n + ' files selected';
            ">
        </label>
        <span style="color:#6c757d;font-size:0.85rem;flex:1"></span>
        <button type="submit" class="btn btn-success" id="btn-send" onclick="this.disabled=true;this.textContent='⏳ Uploading...';this.form.submit()">⬆️ Send</button>
        <button type="button" class="btn btn-secondary" onclick="document.getElementById('upload-area').classList.remove('open')">✖️ Cancel</button>
    </form>
</div>

<div class="mkdir-area" id="mkdir-area">
    <form method="POST">
        <input type="text" name="mkdir" placeholder="Folder name" required style="flex:1;padding:0.4rem 0.7rem;border-radius:6px;border:1px solid #ced4da;font-size:0.85rem">
        <button type="submit" class="btn btn-secondary">✔️ Create</button>
        <button type="button" class="btn btn-secondary" onclick="document.getElementById('mkdir-area').classList.remove('open')">✖️ Cancel</button>
    </form>
</div>

<div class="mkdir-area" id="newfile-area">
    <form method="POST" style="align-items:flex-start">
        <input type="text" name="newfile" placeholder="File name (e.g. notes.txt)" required style="flex:1;min-width:160px;padding:0.4rem 0.7rem;border-radius:6px;border:1px solid #ced4da;font-size:0.85rem">
        <textarea name="newfile_content" placeholder="Optional content..." rows="2" style="flex:2;min-width:200px;padding:0.4rem 0.7rem;border-radius:6px;border:1px solid #ced4da;font-size:0.85rem;font-family:inherit;resize:vertical"></textarea>
        <button type="submit" class="btn btn-secondary">✔️ Create</button>
        <button type="button" class="btn btn-secondary" onclick="document.getElementById('newfile-area').classList.remove('open')">✖️ Cancel</button>
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
            $dl_url    = '/shared/files/' . implode('/', array_map('rawurlencode', explode('/', ltrim($rel, '/'))));
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
