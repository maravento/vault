<?php
// New supplier payment form: first look the purchase up, then register the payment. The server checks everything again.
// FILE: app/views/supplier_payment_new.php
$o = $old ?? [];
$message = null;
if ($purchase) {
    if ($purchase['cancelled'] === 'S') {
        $message = 'La compra está anulada.';
    } elseif ($purchase['credit'] !== 'S') {
        $message = 'La compra no es a crédito: no recibe pagos.';
    } elseif (round($s['balance'], 2) <= 0) {
        $message = 'La compra no tiene saldo.';
    }
}
?>
<div class="content-area">
    <a class="btn-small" href="/module/<?= e($mod['id']) ?>"><?= e(t('← Volver a')) ?> <?= e(t($mod['name'])) ?></a>
    <h2><i class="fas <?= e($mod['icon']) ?>"></i> <?= e(t('Nuevo pago a proveedor')) ?></h2>
    <?php if ($error): ?><p class="error"><?= e($error) ?></p><?php endif; ?>

    <form class="search" method="get" action="/module/payables/new">
        <select name="t">
        <?php foreach ($options['types'] as $x): ?>
            <option value="<?= e($x['code']) ?>"<?= $x['code'] === $q['t'] ? ' selected' : '' ?>><?= e(trim($x['name'])) ?></option>
        <?php endforeach; ?>
        </select>
        <input type="text" name="y" value="<?= e($q['y']) ?>" placeholder="<?= e(t('Año')) ?>" maxlength="4">
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
            <tr><th><?= e(t('Fecha de vencimiento')) ?></th><td><?= e($purchase['due']) ?></td></tr>
            <tr><th><?= e(t('Forma de pago')) ?></th><td><?= e(trim((string) $purchase['payment_name'])) ?></td></tr>
            <tr><th><?= e(t('Deuda')) ?></th><td><?= e(num($s['debt'])) ?></td></tr>
            <tr><th><?= e(t('Pagado')) ?></th><td><?= e(num($s['paid'])) ?></td></tr>
            <tr><th><?= e(t('Devuelto')) ?></th><td><?= e(num($s['returned'])) ?></td></tr>
            <tr><th><?= e(t('Saldo')) ?></th><td><strong><?= e(num($s['balance'])) ?></strong></td></tr>
        </table>
        </div>

        <?php if ($message): ?>
            <p class="error"><?= e(t($message)) ?></p>
        <?php else: ?>
        <form method="post" action="/module/payables/new">
            <input type="hidden" name="csrf" value="<?= e(csrf()) ?>">
            <input type="hidden" name="type" value="<?= e($purchase['type']) ?>">
            <input type="hidden" name="year" value="<?= e($purchase['doc_year']) ?>">
            <input type="hidden" name="number" value="<?= e($purchase['number']) ?>">
            <div class="form-grid">
                <label><?= e(t('Fecha')) ?>
                    <input type="text" name="date" value="<?= e((string) ($o['date'] ?? date('d/m/Y'))) ?>" maxlength="10" placeholder="dd/mm/aaaa">
                </label>
                <label><?= e(t('Valor')) ?>
                    <input type="number" name="value" value="<?= e((string) ($o['value'] ?? round($s['balance'], 2))) ?>" min="0.01" step="0.01">
                </label>
                <label><?= e(t('Cuenta de pago')) ?>
                    <select name="account">
                    <?php $acct = (string) ($o['account'] ?? ''); foreach ($options['accounts'] as $c): ?>
                        <option value="<?= e($c['code']) ?>"<?= $c['code'] === $acct ? ' selected' : '' ?>><?= e(trim($c['name'])) ?></option>
                    <?php endforeach; ?>
                    </select>
                </label>
                <label><?= e(t('Documento')) ?>
                    <input type="text" name="document" value="<?= e((string) ($o['document'] ?? '')) ?>" maxlength="5">
                </label>
                <label class="wide"><?= e(t('Observación')) ?>
                    <input type="text" name="remark" value="<?= e((string) ($o['remark'] ?? '')) ?>" maxlength="255">
                </label>
            </div>
            <button type="submit" class="btn-main"><?= e(t('Guardar pago')) ?></button>
        </form>
        <?php endif; ?>
    <?php endif; ?>
</div>
