<?php
// Third party form, for a new record and for an edit. The browser only helps to fill it: the server checks everything again.
// $edit is true when the record exists: its document cannot change.
// FILE: app/views/third_party_form.php
$o = $old ?? [];
$v = static fn(string $k, string $def = ''): string => (string) ($o[$k] ?? $def);
$person_type = $v('person_type', '0');
$department_selected = $v('department', $options['company']['department']);
$city_selected = $v('city', $options['company']['city']);
$types_selected = (array) ($o['types'] ?? []);
$route = $edit ? '/module/parties/edit' : '/module/parties/new';
?>
<div class="content-area">
    <a class="btn-small" href="/module/<?= e($mod['id']) ?>"><?= e(t('← Volver a')) ?> <?= e(t($mod['name'])) ?></a>
    <h2><i class="fas <?= e($mod['icon']) ?>"></i> <?= e(t($edit ? 'Editar tercero' : 'Nuevo tercero')) ?></h2>
    <?php if ($error): ?><p class="error"><?= e($error) ?></p><?php endif; ?>

    <form method="post" action="<?= e($route) ?>" id="party">
        <input type="hidden" name="csrf" value="<?= e(csrf()) ?>">
        <div class="form-grid">
            <label><?= e(t('Tipo de documento')) ?>
                <select name="doc_type">
                <?php $td = $v('doc_type', '13'); foreach ($options['doc_types'] as $x): ?>
                    <option value="<?= e($x['code']) ?>"<?= $x['code'] === $td ? ' selected' : '' ?>><?= e(trim($x['name'])) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label><?= e(t('Documento')) ?>
                <?php if ($edit): ?>
                    <input type="hidden" name="tax_id" value="<?= e($v('tax_id')) ?>">
                    <input type="text" value="<?= e($v('tax_id') . ($v('check_digit') !== '' ? '-' . $v('check_digit') : '')) ?>" readonly>
                <?php else: ?>
                    <input type="text" name="tax_id" value="<?= e($v('tax_id')) ?>" maxlength="15" inputmode="numeric" placeholder="<?= e(t('Solo números')) ?>">
                <?php endif; ?>
            </label>
            <label><?= e(t('Tipo de persona')) ?>
                <select name="person_type" id="person_type">
                    <option value="0"<?= $person_type === '0' ? ' selected' : '' ?>><?= e(t('Natural')) ?></option>
                    <option value="1"<?= $person_type === '1' ? ' selected' : '' ?>><?= e(t('Jurídica')) ?></option>
                </select>
            </label>
            <label><?= e(t('Régimen')) ?>
                <select name="regime">
                <?php $rg = $v('regime', '0'); foreach (['0' => 'Sin definir', '1' => 'Común', '2' => 'Simplificado', '3' => 'Gran contribuyente'] as $k => $n): ?>
                    <option value="<?= e($k) ?>"<?= $k === $rg ? ' selected' : '' ?>><?= e(t($n)) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label class="natural"><?= e(t('Primer nombre')) ?>
                <input type="text" name="name" value="<?= e($v('name')) ?>" maxlength="50">
            </label>
            <label class="natural"><?= e(t('Segundo nombre')) ?>
                <input type="text" name="middle_name" value="<?= e($v('middle_name')) ?>" maxlength="20">
            </label>
            <label class="natural"><?= e(t('Primer apellido')) ?>
                <input type="text" name="last_name" value="<?= e($v('last_name')) ?>" maxlength="50">
            </label>
            <label class="natural"><?= e(t('Segundo apellido')) ?>
                <input type="text" name="second_last_name" value="<?= e($v('second_last_name')) ?>" maxlength="20">
            </label>
            <label class="legal wide"><?= e(t('Razón social')) ?>
                <input type="text" name="company_name" value="<?= e($v('company_name')) ?>" maxlength="80">
            </label>
            <label><?= e(t('Departamento')) ?>
                <select name="department" id="department">
                <?php foreach ($options['departments'] as $x): ?>
                    <option value="<?= e($x['code']) ?>"<?= $x['code'] === $department_selected ? ' selected' : '' ?>><?= e(trim($x['name'])) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label><?= e(t('Ciudad')) ?>
                <select name="city" id="city">
                <?php foreach ($options['cities'] as $x): ?>
                    <option value="<?= e($x['code']) ?>" data-department="<?= e($x['department']) ?>"<?= $x['code'] === $city_selected && $x['department'] === $department_selected ? ' selected' : '' ?>><?= e(trim($x['name'])) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label class="wide"><?= e(t('Dirección')) ?>
                <input type="text" name="address" value="<?= e($v('address')) ?>" maxlength="100" placeholder="<?= e(t('Si queda vacía se usa el nombre de la ciudad')) ?>">
            </label>
            <label><?= e(t('Teléfono')) ?>
                <input type="text" name="phone" value="<?= e($v('phone')) ?>" maxlength="30">
            </label>
            <label><?= e(t('Celular')) ?>
                <input type="text" name="mobile" value="<?= e($v('mobile')) ?>" maxlength="30">
            </label>
            <label><?= e(t('Correo')) ?>
                <input type="text" name="email" value="<?= e($v('email')) ?>" maxlength="50">
            </label>
            <label><?= e(t('País')) ?>
                <input type="text" name="country" value="<?= e($v('country', 'CO')) ?>" maxlength="2">
            </label>
            <label><?= e(t('Sexo')) ?>
                <select name="sex">
                    <?php $sex_selected = $v('sex'); foreach (['' => '', '1' => 'Masculino', '2' => 'Femenino'] as $k => $n): ?>
                    <option value="<?= e($k) ?>"<?= $k === $sex_selected ? ' selected' : '' ?>><?= e($n === '' ? '' : t($n)) ?></option>
                    <?php endforeach; ?>
                </select>
            </label>
            <label><?= e(t('Fecha de nacimiento')) ?>
                <input type="text" name="birth_date" value="<?= e($v('birth_date')) ?>" maxlength="10" placeholder="dd/mm/aaaa">
            </label>
            <label><?= e(t('Profesión')) ?>
                <select name="profession">
                    <option value=""></option>
                <?php $profession_selected = $v('profession'); foreach ($options['professions'] as $x): ?>
                    <option value="<?= e($x['code']) ?>"<?= $x['code'] === $profession_selected ? ' selected' : '' ?>><?= e(trim($x['name'])) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label><?= e(t('Calificación')) ?>
                <select name="rating">
                    <option value=""></option>
                <?php $rating_selected = $v('rating'); foreach ($options['ratings'] as $x): ?>
                    <option value="<?= e($x['code']) ?>"<?= $x['code'] === $rating_selected ? ' selected' : '' ?>><?= e(trim($x['name'])) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label><?= e(t('Cupo de crédito')) ?>
                <input type="number" name="credit_limit" value="<?= e($v('credit_limit', '0')) ?>" min="0" step="any">
            </label>
            <label><?= e(t('Cupo de facturas')) ?>
                <input type="number" name="invoice_limit" value="<?= e($v('invoice_limit', '0')) ?>" min="0" max="999" step="1">
            </label>
            <label><?= e(t('Forma de pago habitual')) ?>
                <select name="payment">
                    <option value=""></option>
                <?php $payment_row = $v('payment'); foreach ($options['payments'] as $x): ?>
                    <option value="<?= e($x['code']) ?>"<?= $x['code'] === $payment_row ? ' selected' : '' ?>><?= e(trim($x['name'])) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label><?= e(t('Vendedor')) ?>
                <select name="salesperson">
                    <option value=""></option>
                <?php $salesperson_selected = $v('salesperson'); foreach ($options['salespeople'] as $x): ?>
                    <option value="<?= e($x['code']) ?>"<?= $x['code'] === $salesperson_selected ? ' selected' : '' ?>><?= e(trim($x['name'])) ?></option>
                <?php endforeach; ?>
                </select>
            </label>
            <label class="wide"><?= e(t('Observación')) ?>
                <input type="text" name="remark" value="<?= e($v('remark')) ?>" maxlength="255">
            </label>
        </div>
        <fieldset>
            <legend><?= e(t('Clase de tercero')) ?></legend>
            <?php foreach ($options['types'] as $x): ?>
                <label class="check"><input type="checkbox" name="types[]" value="<?= e($x['code']) ?>"<?= in_array($x['code'], $types_selected, true) ? ' checked' : '' ?>> <?= e(trim($x['name'])) ?></label>
            <?php endforeach; ?>
        </fieldset>
        <button type="submit" class="btn-main"><?= e(t('Guardar tercero')) ?></button>
    </form>
</div>
<script src="/assets/third_party.js"></script>
