<?php
// Home: module grid with one tab per business area.
// FILE: app/views/home.php
$sheets = [
    'catalogos'    => ['Catálogos', []],
    'ventas'       => ['Ventas', []],
    'almacen'      => ['Almacén', []],
    'tesoreria'    => ['Tesorería', []],
    'contabilidad' => ['Contabilidad', []],
    'personal'     => ['Personal', []],
    'servicios'    => ['Servicios', []],
];
foreach ($modules as $mod) {
    $sheets[$mod['grupo']][1][] = $mod;
}
?>
<div class="tabs">
    <?php $first = true; foreach ($sheets as $key => [$label, $list]): ?>
        <button type="button" class="tab-btn<?= $first ? ' active' : '' ?>" data-tab="tab-<?= e($key) ?>">
            <?= e(t($label)) ?> <span class="tab-n"><?= count($list) ?></span>
        </button>
    <?php $first = false; endforeach; ?>
</div>

<?php $first = true; foreach ($sheets as $key => [$label, $list]): ?>
<div class="tab-panel" id="tab-<?= e($key) ?>"<?= $first ? '' : ' hidden' ?>>
    <div class="grid-buttons">
        <?php foreach ($list as $mod): $n = $count($mod['tabla']); ?>
        <a class="menu-btn" href="/modulo/<?= e($mod['id']) ?>">
            <i class="fas <?= e($mod['icono']) ?>"></i>
            <span><?= e(t($mod['nombre'])) ?></span>
            <small><?= $n === null ? e(t('sin datos')) : num($n) . ' ' . e(t('registros')) ?></small>
        </a>
        <?php endforeach; ?>
    </div>
</div>
<?php $first = false; endforeach; ?>
