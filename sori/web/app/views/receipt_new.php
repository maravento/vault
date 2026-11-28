<?php
// New payment form: first look the invoice up, then register the payment. The server checks everything again.
// FILE: app/views/receipt_new.php
$o = $old ?? [];
$message = null;
if ($invoice) {
    if ($invoice['cancelled_flag'] === 'S') {
        $message = 'La factura está anulada.';
    } elseif ($invoice['credit'] !== 'S') {
        $message = 'La factura no es de crédito: no recibe abonos.';
    } elseif (round($invoice['balance'], 2) <= 0) {
        $message = 'La factura no tiene saldo.';
    }
}
?>
<div class="content-area">
    <a class="btn-small" href="/module/<?= e($mod['id']) ?>"><?= e(t('← Volver a')) ?> <?= e(t($mod['name'])) ?></a>
    <h2><i class="fas <?= e($mod['icon']) ?>"></i> <?= e(t('Nuevo abono')) ?></h2>
    <?php if ($error): ?><p class="error"><?= e($error) ?></p><?php endif; ?>

    <form class="search" method="get" action="/module/receivables/new">
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
            <tr><th><?= e(t('Fecha de vencimiento')) ?></th><td><?= e($invoice['due']) ?></td></tr>
            <tr><th><?= e(t('Forma de pago')) ?></th><td><?= e(trim((string) $invoice['payment'])) ?></td></tr>
            <tr><th><?= e(t('Total')) ?></th><td><?= e(num((float) $invoice['total'])) ?></td></tr>
            <tr><th><?= e(t('Pagado')) ?></th><td><?= e(num((float) trim((string) $invoice['paid']))) ?></td></tr>
            <tr><th><?= e(t('Saldo')) ?></th><td><strong><?= e(num($invoice['balance'])) ?></strong></td></tr>
        </table>
        </div>

        <?php if ($message): ?>
            <p class="error"><?= e(t($message)) ?></p>
        <?php else: ?>
        <form method="post" action="/module/receivables/new">
            <input type="hidden" name="csrf" value="<?= e(csrf()) ?>">
            <input type="hidden" name="prefix" value="<?= e($invoice['prefix']) ?>">
            <input type="hidden" name="number" value="<?= e($invoice['number']) ?>">
            <div class="form-grid">
                <label><?= e(t('Fecha')) ?>
                    <input type="text" name="date" value="<?= e((string) ($o['date'] ?? date('d/m/Y'))) ?>" maxlength="10" placeholder="dd/mm/aaaa">
                </label>
                <label><?= e(t('Valor')) ?>
                    <input type="number" name="value" value="<?= e((string) ($o['value'] ?? round($invoice['balance'], 2))) ?>" min="0.01" step="0.01">
                </label>
                <label><?= e(t('Cuenta de pago')) ?>
                    <select name="account">
                    <?php $acct = (string) ($o['account'] ?? ''); foreach ($options['accounts'] as $c): ?>
                        <option value="<?= e($c['code']) ?>"<?= $c['code'] === $acct ? ' selected' : '' ?>><?= e(trim($c['name'])) ?></option>
                    <?php endforeach; ?>
                    </select>
                </label>
                <label><?= e(t('Prefijo del abono')) ?>
                    <select name="receipt_prefix">
                    <?php $receipt_prefix = (string) ($o['receipt_prefix'] ?? $options['last_prefix']); foreach ($options['prefixes'] as $p): ?>
                        <option value="<?= e($p['code']) ?>"<?= $p['code'] === $receipt_prefix ? ' selected' : '' ?>><?= e($p['code'] . ' ' . trim($p['name'])) ?></option>
                    <?php endforeach; ?>
                    </select>
                </label>
                <label class="wide"><?= e(t('Observación')) ?>
                    <input type="text" name="remark" value="<?= e((string) ($o['remark'] ?? '')) ?>" maxlength="255">
                </label>
            </div>
            <button type="submit" class="btn-main"><?= e(t('Guardar abono')) ?></button>
        </form>
        <?php endif; ?>
    <?php endif; ?>
</div>
