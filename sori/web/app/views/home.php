<?php
// Home: module grid with one tab per business area.
// FILE: app/views/home.php
$sheets = [
    'catalogs'    => ['Catálogos', []],
    'sales'       => ['Ventas', []],
    'warehouse'      => ['Almacén', []],
    'treasury'    => ['Tesorería', []],
    'accounting' => ['Contabilidad', []],
    'staff'     => ['Personal', []],
    'services'    => ['Servicios', []],
];
foreach ($modules as $mod) {
    $sheets[$mod['group']][1][] = $mod;
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
        <?php foreach ($list as $mod): $n = $count($mod['table']); ?>
        <a class="menu-btn" href="/module/<?= e($mod['id']) ?>">
            <i class="fas <?= e($mod['icon']) ?>"></i>
            <span><?= e(t($mod['name'])) ?></span>
            <small><?= $n === null ? e(t('sin datos')) : num($n) . ' ' . e(t('registros')) ?></small>
        </a>
        <?php endforeach; ?>
    </div>
</div>
<?php $first = false; endforeach; ?>
