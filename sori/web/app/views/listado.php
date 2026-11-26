<?php
// Generic list: search and pages over the main table of a module
// FILE: app/views/listado.php
$q = trim((string) ($_GET['q'] ?? ''));
$page = max(1, (int) ($_GET['p'] ?? 1));
$per = 50;
$off = ($page - 1) * $per;
$pk = $vista['pk'] ?? [];

$conds = [];
$args = [];
if ($q !== '' && $vista['search']) {
    $like = '%' . addcslashes($q, '%_\\') . '%';
    $conds[] = '(' . implode(' OR ', array_map(static fn($e) => "$e LIKE ?", $vista['search'])) . ')';
    $args = array_fill(0, count($vista['search']), $like);
}
// Optional filter chosen from a fixed list; its SQL comes from the view definition
$filtro = $vista['filtro'] ?? null;
$f = (string) ($_GET['f'] ?? '');
if ($filtro && isset($filtro['opciones'][$f])) {
    $conds[] = $filtro['opciones'][$f][1];
} else {
    $f = '';
}
$where = $conds ? 'WHERE ' . implode(' AND ', $conds) : '';

$st = tenant()->prepare("SELECT COUNT(*) FROM {$vista['from']} $where");
$st->execute($args);
$total = (int) $st->fetchColumn();
$pages = max(1, (int) ceil($total / $per));

$sel = [];
foreach ($vista['cols'] as $i => $c) {
    $sel[] = "{$c[1]} AS c$i";
}
foreach ($pk as $i => $k) {
    $sel[] = "{$vista['alias']}.$k AS k$i";
}
$st = tenant()->prepare('SELECT ' . implode(', ', $sel) . " FROM {$vista['from']} $where ORDER BY {$vista['order']} LIMIT $per OFFSET $off");
$st->execute($args);
$rows = $st->fetchAll();
$qs = ($q === '' ? '' : '&q=' . urlencode($q)) . ($f === '' ? '' : '&f=' . urlencode($f));
?>
<div class="content-area">
    <a class="btn-small" href="/"><?= e(t('← Volver')) ?></a>
    <h2><i class="fas <?= e($mod['icono']) ?>"></i> <?= e(t($mod['nombre'])) ?></h2>
    <?php if (!empty($vista['nota'])): ?>
        <p class="muted"><?= e(t($vista['nota'])) ?></p>
    <?php endif; ?>

    <?php if ($vista['search']): ?>
    <form class="search" method="get" action="/modulo/<?= e($mod['id']) ?>">
        <?php if ($filtro): ?>
        <select name="f">
            <option value=""><?= e(t('Todos')) ?></option>
            <?php foreach ($filtro['opciones'] as $valor => $op): ?>
                <option value="<?= e((string) $valor) ?>"<?= (string) $valor === $f ? ' selected' : '' ?>><?= e(t($op[0])) ?></option>
            <?php endforeach; ?>
        </select>
        <?php endif; ?>
        <input type="text" name="q" value="<?= e($q) ?>" placeholder="<?= e(t('Buscar')) ?>" maxlength="60">
        <button type="submit" class="btn-small"><?= e(t('Buscar')) ?></button>
    </form>
    <?php endif; ?>

    <div class="table-wrap">
    <table class="content-table">
        <thead>
            <tr>
                <?php foreach ($vista['cols'] as $c): ?>
                    <th><?= e(t($c[0])) ?></th>
                <?php endforeach; ?>
                <?php if ($pk): ?><th></th><?php endif; ?>
            </tr>
        </thead>
        <tbody>
        <?php foreach ($rows as $r): ?>
            <tr>
                <?php foreach ($vista['cols'] as $i => $c): $tipo = $c[2] ?? 'text'; ?>
                    <td<?= $tipo === 'money' ? ' class="num"' : '' ?>><?= e(fmt($r["c$i"], $tipo)) ?></td>
                <?php endforeach; ?>
                <?php if ($pk):
                    $keys = [];
                    foreach ($pk as $i => $_) {
                        $keys["k$i"] = $r["k$i"];
                    } ?>
                    <td><a class="btn-small" href="/modulo/<?= e($mod['id']) ?>/ver?<?= e(http_build_query($keys)) ?>"><?= e(t('Ver')) ?></a></td>
                <?php endif; ?>
            </tr>
        <?php endforeach; ?>
        <?php if (!$rows): ?>
            <tr><td colspan="<?= count($vista['cols']) + ($pk ? 1 : 0) ?>"><?= e(t('Sin resultados.')) ?></td></tr>
        <?php endif; ?>
        </tbody>
    </table>
    </div>

    <p class="pager">
        <?= num($total) ?> <?= e(t('registros')) ?> · <?= e(t('página')) ?> <?= $page ?> <?= e(t('de')) ?> <?= $pages ?>
        <?php if ($page > 1): ?> <a class="btn-small" href="?p=<?= $page - 1 . e($qs) ?>"><?= e(t('‹ Anterior')) ?></a><?php endif; ?>
        <?php if ($page < $pages): ?> <a class="btn-small" href="?p=<?= $page + 1 . e($qs) ?>"><?= e(t('Siguiente ›')) ?></a><?php endif; ?>
    </p>
</div>
