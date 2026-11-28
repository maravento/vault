<?php
// Return to a supplier form: look the purchase up, then choose the quantity to return of each line. The server checks everything again.
// FILE: app/views/purchase_return_new.php
$o = $old ?? [];
$message = null;
if ($purchase) {
    if ($purchase['cancelled'] === 'S') {
        $message = 'La compra está anulada.';
    } elseif (!$lines) {
        $message = 'La compra no tiene ítems.';
    }
}
?>
<div class="content-area">
    <a class="btn-small" href="/module/<?= e($mod['id']) ?>"><?= e(t('← Volver a')) ?> <?= e(t($mod['name'])) ?></a>
    <h2><i class="fas <?= e($mod['icon']) ?>"></i> <?= e(t('Devolución a proveedor')) ?></h2>
    <?php if ($error): ?><p class="error"><?= e($error) ?></p><?php endif; ?>

    <form class="search" method="get" action="/module/purchases/return">
        <select name="t">
        <?php foreach ($options['types'] as $x): ?>
            <option value="<?= e($x['code']) ?>"<?= $x['code'] === $q['t'] ? ' selected' : '' ?>><?= e(trim($x['name'])) ?></option>
        <?php endforeach; ?>
        </select>
        <input type="text" name="n" value="<?= e($q['n']) ?>" placeholder="<?= e(t('Número de compra')) ?>" maxlength="10">
        <button type="submit" class="btn-small"><?= e(t('Buscar compra')) ?></button>
    </form>

    <?php if ($q['t'] !== '' && $q['n'] !== '' && !$purchase): ?>
        <p class="error"><?= e(t('Compra no encontrada.')) ?></p>
    <?php elseif ($purchase): ?>
        <div class="table-wrap">
        <table class="content-table kv">
            <tr><th><?= e(t('Compra')) ?></th><td><?= e(trim($purchase['type']) . '-' . $purchase['number']) ?></td></tr>
            <tr><th><?= e(t('Proveedor')) ?></th><td><?= e($purchase['name']) ?></td></tr>
            <tr><th><?= e(t('Factura del proveedor')) ?></th><td><?= e($purchase['invoice']) ?></td></tr>
            <tr><th><?= e(t('Fecha')) ?></th><td><?= e($purchase['date']) ?></td></tr>
            <tr><th><?= e(t('Total')) ?></th><td><?= e(num((float) $purchase['total'])) ?></td></tr>
        </table>
        </div>

        <?php if ($message): ?>
            <p class="error"><?= e(t($message)) ?></p>
        <?php else: ?>
        <form method="post" action="/module/purchases/return">
            <input type="hidden" name="csrf" value="<?= e(csrf()) ?>">
            <input type="hidden" name="type" value="<?= e($purchase['type']) ?>">
            <input type="hidden" name="number" value="<?= e($purchase['number']) ?>">
            <div class="form-grid">
                <label><?= e(t('Fecha')) ?>
                    <input type="text" name="date" value="<?= e((string) ($o['date'] ?? date('d/m/Y'))) ?>" maxlength="10" placeholder="dd/mm/aaaa">
                </label>
                <label><?= e(t('Forma de pago')) ?>
                    <select name="payment">
                    <?php $payment_row = (string) ($o['payment'] ?? ''); foreach ($options['payments'] as $f): ?>
                        <option value="<?= e($f['code']) ?>"<?= $f['code'] === $payment_row ? ' selected' : '' ?>><?= e(trim($f['name'])) ?></option>
                    <?php endforeach; ?>
                    </select>
                </label>
            </div>
            <div class="table-wrap">
            <table class="content-table">
                <thead><tr>
                    <th><?= e(t('Ítem')) ?></th><th><?= e(t('Comprado')) ?></th><th><?= e(t('Devuelto')) ?></th><th><?= e(t('Cantidad a devolver')) ?></th>
                </tr></thead>
                <tbody>
                <?php foreach ($lines as $l): ?>
                    <tr>
                        <td><?= e(trim((string) $l['item_code']) . ' ' . trim((string) $l['name'])) ?></td>
                        <td><?= e(num((float) $l['qty'])) ?></td>
                        <td><?= e(num((float) $l['returned'])) ?></td>
                        <td><input type="number" name="quantity[<?= e(trim((string) $l['line_no'])) ?>]" value="<?= e((string) ($o['quantity'][trim((string) $l['line_no'])] ?? '')) ?>" min="0" step="any"></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
            </div>
            <button type="submit" class="btn-main"><?= e(t('Guardar devolución')) ?></button>
        </form>
        <?php endif; ?>
    <?php endif; ?>
</div>
