<?php
// New quote or invoice form. The browser only helps to fill it: the server checks and computes everything again.
// $doc gives the address, the title, the items heading and the button text of each kind of document.
// FILE: app/views/document_new.php
$o = $old ?? [];
$row_count = max(1, count((array) ($o['item'] ?? [])));
$record = static function (string $item_code, string $qty, string $val, string $disc): void { ?>
            <tr class="record">
                <td><input type="text" name="item[]" list="dl-item" value="<?= e($item_code) ?>" maxlength="20" autocomplete="off" class="f-code"></td>
                <td class="f-name"></td>
                <td><input type="number" name="quantity[]" value="<?= e($qty) ?>" min="0" step="any" class="f-qty"></td>
                <td><input type="number" name="value[]" value="<?= e($val) ?>" min="0" step="any" class="f-value" readonly></td>
                <td><input type="number" name="discount[]" value="<?= e($disc) ?>" min="0" step="any" class="f-disc" readonly></td>
                <td class="num f-vat">0</td>
                <td class="num f-sub">0</td>
                <td><button type="button" class="btn-small f-remove" title="<?= e(t('Quitar')) ?>">×</button></td>
            </tr>
<?php };
?>
<div class="content-area">
    <a class="btn-small" href="/module/<?= e($mod['id']) ?>"><?= e(t('← Volver a')) ?> <?= e(t($mod['name'])) ?></a>
    <h2><i class="fas <?= e($mod['icon']) ?>"></i> <?= e(t($doc['title'])) ?></h2>
    <?php if ($error): ?><p class="error"><?= e($error) ?></p><?php endif; ?>

    <form method="post" action="<?= e($doc['route']) ?>" id="document">
        <input type="hidden" name="csrf" value="<?= e(csrf()) ?>">
        <div class="form-grid">
            <label><?= e(t('Prefijo')) ?>
                <select name="prefix">
                <?php $doc_prefix = (string) ($o['prefix'] ?? $options['last_prefix']); foreach ($options['prefixes'] as $p): ?>
                    <option value="<?= e($p['code']) ?>"<?= $p['code'] === $doc_prefix ? ' selected' : '' ?>><?= e($p['code'] . ' ' . trim($p['name'])) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label><?= e(t('Fecha')) ?>
                <input type="text" name="date" value="<?= e((string) ($o['date'] ?? date('d/m/Y'))) ?>" maxlength="10" placeholder="dd/mm/aaaa">
            </label>
            <label><?= e(t('Tercero')) ?>
                <input type="text" name="party" id="party" list="dl-party" value="<?= e((string) ($o['party'] ?? '')) ?>" maxlength="20" autocomplete="off" placeholder="<?= e(t('Documento o nombre')) ?>">
            </label>
            <label><?= e(t('Forma de pago')) ?>
                <select name="payment">
                <?php $payment = (string) ($o['payment'] ?? '1'); foreach ($options['payments'] as $f): ?>
                    <option value="<?= e($f['code']) ?>"<?= $f['code'] === $payment ? ' selected' : '' ?>><?= e(trim($f['name'])) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label><?= e(t('Vendedor')) ?>
                <select name="salesperson">
                    <option value=""></option>
                <?php $salesperson_selected = (string) ($o['salesperson'] ?? ''); foreach ($options['salespeople'] as $v): ?>
                    <option value="<?= e($v['code']) ?>"<?= $v['code'] === $salesperson_selected ? ' selected' : '' ?>><?= e(trim($v['name'])) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label class="wide"><?= e(t('Detalle')) ?>
                <input type="text" name="detail" value="<?= e((string) ($o['detail'] ?? '')) ?>" maxlength="100">
            </label>
        </div>
        <datalist id="dl-party"></datalist>
        <datalist id="dl-item"></datalist>

        <h3><?= e(t($doc['items'])) ?></h3>
        <div class="table-wrap">
        <table class="content-table items">
            <thead>
                <tr>
                    <th><?= e(t('Código')) ?></th><th><?= e(t('Concepto')) ?></th><th><?= e(t('Cantidad')) ?></th>
                    <th><?= e(t('Valor (IVA incluido)')) ?></th><th><?= e(t('Descuento')) ?></th><th><?= e(t('IVA %')) ?></th>
                    <th><?= e(t('Subtotal')) ?></th><th></th>
                </tr>
            </thead>
            <tbody id="items">
            <?php for ($i = 0; $i < $row_count; $i++) {
                $record((string) ($o['item'][$i] ?? ''), (string) ($o['quantity'][$i] ?? '1'), (string) ($o['value'][$i] ?? ''), (string) ($o['discount'][$i] ?? '0'));
            } ?>
            </tbody>
        </table>
        </div>
        <template id="record"><?php $record('', '1', '', '0'); ?></template>
        <p>
            <button type="button" class="btn-small" id="add"><i class="fas fa-plus"></i> <?= e(t('Agregar ítem')) ?></button>
        </p>
        <p class="totals">
            <?= e(t('IVA')) ?>: <strong id="t-vat">0</strong> ·
            <?= e(t('Total')) ?>: <strong id="t-total">0</strong>
            <span class="muted"><?= e(t('Los totales se calculan de nuevo al guardar.')) ?></span>
        </p>
        <button type="submit" class="btn-main"><?= e(t($doc['button'])) ?></button>
    </form>
</div>
<script src="/assets/document.js"></script>
