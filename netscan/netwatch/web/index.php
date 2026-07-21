<?php
// maravento.com
//
////////////////////////////////////////////////////////////////////////////////
//
// index.php
// netwatch - Main Container
// https://github.com/maravento/vault
//
////////////////////////////////////////////////////////////////////////////////

// $tab must always be validated against $allowed_tabs before being echoed into
// the href/class attributes below; any new tab value added here must also be
// added to $allowed_tabs.
$tab = isset($_GET['tab']) ? $_GET['tab'] : 'lan';
$allowed_tabs = ['lan', 'ports'];
if (!in_array($tab, $allowed_tabs)) $tab = 'lan';
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NetWatch</title>
    <meta name="color-scheme" content="dark">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🌐</text></svg>" type="image/svg+xml">
    <script>
        // Applied before first paint to avoid a flash of the wrong theme.
        (function() {
            var t = localStorage.getItem('netwatch-theme') || 'dark';
            document.documentElement.setAttribute('data-theme', t);
        })();
    </script>
    <style>
        /* The top bar (brand + tabs) is intentionally NOT themed — it stays
           this fixed dark palette regardless of the light/dark toggle,
           which only affects the LAN/Ports content in the iframe below.
           No [data-theme="light"] override here on purpose. */
        :root {
            color-scheme: dark;
            --bg-primary: #1a2332;
            --bg-header: #2c3e50;
            --bg-panel-alt: #243447;
            --border: rgba(255,255,255,0.08);
            --border-soft: rgba(255,255,255,0.06);
            --text-primary: #ffffff;
            --text-secondary: #a0aec0;
            --text-tab: #8899aa;
            --text-tab-hover: #cbd5e0;
            --accent: #48bb78;
            --accent-soft: rgba(72,187,120,0.08);
            --pill-bg: rgba(255,255,255,0.07);
        }

        * { margin: 0; padding: 0; box-sizing: border-box; }

        html, body {
            height: 100%;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Ubuntu, sans-serif;
            background: var(--bg-primary);
            overflow: hidden;
        }

        /* ── HEADER ── */
        .header {
            background: var(--bg-header);
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
            border-bottom: 1px solid var(--border);
            gap: 0.8rem;
        }

        .header-brand {
            display: flex;
            align-items: center;
            gap: 0.6rem;
            color: var(--text-primary);
            font-size: 1rem;
            font-weight: 700;
            letter-spacing: 0.02em;
            text-decoration: none;
        }

        .header-brand:hover {
            color: var(--text-primary);
            text-decoration: underline;
        }

        .header-brand span {
            font-size: 1.3rem;
        }

        .header-title {
            color: var(--text-secondary);
            font-size: 0.85rem;
            font-weight: 400;
            flex: 1;
        }

        .header-right {
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }

        .header-date {
            color: var(--text-secondary);
            font-size: 0.8rem;
            background: var(--pill-bg);
            padding: 0.3rem 0.7rem;
            border-radius: 6px;
        }

        .theme-toggle {
            color: var(--text-secondary);
            background: var(--pill-bg);
            border: none;
            font-size: 0.9rem;
            padding: 0.3rem 0.6rem;
            border-radius: 6px;
            cursor: pointer;
            line-height: 1;
        }

        .theme-toggle:hover {
            color: var(--text-primary);
        }

        /* ── TABS ── */
        .tabs {
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 0 1rem;
            gap: 0.25rem;
            background: var(--bg-panel-alt);
        }

        .tab {
            display: flex;
            align-items: center;
            gap: 0.4rem;
            padding: 0.55rem 1.1rem;
            font-size: 0.85rem;
            font-weight: 500;
            color: var(--text-tab);
            text-decoration: none;
            border-bottom: 3px solid transparent;
            transition: color 0.15s, border-color 0.15s, background 0.15s;
            cursor: pointer;
            white-space: nowrap;
            border-radius: 6px 6px 0 0;
            margin-bottom: -1px;
        }

        .tab:hover {
            color: var(--text-tab-hover);
            background: var(--border-soft);
        }

        .tab.active {
            color: var(--text-primary);
            border-bottom-color: var(--accent);
            background: var(--accent-soft);
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
        <a class="header-brand" href="https://github.com/maravento/vault/tree/master/netscan" target="_blank" rel="noopener noreferrer">
            <span>🌐</span> NetWatch
        </a>
        <div class="header-title">LAN Devices &amp; Watched Ports</div>
        <div class="header-right">
            <button class="theme-toggle" id="themeToggle" title="Toggle light/dark theme" aria-label="Toggle light/dark theme">🌙</button>
            <div class="header-date" id="clock"></div>
        </div>
    </div>
    <div class="tabs">
        <a class="tab <?= $tab === 'lan' ? 'active' : '' ?>" href="?tab=lan">
            <span class="tab-icon">🌐</span> LAN
        </a>
        <a class="tab <?= $tab === 'ports' ? 'active' : '' ?>" href="?tab=ports">
            <span class="tab-icon">🔌</span> Ports
        </a>
    </div>
</div>

<div class="frame-container">
    <?php if ($tab === 'lan'): ?>
        <iframe src="/lan/" id="frame-lan"></iframe>
    <?php else: ?>
        <iframe src="/ports/" id="frame-ports"></iframe>
    <?php endif; ?>
</div>

<script>
    function updateClock() {
        // Local time, not toISOString() (which is always UTC and reads
        // hours ahead/behind the system clock outside UTC timezones).
        const now = new Date();
        const pad = n => String(n).padStart(2, '0');
        document.getElementById('clock').textContent =
            `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
    }
    updateClock();
    setInterval(updateClock, 1000);

    function currentTheme() {
        return localStorage.getItem('netwatch-theme') || 'dark';
    }

    function applyTheme(theme) {
        document.documentElement.setAttribute('data-theme', theme);
        localStorage.setItem('netwatch-theme', theme);
        document.getElementById('themeToggle').textContent = theme === 'dark' ? '🌙' : '☀️';
        // Propagate to the currently visible iframe — it's a separate
        // same-origin document, so it won't pick up localStorage changes
        // until its own load-time script runs (i.e. on next navigation).
        const iframe = document.querySelector('.frame-container iframe');
        if (iframe) {
            try {
                iframe.contentDocument.documentElement.setAttribute('data-theme', theme);
            } catch (e) { /* cross-origin or not yet loaded, ignore */ }
        }
    }

    applyTheme(currentTheme());
    document.getElementById('themeToggle').addEventListener('click', () => {
        applyTheme(currentTheme() === 'dark' ? 'light' : 'dark');
    });
</script>

</body>
</html>
