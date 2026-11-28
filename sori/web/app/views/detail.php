<?php
// Generic detail: one record with its resolved names, every filled field and its child rows
// FILE: app/views/detail.php
$pk = $screen['pk'];
$vals = [];
foreach ($pk as $i => $_) {
    $vals[] = (string) ($_GET["k$i"] ?? '');
}

$sel = ["{$screen['alias']}.*"];
foreach ($screen['cols'] as $i => $c) {
    $sel[] = "{$c[1]} AS c$i";
}
$where = implode(' AND ', array_map(static fn($k) => "{$screen['alias']}.$k = ?", $pk));
$st = tenant()->prepare('SELECT ' . implode(', ', $sel) . " FROM {$screen['from']} WHERE $where LIMIT 1");
$st->execute($vals);
$row = $st->fetch();
if (!$row) {
    fail(404, 'Not found');
}

$title = preg_replace_callback('/\{(\w+)\}/', static fn($m) => trim((string) ($row[$m[1]] ?? '')), t($screen['title']));
$all_rows = isset($_GET['all_rows']);
$row_limit = setting('DETAIL_ROWS_LIMIT', 500);
?>
<div class="content-area">
    <a class="btn-small" href="/module/<?= e($mod['id']) ?>"><?= e(t('← Volver a')) ?> <?= e(t($mod['name'])) ?></a>
    <h2><i class="fas <?= e($mod['icon']) ?>"></i> <?= e($title) ?></h2>

    <?php $cancel_cfg = $screen['cancel_cfg'] ?? null; if ($cancel_cfg): ?>
        <?php if (trim((string) ($row[$cancel_cfg['field']] ?? '')) === 'S'): ?>
            <p class="notice"><i class="fas fa-ban"></i> <?= e(t($cancel_cfg['cancelled'])) ?></p>
        <?php elseif (can_write()): ?>
            <form method="post" action="<?= e($cancel_cfg['route']) ?>" data-confirm="<?= e(t($cancel_cfg['confirm'])) ?>">
                <input type="hidden" name="csrf" value="<?= e(csrf()) ?>">
                <?php foreach ($pk as $i => $_): ?>
                    <input type="hidden" name="k<?= $i ?>" value="<?= e($vals[$i]) ?>">
                <?php endforeach; ?>
                <button type="submit" class="btn-small"><i class="fas fa-ban"></i> <?= e(t($cancel_cfg['text'])) ?></button>
            </form>
            <?php if (!empty($cancel_cfg['receive'])): ?>
                <p><a class="btn-small" href="<?= e($cancel_cfg['receive']['route'] . '?' . http_build_query(['p' => $vals[1] ?? '', 'n' => $vals[2] ?? ''])) ?>"><i class="fas fa-hand-holding-dollar"></i> <?= e(t($cancel_cfg['receive']['text'])) ?></a></p>
            <?php endif; ?>
            <?php if (!empty($cancel_cfg['return_cfg'])): ?>
                <p><a class="btn-small" href="<?= e($cancel_cfg['return_cfg']['route'] . '?' . http_build_query(['p' => $vals[1] ?? '', 'n' => $vals[2] ?? ''])) ?>"><i class="fas fa-rotate-left"></i> <?= e(t($cancel_cfg['return_cfg']['text'])) ?></a></p>
            <?php endif; ?>
        <?php endif; ?>
    <?php endif; ?>

    <?php $edit_link = $screen['edit_cfg'] ?? null; if ($edit_link && can_write()): ?>
        <p><a class="btn-small" href="<?= e($edit_link['route'] . '?' . http_build_query(array_combine(array_map(static fn($i) => "k$i", array_keys($pk)), array_map(static fn($i) => $vals[$i] ?? '', array_keys($pk))))) ?>"><i class="fas fa-pen"></i> <?= e(t($edit_link['text'])) ?></a></p>
    <?php endif; ?>

    <?php $return_link = $screen['return_cfg'] ?? null; if ($return_link && can_write()): ?>
        <p><a class="btn-small" href="<?= e($return_link['route'] . '?' . http_build_query(['t' => $vals[2] ?? '', 'n' => $vals[3] ?? ''])) ?>"><i class="fas fa-rotate-left"></i> <?= e(t($return_link['text'])) ?></a></p>
    <?php endif; ?>

    <?php $pay_cfg = $screen['pay'] ?? null; if ($pay_cfg && can_write()): ?>
        <p><a class="btn-small" href="<?= e($pay_cfg['route'] . '?' . http_build_query(['y' => $vals[1] ?? '', 't' => $vals[2] ?? '', 'n' => $vals[3] ?? ''])) ?>"><i class="fas fa-hand-holding-dollar"></i> <?= e(t($pay_cfg['text'])) ?></a></p>
    <?php endif; ?>

    <div class="table-wrap">
    <table class="content-table kv">
        <?php foreach ($screen['cols'] as $i => $c): ?>
            <tr><th><?= e(t($c[0])) ?></th><td><?= e(fmt($row["c$i"], $c[2] ?? 'text')) ?></td></tr>
        <?php endforeach; ?>
    </table>
    </div>

    <?php
    // A field that holds a list of codes is shown as a table, with a description when it is known
    $price_list = $screen['price_list'] ?? null;
    if ($price_list):
        $codes = array_values(array_filter(array_map('trim', explode($price_list['separator'], (string) ($row[$price_list['field']] ?? ''))), 'strlen'));
    ?>
    <h3><?= e(t($price_list['title'])) ?> <span class="muted">(<?= count($codes) ?>)</span></h3>
    <?php if (!empty($price_list['note'])): ?><p class="muted"><?= e(t($price_list['note'])) ?></p><?php endif; ?>
    <div class="table-wrap">
    <table class="content-table">
        <thead><tr><th>#</th><th><?= e(t('Código')) ?></th><th><?= e(t('Descripción')) ?></th></tr></thead>
        <tbody>
        <?php foreach ($codes as $i => $item_code): ?>
            <tr><td class="num"><?= $i + 1 ?></td><td><?= e($item_code) ?></td><td><?= e(t($price_list['names'][$item_code] ?? '')) ?></td></tr>
        <?php endforeach; ?>
        </tbody>
    </table>
    </div>
    <?php endif; ?>

    <?php foreach ($screen['children'] ?? [] as $h):
        $cond = [];
        $args = [];
        foreach ($h['where'] as $child_col => $pc) {
            $cond[] = "$child_col = ?";
            $args[] = (string) ($row[$pc] ?? '');
        }
        $child_select = [];
        foreach ($h['cols'] as $i => $c) {
            $child_select[] = "{$c[1]} AS c$i";
        }
        $st = tenant()->prepare('SELECT ' . implode(', ', $child_select) . " FROM {$h['from']} WHERE " . implode(' AND ', $cond)
            . " ORDER BY {$h['order']} LIMIT $row_limit");
        $st->execute($args);
        $child_rows = $st->fetchAll();
    ?>
    <h3><?= e(t($h['title'])) ?> <span class="muted">(<?= count($child_rows) ?><?= count($child_rows) === $row_limit ? ', ' . str_replace('{n}', (string) $row_limit, t('primeros {n}')) : '' ?>)</span></h3>
    <div class="table-wrap">
    <table class="content-table">
        <thead><tr><?php foreach ($h['cols'] as $c): ?><th><?= e(t($c[0])) ?></th><?php endforeach; ?></tr></thead>
        <tbody>
        <?php foreach ($child_rows as $r): ?>
            <tr>
            <?php foreach ($h['cols'] as $i => $c): $type = $c[2] ?? 'text'; ?>
                <td<?= $type === 'money' ? ' class="num"' : '' ?>><?= e(fmt($r["c$i"], $type)) ?></td>
            <?php endforeach; ?>
            </tr>
        <?php endforeach; ?>
        <?php if (!$child_rows): ?>
            <tr><td colspan="<?= count($h['cols']) ?>"><?= e(t('Sin registros.')) ?></td></tr>
        <?php endif; ?>
        </tbody>
    </table>
    </div>
    <?php endforeach; ?>

    <?php
    // Fields not already in the summary above: those that are a plain column of the main table
    $shown = $price_list ? [$price_list['field'] => true] : [];
    foreach ($screen['cols'] as $c) {
        if (preg_match('/^' . preg_quote($screen['alias'], '/') . '\.(\w+)$/', $c[1], $m)) {
            $shown[$m[1]] = true;
        }
    }
    $extra = [];
    $empty_rows = 0;
    foreach ($row as $col => $v) {
        if (preg_match('/^c\d+$/', $col) || isset($shown[$col])) {
            continue;
        }
        if (trim((string) $v) === '') {
            $empty_rows++;
            if (!$all_rows) {
                continue;
            }
        }
        $extra[$col] = (string) $v;
    }
    $base = $_GET;
    unset($base['all_rows']);
    ?>
    <?php if ($extra): ?>
    <h3><?= e(t('Otros campos')) ?>
        <?php if ($empty_rows): ?>
        <a class="btn-small" href="?<?= e(http_build_query($all_rows ? $base : $base + ['all_rows' => 1])) ?>"><?= e(t($all_rows ? 'Ocultar vacíos' : 'Mostrar vacíos')) ?></a>
        <?php endif; ?>
    </h3>
    <div class="table-wrap">
    <table class="content-table kv">
        <?php foreach ($extra as $col => $v): ?>
            <tr><th><?= e(label($col)) ?></th><td><?= e($v) ?></td></tr>
        <?php endforeach; ?>
    </table>
    </div>
    <?php endif; ?>
</div>
