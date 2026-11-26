<?php
// Generic detail: one record with its resolved names, every filled field and its child rows
// FILE: app/views/detalle.php
$pk = $vista['pk'];
$vals = [];
foreach ($pk as $i => $_) {
    $vals[] = (string) ($_GET["k$i"] ?? '');
}

$sel = ["{$vista['alias']}.*"];
foreach ($vista['cols'] as $i => $c) {
    $sel[] = "{$c[1]} AS c$i";
}
$where = implode(' AND ', array_map(static fn($k) => "{$vista['alias']}.$k = ?", $pk));
$st = tenant()->prepare('SELECT ' . implode(', ', $sel) . " FROM {$vista['from']} WHERE $where LIMIT 1");
$st->execute($vals);
$row = $st->fetch();
if (!$row) {
    fail(404, 'Not found');
}

$titulo = preg_replace_callback('/\{(\w+)\}/', static fn($m) => trim((string) ($row[$m[1]] ?? '')), t($vista['titulo']));
$todos = isset($_GET['todos']);
$limite = setting('DETAIL_ROWS_LIMIT', 500);
?>
<div class="content-area">
    <a class="btn-small" href="/modulo/<?= e($mod['id']) ?>"><?= e(t('← Volver a')) ?> <?= e(t($mod['nombre'])) ?></a>
    <h2><i class="fas <?= e($mod['icono']) ?>"></i> <?= e($titulo) ?></h2>

    <div class="table-wrap">
    <table class="content-table kv">
        <?php foreach ($vista['cols'] as $i => $c): ?>
            <tr><th><?= e(t($c[0])) ?></th><td><?= e(fmt($row["c$i"], $c[2] ?? 'text')) ?></td></tr>
        <?php endforeach; ?>
    </table>
    </div>

    <?php
    // A field that holds a list of codes is shown as a table, with a description when it is known
    $lista = $vista['lista'] ?? null;
    if ($lista):
        $codigos = array_values(array_filter(array_map('trim', explode($lista['separador'], (string) ($row[$lista['campo']] ?? ''))), 'strlen'));
    ?>
    <h3><?= e(t($lista['titulo'])) ?> <span class="muted">(<?= count($codigos) ?>)</span></h3>
    <?php if (!empty($lista['nota'])): ?><p class="muted"><?= e(t($lista['nota'])) ?></p><?php endif; ?>
    <div class="table-wrap">
    <table class="content-table">
        <thead><tr><th>#</th><th><?= e(t('Código')) ?></th><th><?= e(t('Descripción')) ?></th></tr></thead>
        <tbody>
        <?php foreach ($codigos as $i => $cod): ?>
            <tr><td class="num"><?= $i + 1 ?></td><td><?= e($cod) ?></td><td><?= e(t($lista['nombres'][$cod] ?? '')) ?></td></tr>
        <?php endforeach; ?>
        </tbody>
    </table>
    </div>
    <?php endif; ?>

    <?php foreach ($vista['hijos'] ?? [] as $h):
        $cond = [];
        $args = [];
        foreach ($h['where'] as $hc => $pc) {
            $cond[] = "$hc = ?";
            $args[] = (string) ($row[$pc] ?? '');
        }
        $hsel = [];
        foreach ($h['cols'] as $i => $c) {
            $hsel[] = "{$c[1]} AS c$i";
        }
        $st = tenant()->prepare('SELECT ' . implode(', ', $hsel) . " FROM {$h['from']} WHERE " . implode(' AND ', $cond)
            . " ORDER BY {$h['order']} LIMIT $limite");
        $st->execute($args);
        $hrows = $st->fetchAll();
    ?>
    <h3><?= e(t($h['titulo'])) ?> <span class="muted">(<?= count($hrows) ?><?= count($hrows) === $limite ? ', ' . str_replace('{n}', (string) $limite, t('primeros {n}')) : '' ?>)</span></h3>
    <div class="table-wrap">
    <table class="content-table">
        <thead><tr><?php foreach ($h['cols'] as $c): ?><th><?= e(t($c[0])) ?></th><?php endforeach; ?></tr></thead>
        <tbody>
        <?php foreach ($hrows as $r): ?>
            <tr>
            <?php foreach ($h['cols'] as $i => $c): $tipo = $c[2] ?? 'text'; ?>
                <td<?= $tipo === 'money' ? ' class="num"' : '' ?>><?= e(fmt($r["c$i"], $tipo)) ?></td>
            <?php endforeach; ?>
            </tr>
        <?php endforeach; ?>
        <?php if (!$hrows): ?>
            <tr><td colspan="<?= count($h['cols']) ?>"><?= e(t('Sin registros.')) ?></td></tr>
        <?php endif; ?>
        </tbody>
    </table>
    </div>
    <?php endforeach; ?>

    <?php
    // Fields not already in the summary above: those that are a plain column of the main table
    $mostrados = $lista ? [$lista['campo'] => true] : [];
    foreach ($vista['cols'] as $c) {
        if (preg_match('/^' . preg_quote($vista['alias'], '/') . '\.(\w+)$/', $c[1], $m)) {
            $mostrados[$m[1]] = true;
        }
    }
    $extra = [];
    $vacios = 0;
    foreach ($row as $col => $v) {
        if (preg_match('/^c\d+$/', $col) || isset($mostrados[$col])) {
            continue;
        }
        if (trim((string) $v) === '') {
            $vacios++;
            if (!$todos) {
                continue;
            }
        }
        $extra[$col] = (string) $v;
    }
    $base = $_GET;
    unset($base['todos']);
    ?>
    <?php if ($extra): ?>
    <h3><?= e(t('Otros campos')) ?>
        <?php if ($vacios): ?>
        <a class="btn-small" href="?<?= e(http_build_query($todos ? $base : $base + ['todos' => 1])) ?>"><?= e(t($todos ? 'Ocultar vacíos' : 'Mostrar vacíos')) ?></a>
        <?php endif; ?>
    </h3>
    <div class="table-wrap">
    <table class="content-table kv">
        <?php foreach ($extra as $col => $v): ?>
            <tr><th><?= e(etiqueta($col)) ?></th><td><?= e($v) ?></td></tr>
        <?php endforeach; ?>
    </table>
    </div>
    <?php endif; ?>
</div>
