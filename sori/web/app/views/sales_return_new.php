<?php
// Customer return form: look the invoice up, then choose the quantity to return of each line. The server checks everything again.
// FILE: app/views/sales_return_new.php
$o = $old ?? [];
$message = null;
if ($invoice) {
    if ($invoice['cancelled_flag'] === 'S') {
        $message = 'La factura está anulada.';
    } elseif (!$lines) {
        $message = 'La factura no tiene ítems.';
    }
}
?>
<div class="content-area">
    <a class="btn-small" href="/module/<?= e($mod['id']) ?>"><?= e(t('← Volver a')) ?> <?= e(t($mod['name'])) ?></a>
    <h2><i class="fas <?= e($mod['icon']) ?>"></i> <?= e(t('Devolución de cliente')) ?></h2>
    <?php if ($error): ?><p class="error"><?= e($error) ?></p><?php endif; ?>

    <form class="search" method="get" action="/module/invoices/return">
        <input type="text" name="p" value="<?= e($q['p']) ?>" placeholder="<?= e(t('Prefijo')) ?>" maxlength="5">
        <input type="text" name="n" value="<?= e($q['n']) ?>" placeholder="<?= e(t('Número de factura')) ?>" maxlength="10">
        <button type="submit" class="btn-small"><?= e(t('Buscar factura')) ?></button>
    </form>

    <?php if ($q['p'] !== '' && $q['n'] !== '' && !$invoice): ?>
        <p class="error"><?= e(t('Factura no encontrada.')) ?></p>
    <?php elseif ($invoice): ?>
        <div class="table-wrap">
        <table class="content-table kv">
            <tr><th><?= e(t('Factura')) ?></th><td><?= e(trim($invoice['prefix']) . '-' . $invoice['number']) ?></td></tr>
            <tr><th><?= e(t('Tercero')) ?></th><td><?= e($invoice['name']) ?></td></tr>
            <tr><th><?= e(t('Fecha')) ?></th><td><?= e($invoice['date']) ?></td></tr>
            <tr><th><?= e(t('Total')) ?></th><td><?= e(num((float) $invoice['total'])) ?></td></tr>
            <tr><th><?= e(t('Devuelto')) ?></th><td><?= e(num($invoice['returned'])) ?></td></tr>
        </table>
        </div>

        <?php if ($message): ?>
            <p class="error"><?= e(t($message)) ?></p>
        <?php else: ?>
        <form method="post" action="/module/invoices/return">
            <input type="hidden" name="csrf" value="<?= e(csrf()) ?>">
            <input type="hidden" name="prefix" value="<?= e($invoice['prefix']) ?>">
            <input type="hidden" name="number" value="<?= e($invoice['number']) ?>">
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
                    <th><?= e(t('Ítem')) ?></th><th><?= e(t('Vendido')) ?></th><th><?= e(t('Devuelto')) ?></th><th><?= e(t('Cantidad a devolver')) ?></th>
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
