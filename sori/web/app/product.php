<?php
// SORI writes: create and edit a product or service (a "concepto"). It follows the legacy program, checked on real data:
// the item has a type (warehouse item or service), an accounting group (one row in T623), up to five price lists
// (T630, the price includes the tax) and starts with cost 0. The cost is kept by the purchases.
// FILE: app/product.php
declare(strict_types=1);

const GENERAL_SEASON = '1';
const PRICE_LISTS = ['1', '2', '3', '4', '5'];

// Lists the form needs
function product_options(PDO $db): array
{
    return [
        'groups' => $db->query('SELECT T621Codigo AS code, T621Nombre AS name FROM T621GRUPOCONTAB ORDER BY CAST(T621Codigo AS UNSIGNED)')->fetchAll(),
        'vat_types' => $db->query('SELECT T641Codigo AS code, T641Nombre AS name FROM T641TIPOIVA ORDER BY CAST(T641Codigo AS UNSIGNED)')->fetchAll(),
    ];
}

// A product with its prices, shaped like the form fields. Null when it does not exist.
function product_read(PDO $db, string $company_id, string $code): ?array
{
    $st = $db->prepare('SELECT * FROM T603CONCEPTO WHERE T603CodEmpresa = ? AND T603Codigo = ? AND T603CodTemporada = ?');
    $st->execute([$company_id, $code, GENERAL_SEASON]);
    $r = $st->fetch();
    if (!$r) {
        return null;
    }
    $st = $db->prepare('SELECT T630Codigo AS price_list, T630Valor AS value, T630ValorIVA AS vat, T630CodTipoIVA AS type FROM T630LISTAVALORES WHERE T630CodEmpresa = ? AND T630CodTemporada = ? AND T630CodConcepto = ? ORDER BY T630Codigo');
    $st->execute([$company_id, GENERAL_SEASON, $code]);
    $prices = [];
    $vat_type = '0';
    $vat_percent = '0';
    foreach ($st->fetchAll() as $p) {
        $prices[trim($p['price_list'])] = trim($p['value']);
        $vat_type = trim($p['type']);
        $vat_percent = trim($p['vat']);
    }
    $st = $db->prepare('SELECT T623CodGrupo FROM T623CONCEPTOxGRUPO WHERE T623CodEmpresa = ? AND T623CodConcepto = ? ORDER BY T623CodGrupo LIMIT 1');
    $st->execute([$company_id, $code]);
    return [
        'code' => trim($r['T603Codigo']), 'name' => trim($r['T603Nombre']), 'type' => trim($r['T603Tipo']), 'group' => trim((string) $st->fetchColumn()),
        'active' => trim($r['T603Imprimir']), 'free_price' => trim($r['T603ActivaValor']), 'allows_discount' => trim($r['T603ActivaDescuento']),
        'vat_type' => $vat_type, 'vat_percent' => $vat_percent, 'price' => $prices,
    ];
}

// Saves a new product or the changes of an existing one. One transaction.
// Returns ['keys' => [...]] or ['error' => message].
function product_save(PDO $db, string $entered_by, array $in, bool $new): array
{
    $company_id = company_code($db);
    $entered_by = substr($entered_by, 0, 20);
    $c = static fn(string $k): string => field($in[$k] ?? '');
    $row_exists = static function (string $sql, array $p) use ($db): bool {
        $st = $db->prepare($sql);
        $st->execute($p);
        return (bool) $st->fetchColumn();
    };

    $code = $c('code');
    if (!preg_match('/^[A-Za-z0-9._-]{1,20}$/', $code)) {
        return ['error' => t('Código no válido: use hasta 20 letras, números, punto, guion o guion bajo.')];
    }
    if ($c('name') === '') {
        return ['error' => t('Indique el nombre.')];
    }
    if (text_length($c('name')) > 255) {
        return ['error' => str_replace('{n}', '255', t('Un texto supera los {n} caracteres.'))];
    }
    $type = $c('type');
    if ($type !== '1' && $type !== '2') {
        return ['error' => t('Tipo no válido.')];
    }
    $group = $c('group');
    if (!$row_exists('SELECT 1 FROM T621GRUPOCONTAB WHERE T621Codigo = ?', [$group])) {
        return ['error' => t('Grupo contable no válido.')];
    }
    $vat_type = $c('vat_type');
    if (!$row_exists('SELECT 1 FROM T641TIPOIVA WHERE T641Codigo = ?', [$vat_type])) {
        return ['error' => t('Tipo de IVA no válido.')];
    }
    // The rate applies only to taxed items
    $rate = '0';
    if ($vat_type === '0') {
        $p = positive_decimal($c('vat_percent') === '' ? '0' : $c('vat_percent'), true);
        if ($p === null || $p > 100) {
            return ['error' => t('Porcentaje de IVA no válido.')];
        }
        $rate = legacy_num($p, 2);
    }
    $prices = [];
    foreach (PRICE_LISTS as $price_list) {
        $v = field($in['price'][$price_list] ?? '');
        if ($v === '') {
            continue;
        }
        $n = positive_decimal($v, true);
        if ($n === null || $n > 999999999999) {
            return ['error' => str_replace('{n}', $price_list, t('Precio no válido en la lista {n}.'))];
        }
        $prices[$price_list] = legacy_num($n, 2);
    }
    if (!isset($prices['1'])) {
        return ['error' => t('Indique el precio de la lista 1.')];
    }
    $yes_no = static fn(string $k): string => isset($in[$k]) && $in[$k] === 'S' ? 'S' : 'N';

    $tax_changed = true;
    try {
        $db->beginTransaction();
        if ($new) {
            $record = [];
            foreach ($db->query('SHOW COLUMNS FROM T603CONCEPTO')->fetchAll() as $col) {
                $record[$col['Field']] = ' ';
            }
            $record = array_merge($record, [
                'T603CodEmpresa' => $company_id, 'T603Codigo' => $code, 'T603CodTemporada' => GENERAL_SEASON, 'T603Nombre' => $c('name'),
                'T603CobroAut' => 'N', 'T603Imprimir' => $yes_no('active'), 'T603Tipo' => $type, 'T603Operacion' => '1', 'T603Peso' => '0',
                'T603ActivaValor' => $yes_no('free_price'), 'T603ActivaDescuento' => $yes_no('allows_discount'), 'T603UltValorCompra' => '0',
                'T603CostoPromedio' => '0', 'T603CostoDigitado' => '0', 'T603UnidadMedida' => '94', 'T603BaseInteres' => 'N', 'T603GrupoCC' => '-1',
                'T603UltFlete' => '0', 'T603UltFlete1' => '0', 'T603UltFlete2' => '0',
            ]);
            $db->prepare('INSERT INTO T603CONCEPTO (' . implode(', ', array_keys($record)) . ') VALUES (' . implode(', ', array_fill(0, count($record), '?')) . ')')
                ->execute(array_values($record));
        } else {
            $st = $db->prepare('SELECT 1 FROM T603CONCEPTO WHERE T603CodEmpresa = ? AND T603Codigo = ? AND T603CodTemporada = ? FOR UPDATE');
            $st->execute([$company_id, $code, GENERAL_SEASON]);
            if (!$st->fetchColumn()) {
                $db->rollBack();
                return ['error' => t('Producto no encontrado.')];
            }
            $previous = product_read($db, $company_id, $code);
            $tax_changed = $previous['vat_type'] !== $vat_type || (float) $previous['vat_percent'] !== (float) $rate;
            // The type does not change: the movements of the item were made with it
            $db->prepare('UPDATE T603CONCEPTO SET T603Nombre = ?, T603Imprimir = ?, T603ActivaValor = ?, T603ActivaDescuento = ? WHERE T603CodEmpresa = ? AND T603Codigo = ? AND T603CodTemporada = ?')
                ->execute([$c('name'), $yes_no('active'), $yes_no('free_price'), $yes_no('allows_discount'), $company_id, $code, GENERAL_SEASON]);
        }
        // Only the five lists of the form are replaced; any other list of the item is kept
        $removed = array_diff(PRICE_LISTS, array_keys($prices));
        foreach ($removed as $price_list) {
            $db->prepare('DELETE FROM T630LISTAVALORES WHERE T630CodEmpresa = ? AND T630CodTemporada = ? AND T630CodConcepto = ? AND T630Codigo = ?')
                ->execute([$company_id, GENERAL_SEASON, $code, $price_list]);
        }
        $tax_update = $tax_changed ? ', T630ValorIVA = VALUES(T630ValorIVA), T630CodTipoIVA = VALUES(T630CodTipoIVA)' : '';
        $ins = $db->prepare("INSERT INTO T630LISTAVALORES (T630CodEmpresa, T630CodTemporada, T630CodConcepto, T630Codigo, T630Valor, T630ValorIVA, T630CodTipoIVA, T630PorcInc, T630PorcDec, T630PorcRentab, T630ValorIPCO) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE T630Valor = VALUES(T630Valor)$tax_update");
        foreach ($prices as $price_list => $value) {
            $ins->execute([$company_id, GENERAL_SEASON, $code, $price_list, $value, $rate, $vat_type, '0', '0', '0', ' ']);
        }
        $db->prepare('DELETE FROM T623CONCEPTOxGRUPO WHERE T623CodEmpresa = ? AND T623CodConcepto = ?')->execute([$company_id, $code]);
        $db->prepare('INSERT INTO T623CONCEPTOxGRUPO (T623CodEmpresa, T623CodConcepto, T623CodGrupo) VALUES (?, ?, ?)')->execute([$company_id, $code, $group]);
        audit($db, $entered_by, 'PRODUCTO ' . $code);
        $db->commit();
    } catch (PDOException $ex) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        if ($ex->getCode() === '23000') {
            return ['error' => t('Ya existe un producto con ese código.')];
        }
        error_log('sori: product not saved: ' . $ex->getMessage());
        return ['error' => t('No se pudo guardar el producto.')];
    }
    return ['keys' => ['k0' => $company_id, 'k1' => $code, 'k2' => GENERAL_SEASON]];
}
