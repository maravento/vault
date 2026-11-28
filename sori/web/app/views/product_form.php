<?php
// Product form, for a new record and for an edit. The browser only helps to fill it: the server checks everything again.
// $edit is true when the record exists: its code and type cannot change.
// FILE: app/views/product_form.php
$o = $old ?? [];
$v = static fn(string $k, string $def = ''): string => (string) ($o[$k] ?? $def);
$checked = static fn(string $k, bool $def): bool => isset($o[$k]) ? $o[$k] === 'S' : $def;
$route = $edit ? '/module/products/edit' : '/module/products/new';
$prices = (array) ($o['price'] ?? []);
?>
<div class="content-area">
    <a class="btn-small" href="/module/<?= e($mod['id']) ?>"><?= e(t('← Volver a')) ?> <?= e(t($mod['name'])) ?></a>
    <h2><i class="fas <?= e($mod['icon']) ?>"></i> <?= e(t($edit ? 'Editar producto' : 'Nuevo producto')) ?></h2>
    <?php if ($error): ?><p class="error"><?= e($error) ?></p><?php endif; ?>

    <form method="post" action="<?= e($route) ?>">
        <input type="hidden" name="csrf" value="<?= e(csrf()) ?>">
        <div class="form-grid">
            <label><?= e(t('Código')) ?>
                <?php if ($edit): ?>
                    <input type="hidden" name="code" value="<?= e($v('code')) ?>">
                    <input type="text" value="<?= e($v('code')) ?>" readonly>
                <?php else: ?>
                    <input type="text" name="code" value="<?= e($v('code')) ?>" maxlength="20">
                <?php endif; ?>
            </label>
            <label><?= e(t('Tipo')) ?>
                <?php if ($edit): ?>
                    <input type="hidden" name="type" value="<?= e($v('type')) ?>">
                    <input type="text" value="<?= e(t($v('type') === '2' ? 'Servicio' : 'Almacén')) ?>" readonly>
                <?php else: ?>
                    <select name="type">
                        <?php $type_selected = $v('type', '1'); foreach (['1' => 'Almacén', '2' => 'Servicio'] as $k => $n): ?>
                        <option value="<?= e($k) ?>"<?= $k === $type_selected ? ' selected' : '' ?>><?= e(t($n)) ?></option>
                        <?php endforeach; ?>
                    </select>
                <?php endif; ?>
            </label>
            <label class="wide"><?= e(t('Nombre')) ?>
                <input type="text" name="name" value="<?= e($v('name')) ?>" maxlength="255">
            </label>
            <label><?= e(t('Grupo contable')) ?>
                <select name="group">
                <?php $group_selected = $v('group'); foreach ($options['groups'] as $x): ?>
                    <option value="<?= e($x['code']) ?>"<?= $x['code'] === $group_selected ? ' selected' : '' ?>><?= e(trim($x['name'])) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label><?= e(t('Impuesto')) ?>
                <select name="vat_type">
                <?php $vat_type_selected = $v('vat_type', '0'); foreach ($options['vat_types'] as $x): ?>
                    <option value="<?= e($x['code']) ?>"<?= $x['code'] === $vat_type_selected ? ' selected' : '' ?>><?= e(trim($x['name'])) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label><?= e(t('IVA %')) ?>
                <input type="number" name="vat_percent" value="<?= e($v('vat_percent', '19')) ?>" min="0" max="100" step="any">
            </label>
        </div>
        <h3><?= e(t('Precios (IVA incluido)')) ?></h3>
        <div class="form-grid">
            <?php foreach (PRICE_LISTS as $price_list): ?>
            <label><?= e(t('Lista')) ?> <?= e($price_list) ?>
                <input type="number" name="price[<?= e($price_list) ?>]" value="<?= e((string) ($prices[$price_list] ?? '')) ?>" min="0" step="any">
            </label>
            <?php endforeach; ?>
        </div>
        <fieldset>
            <label class="check"><input type="checkbox" name="active" value="S"<?= $checked('active', true) ? ' checked' : '' ?>> <?= e(t('Activo')) ?></label>
            <label class="check"><input type="checkbox" name="free_price" value="S"<?= $checked('free_price', false) ? ' checked' : '' ?>> <?= e(t('El precio se puede cambiar al facturar')) ?></label>
            <label class="check"><input type="checkbox" name="allows_discount" value="S"<?= $checked('allows_discount', false) ? ' checked' : '' ?>> <?= e(t('Permite descuento')) ?></label>
        </fieldset>
        <button type="submit" class="btn-main"><?= e(t('Guardar producto')) ?></button>
    </form>
</div>
