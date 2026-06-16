<?php
// maravento.com
//
////////////////////////////////////////////////////////////////////////////////
//
// index.php
// smbstack - Main Container
// https://github.com/maravento/vault/smbstack
//
////////////////////////////////////////////////////////////////////////////////

$tab = isset($_GET['tab']) ? $_GET['tab'] : 'shared';
$allowed_tabs = ['shared', 'audit'];
if (!in_array($tab, $allowed_tabs)) $tab = 'shared';
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SMBstack</title>
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🗂️</text></svg>" type="image/svg+xml">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }

        html, body {
            height: 100%;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Ubuntu, sans-serif;
            background: #1a2332;
            overflow: hidden;
        }

        /* ── HEADER ── */
        .header {
            background: #2c3e50;
            box-shadow: 0 2px 8px rgba(0,0,0,0.3);
            display: flex;
            flex-direction: column;
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            z-index: 100;
        }

        .header-top {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 0.6rem 1.2rem;
            border-bottom: 1px solid rgba(255,255,255,0.08);
        }

        .header-brand {
            display: flex;
            align-items: center;
            gap: 0.6rem;
            color: white;
            font-size: 1rem;
            font-weight: 700;
            letter-spacing: 0.02em;
        }

        .header-brand span {
            font-size: 1.3rem;
        }

        .header-title {
            color: #a0aec0;
            font-size: 0.85rem;
            font-weight: 400;
        }

        .header-date {
            color: #a0aec0;
            font-size: 0.8rem;
            background: rgba(255,255,255,0.07);
            padding: 0.3rem 0.7rem;
            border-radius: 6px;
        }

        /* ── TABS ── */
        .tabs {
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 0 1rem;
            gap: 0.25rem;
            background: #243447;
        }

        .tab {
            display: flex;
            align-items: center;
            gap: 0.4rem;
            padding: 0.55rem 1.1rem;
            font-size: 0.85rem;
            font-weight: 500;
            color: #8899aa;
            text-decoration: none;
            border-bottom: 3px solid transparent;
            transition: color 0.15s, border-color 0.15s, background 0.15s;
            cursor: pointer;
            white-space: nowrap;
            border-radius: 6px 6px 0 0;
            margin-bottom: -1px;
        }

        .tab:hover {
            color: #cbd5e0;
            background: rgba(255,255,255,0.05);
        }

        .tab.active {
            color: #ffffff;
            border-bottom-color: #f6ad55;
            background: rgba(246,173,85,0.08);
        }

        .tab-icon { font-size: 1rem; }

        /* ── IFRAME ── */
        .frame-container {
            position: fixed;
            top: 88px;
            left: 0;
            right: 0;
            bottom: 0;
        }

        iframe {
            width: 100%;
            height: 100%;
            border: none;
            background: transparent;
        }
    </style>
</head>
<body>

<div class="header">
    <div class="header-top">
        <div class="header-brand">
            <span>🗂️</span> SMBstack
        </div>
        <div class="header-title">Shared Folder &amp; Audit</div>
        <div class="header-date" id="clock"></div>
    </div>
    <div class="tabs">
        <a class="tab <?= $tab === 'shared' ? 'active' : '' ?>" href="?tab=shared">
            <span class="tab-icon">📁</span> Shared
        </a>
        <a class="tab <?= $tab === 'audit' ? 'active' : '' ?>" href="?tab=audit">
            <span class="tab-icon">📊</span> Audit
        </a>
    </div>
</div>

<div class="frame-container">
    <?php if ($tab === 'shared'): ?>
        <iframe src="/shared/" id="frame-shared"></iframe>
    <?php else: ?>
        <iframe src="/audit/" id="frame-audit"></iframe>
    <?php endif; ?>
</div>

<script>
    function updateClock() {
        const now = new Date();
        document.getElementById('clock').textContent =
            now.toISOString().replace('T', ' ').substring(0, 19);
    }
    updateClock();
    setInterval(updateClock, 1000);
</script>

</body>
</html>
