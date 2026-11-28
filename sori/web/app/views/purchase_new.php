<?php
// New purchase form: header and a fixed number of item rows. The server checks and computes everything again.
// FILE: app/views/purchase_new.php
$o = $old ?? [];
?>
<div class="content-area">
    <a class="btn-small" href="/module/<?= e($mod['id']) ?>"><?= e(t('← Volver a')) ?> <?= e(t($mod['name'])) ?></a>
    <h2><i class="fas <?= e($mod['icon']) ?>"></i> <?= e(t('Nueva compra')) ?></h2>
    <?php if ($error): ?><p class="error"><?= e($error) ?></p><?php endif; ?>

    <form method="post" action="/module/purchases/new">
        <input type="hidden" name="csrf" value="<?= e(csrf()) ?>">
        <div class="form-grid">
            <label><?= e(t('Tipo de compra')) ?>
                <select name="type">
                <?php $type_selected = (string) ($o['type'] ?? ''); foreach ($options['types'] as $x): ?>
                    <option value="<?= e($x['code']) ?>"<?= $x['code'] === $type_selected ? ' selected' : '' ?>><?= e(trim($x['name'])) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label><?= e(t('Fecha')) ?>
                <input type="text" name="date" value="<?= e((string) ($o['date'] ?? date('d/m/Y'))) ?>" maxlength="10" placeholder="dd/mm/aaaa">
            </label>
            <label><?= e(t('Proveedor')) ?>
                <input type="text" name="supplier" value="<?= e((string) ($o['supplier'] ?? '')) ?>" maxlength="20" placeholder="<?= e(t('Documento del proveedor')) ?>">
            </label>
            <label><?= e(t('Factura del proveedor')) ?>
                <input type="text" name="invoice" value="<?= e((string) ($o['invoice'] ?? '')) ?>" maxlength="15">
            </label>
            <label><?= e(t('Forma de pago')) ?>
                <select name="payment">
                <?php $payment_row = (string) ($o['payment'] ?? '1'); foreach ($options['payments'] as $f): ?>
                    <option value="<?= e($f['code']) ?>"<?= $f['code'] === $payment_row ? ' selected' : '' ?>><?= e(trim($f['name'])) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label><?= e(t('Retención en la fuente %')) ?>
                <input type="number" name="withholding_percent" value="<?= e((string) ($o['withholding_percent'] ?? '')) ?>" min="0" max="100" step="any">
            </label>
        </div>

        <h3><?= e(t('Ítems de la compra')) ?></h3>
        <div class="table-wrap">
        <table class="content-table items">
            <thead>
                <tr><th><?= e(t('Código')) ?></th><th><?= e(t('Cantidad')) ?></th><th><?= e(t('Costo unitario (sin IVA)')) ?></th><th><?= e(t('IVA %')) ?></th></tr>
            </thead>
            <tbody>
            <?php for ($i = 0; $i < 8; $i++): ?>
                <tr>
                    <td><input type="text" name="item[]" value="<?= e((string) ($o['item'][$i] ?? '')) ?>" maxlength="20" autocomplete="off"></td>
                    <td><input type="number" name="quantity[]" value="<?= e((string) ($o['quantity'][$i] ?? '')) ?>" min="0" step="any"></td>
                    <td><input type="number" name="value[]" value="<?= e((string) ($o['value'][$i] ?? '')) ?>" min="0" step="any"></td>
                    <td><input type="number" name="vat[]" value="<?= e((string) ($o['vat'][$i] ?? '0')) ?>" min="0" max="100" step="any"></td>
                </tr>
            <?php endfor; ?>
            </tbody>
        </table>
        </div>
        <p class="muted"><?= e(t('Los totales se calculan al guardar.')) ?></p>
        <button type="submit" class="btn-main"><?= e(t('Guardar compra')) ?></button>
    </form>
</div>
