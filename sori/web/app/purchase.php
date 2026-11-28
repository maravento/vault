<?php
// SORI writes: a purchase from a supplier. It follows the legacy program, checked on real data:
// the purchase is a document of an entry type (T611 with lines in T612), the quantities go into the stock
// totals and, when the company posts online, the accounting document debits the stock accounts by tax rate
// and the tax, and credits the means of payment less the income-tax withholding.
// Discounts, freight and the other withholdings are not supported: the form does not offer them.
// FILE: app/purchase.php
declare(strict_types=1);

// Purchase types the form offers: entry types named as a purchase
function purchase_options(PDO $db): array
{
    return [
        'types' => $db->query("SELECT T617Codigo AS code, T617Nombre AS name FROM T617TIPOTRANSACCION WHERE T617Tipo = 'E' AND T617Nombre LIKE 'COMPRA%' ORDER BY CAST(T617Codigo AS UNSIGNED)")->fetchAll(),
        'payments' => $db->query('SELECT T616Codigo AS code, T616Nombre AS name FROM T616TIPOFORMAPAGO ORDER BY CAST(T616Codigo AS UNSIGNED)')->fetchAll(),
    ];
}

// Next number of a document type: after the counter of the type and after the highest document of the type
function next_number_for_type(PDO $db, string $company_id, string $type): string
{
    $st = $db->prepare('SELECT T617Consecutivo FROM T617TIPOTRANSACCION WHERE T617Codigo = ? FOR UPDATE');
    $st->execute([$type]);
    $consec = $st->fetchColumn();
    $st = $db->prepare('SELECT COALESCE(MAX(CAST(T611NumeroDoc AS UNSIGNED)), 0) FROM T611DOCUMENTO WHERE T611CodEmpresa = ? AND T611TipoTransaccion = ?');
    $st->execute([$company_id, $type]);
    $num = (string) (max((int) ($consec === false ? 0 : $consec), (int) $st->fetchColumn()) + 1);
    if ($consec !== false) {
        $db->prepare('UPDATE T617TIPOTRANSACCION SET T617Consecutivo = ? WHERE T617Codigo = ?')->execute([$num, $type]);
    }
    return $num;
}

// Accounting document of a purchase. The setup row is chosen by year, accounting group and type (process 1).
function post_purchase(PDO $db, string $company_id, string $type, string $supplier, array $lines, string $num, string $payment, bool $credit, float $withholding_amount, DateTimeImmutable $d): void
{
    $year = $d->format('Y');
    $date = $d->format('d/m/Y');
    $group = $db->prepare('SELECT T623CodGrupo FROM T623CONCEPTOxGRUPO WHERE T623CodEmpresa = ? AND T623CodConcepto = ? ORDER BY T623CodGrupo LIMIT 1');
    $record = $db->prepare("SELECT * FROM T620CONCEPTOCONTAB WHERE T620CodEmpresa = ? AND T620Agno = ? AND T620CodGrupo = ? AND T620CodProceso = '1' AND T620TipoTransaccion = ? LIMIT 1");
    $debits = [];
    $doc_type = null;
    $credit_account = null;
    $withholding_account = '';
    foreach ($lines as $n => $l) {
        $group->execute([$company_id, $l['item_code']]);
        $g = $group->fetchColumn();
        if ($g === false) {
            throw new DocumentError(str_replace('{n}', (string) ($n + 1), t('El ítem {n} no tiene grupo contable.')));
        }
        $record->execute([$company_id, $year, $g, $type]);
        $c = $record->fetch();
        if (!$c) {
            throw new DocumentError(t('No hay configuración contable para la compra de este grupo.'));
        }
        $td = trim((string) $c['T620CodTipoDocContab']);
        if ($td === '' || ($doc_type !== null && $doc_type !== $td)) {
            throw new DocumentError(t('Los ítems usan tipos de documento contable distintos.'));
        }
        $doc_type = $td;
        $idx = null;
        for ($k = 1; $k <= 4; $k++) {
            if (trim((string) $c["T620Cuenta$k"]) !== '' && abs((float) $c["T620PorcIVA$k"] - $l['rate']) < 0.01) {
                $idx = $k;
                break;
            }
        }
        if ($idx === null) {
            throw new DocumentError(str_replace('{n}', (string) ($n + 1), t('No hay cuenta contable para el IVA del ítem {n}.')));
        }
        $acct = trim((string) $c["T620Cuenta$idx"]);
        $debits[$acct] = ($debits[$acct] ?? 0.0) + $l['qty'] * $l['cost'];
        if ($l['vat'] > 0) {
            $tax_account = trim((string) $c["T620CuentaImp$idx"]);
            if ($tax_account === '') {
                throw new DocumentError(str_replace('{n}', (string) ($n + 1), t('No hay cuenta contable para el IVA del ítem {n}.')));
            }
            $debits[$tax_account] = ($debits[$tax_account] ?? 0.0) + $l['vat'];
        }
        $col = $credit ? 'T620Credito' : ($payment === PAYMENT_BANK ? 'T620Banco' : ($payment === PAYMENT_CASH ? 'T620Caja' : null));
        $account = $col === null ? '' : trim((string) $c[$col]);
        if ($account === '' || ($credit_account !== null && $credit_account !== $account)) {
            throw new DocumentError(t('La forma de pago no tiene una cuenta contable verificada.'));
        }
        $credit_account = $account;
        $withholding_account = trim((string) $c['T620ReteRenta']);
    }
    $entry_lines = [];
    $total = 0.0;
    foreach ($debits as $acct => $value) {
        $r = round($value, 0);
        if ($r != 0) {
            $entry_lines[] = [$acct, $r, 0.0, ' '];
            $total += $r;
        }
    }
    if (!$entry_lines) {
        return;
    }
    $withholding_rounded = round($withholding_amount, 0);
    if ($withholding_rounded > 0 && $withholding_account === '') {
        throw new DocumentError(t('No hay cuenta contable para la retención en la fuente.'));
    }
    $entry_lines[] = [$credit_account, 0.0, $total - $withholding_rounded, $num];
    if ($withholding_rounded > 0) {
        $entry_lines[] = [$withholding_account, 0.0, $withholding_rounded, ' '];
    }

    $st = $db->prepare('SELECT COUNT(*) FROM T104DOCUMENTO WHERE T104CodEmpresa = ? AND T104Agno = ? AND T104CodTipoDoc = ? AND T104NumeroDoc = ?');
    $st->execute([$company_id, $year, $doc_type, $num]);
    if ((int) $st->fetchColumn()) {
        throw new DocumentError(str_replace('{n}', $num, t('Ya existe el documento contable {n}.')));
    }
    $db->prepare(
        'INSERT INTO T104DOCUMENTO (T104CodEmpresa, T104Agno, T104CodTipoDoc, T104NumeroDoc, T104Fecha, T104Concepto, T104Anulado,
            T104Aplicacion, T104ValorTotal, T104NombreCheque, NumeroAnterior, NuevoNumero, T104Bloqueado)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    )->execute([$company_id, $year, $doc_type, $num, $date, ' ', 'N', 'FACTURACIO', ' ', ' ', '', '', 'N']);
    $ins = $db->prepare(
        'INSERT INTO T106MOVIMIENTO (T106CodEmpresa, T106Agno, T106CodTipoDoc, T106NumeroDoc, T106CodCta, T106ConsecCta, T106Fecha,
            T106CodCentro, T106Nit, T106Referencia, T106Detalle, T106ValorDebito, T106ValorCredito, T106CodSubTipoDoc,
            T106SubNumeroDoc, T106FechaConciliado, Anterior, Nuevo)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    foreach ($entry_lines as $k => $l) {
        $ins->execute([
            $company_id, $year, $doc_type, $num, $l[0], (string) $k, $date, $lines[0]['center'], $supplier, ' ', ' ',
            legacy_num((float) $l[1], 0), legacy_num((float) $l[2], 0), $l[3], ' ', '01/01/1900', '', '',
        ]);
    }
}

// Saves a purchase. One transaction: if anything fails, nothing is saved.
// Returns ['keys' => [...], 'notice' => text|null] or ['error' => message].
function purchase_save(PDO $db, string $entered_by, array $in): array
{
    $company_id = company_code($db);
    $entered_by = substr($entered_by, 0, 20);
    $type = field($in['type'] ?? '');
    $tax_id = field($in['supplier'] ?? '');
    $invoice = field($in['invoice'] ?? '');
    $payment = field($in['payment'] ?? '');
    $date = field($in['date'] ?? '');
    $withholding_percent = field($in['withholding_percent'] ?? '');
    foreach (['item', 'quantity', 'value', 'vat'] as $k) {
        if (!isset($in[$k]) || !is_array($in[$k])) {
            return ['error' => t('Agregue al menos un ítem.')];
        }
    }
    $d = DateTimeImmutable::createFromFormat('!d/m/Y', $date);
    if ($d === false || $d->format('d/m/Y') !== $date) {
        return ['error' => t('Fecha no válida.')];
    }
    if ($d > new DateTimeImmutable('today')) {
        return ['error' => t('La fecha no puede ser futura.')];
    }
    if ($invoice === '' || text_length($invoice) > 15) {
        return ['error' => t('Indique el número de la factura del proveedor.')];
    }
    $withholding = 0.0;
    if ($withholding_percent !== '') {
        $withholding = positive_decimal($withholding_percent, true) ?? -1.0;
        if ($withholding < 0 || $withholding > 100) {
            return ['error' => t('Porcentaje de retención no válido.')];
        }
    }
    $st = $db->prepare("SELECT 1 FROM T617TIPOTRANSACCION WHERE T617Codigo = ? AND T617Tipo = 'E' AND T617Nombre LIKE 'COMPRA%'");
    $st->execute([$type]);
    if (!$st->fetchColumn()) {
        return ['error' => t('Tipo de compra no válido.')];
    }
    $st = $db->prepare('SELECT 1 FROM T12TERCERO WHERE T12CodEmpresa = ? AND T12Nit = ?');
    $st->execute([$company_id, $tax_id]);
    if ($tax_id === '' || !$st->fetchColumn()) {
        return ['error' => t('Proveedor no válido.')];
    }
    $st = $db->prepare('SELECT T616DiasInc, T616Cartera FROM T616TIPOFORMAPAGO WHERE T616Codigo = ?');
    $st->execute([$payment]);
    $payment_row = $st->fetch();
    if ($payment === '' || !$payment_row) {
        return ['error' => t('Forma de pago no válida.')];
    }
    $st = $db->prepare('SELECT T10ContabilidadBloque FROM T10EMPRESA WHERE T10CodEmpresa = ?');
    $st->execute([$company_id]);
    $online = ($st->fetchColumn() ?: 'N') !== 'S';

    // Items
    $lines = [];
    $item_codes = array_values($in['item']);
    if (!$item_codes || count($item_codes) > 200) {
        return ['error' => t('Agregue al menos un ítem.')];
    }
    $sel = $db->prepare('SELECT TRIM(T603Tipo) AS type FROM T603CONCEPTO WHERE T603CodEmpresa = ? AND T603Codigo = ?');
    foreach ($item_codes as $i => $item_code) {
        $n = $i + 1;
        $item_code = field($item_code);
        if ($item_code === '' && field($in['quantity'][$i] ?? '') === '' && field($in['value'][$i] ?? '') === '') {
            continue;
        }
        $sel->execute([$company_id, $item_code]);
        $t = $sel->fetchColumn();
        if ($item_code === '' || $t === false) {
            return ['error' => str_replace('{c}', $item_code, t('Concepto no encontrado: {c}'))];
        }
        $qty = positive_decimal($in['quantity'][$i] ?? null);
        $cost = positive_decimal($in['value'][$i] ?? null);
        $rate = positive_decimal($in['vat'][$i] ?? '0', true);
        if ($qty === null || $qty > 99999 || $cost === null || $cost > 999999999 || $rate === null || $rate > 100) {
            return ['error' => str_replace('{n}', (string) $n, t('Cantidad, valor o IVA no válido en el ítem {n}.'))];
        }
        $lines[] = [
            'item_code' => $item_code, 'qty' => $qty, 'cost' => $cost, 'rate' => $rate, 'vat' => round($qty * $cost * $rate / 100, 2),
            'center' => '00', 'type' => (string) $t,
        ];
    }
    if (!$lines) {
        return ['error' => t('Agregue al menos un ítem.')];
    }
    $base_total = 0.0;
    $vat_total = 0.0;
    foreach ($lines as $l) {
        $base_total += $l['qty'] * $l['cost'];
        $vat_total += $l['vat'];
    }
    $withholding_amount = round($base_total * $withholding / 100, 2);

    $lock = number_lock($db, 'purchase', $company_id, $type);
    if ($lock === null) {
        return ['error' => t('No se pudo asignar el número. Intente de nuevo.')];
    }
    try {
        $db->beginTransaction();
        $lock_message = period_locked($db, $company_id, $d);
        if ($lock_message !== null) {
            $db->rollBack();
            return ['error' => $lock_message];
        }
        // The same invoice of a supplier is not entered twice
        $st = $db->prepare("SELECT COUNT(*) FROM T611DOCUMENTO WHERE T611CodEmpresa = ? AND T611TipoTransaccion = ? AND T611CodProveedor = ? AND T611NumFactura = ? AND T611Anular <> 'S'");
        $st->execute([$company_id, $type, $tax_id, $invoice]);
        if ((int) $st->fetchColumn()) {
            $db->rollBack();
            return ['error' => t('Esa factura del proveedor ya está registrada.')];
        }
        $num = next_number_for_type($db, $company_id, $type);
        $year = $d->format('Y');
        $due = $d->modify('+' . (int) $payment_row['T616DiasInc'] . ' days')->format('d/m/Y');
        $header = [
            'T611CodEmpresa' => $company_id, 'T611Agno' => $year, 'T611TipoTransaccion' => $type, 'T611NumeroDoc' => $num, 'T611Fecha' => $date,
            'T611CodProveedor' => $tax_id, 'T611ValorBase' => legacy_num($base_total, 4), 'T611ValorIVA' => legacy_num($vat_total, 2),
            'T611ValorDescuento' => '0', 'T611ValorTtFactura' => legacy_num($base_total + $vat_total, 4), 'T611FormaPago' => $payment,
            'T611FechaVence' => $due, 'T611Concepto' => ' ', 'T611Prefijo' => ' ', 'T611NumFactura' => $invoice, 'T611Anular' => 'N',
            'T611FechaPago' => ' ', 'T611ValorReteRenta' => legacy_num($withholding_amount, 2), 'T611ValorReteIVA' => '0', 'T611ValorReteICA' => '0',
            'T611PorcRenta' => legacy_num($withholding, 2), 'T611PorcIVA' => '0', 'T611PorcICA' => '0', 'T611Consecutivo' => ' ', 'T611Digita' => $entered_by,
            'T611Impresa' => 'N', 'T611OtroDescuento' => '0', 'T611Hora' => date('H:i'), 'T611FechaDevol' => ' ', 'T611Obra' => ' ',
            'T611Vendedor' => ' ', 'T611Conductor' => ' ', 'T611PorcOtro' => '0', 'T611CUFE' => ' ', 'T611PdfCufe' => ' ', 'T611PorcAUIAdmon' => '0',
            'T611AUIAdmon' => '0', 'T611PorcAUIImprevisto' => '0', 'T611AUIImprevisto' => '0', 'T611PorcAUIUtilidad' => '0', 'T611AUIUtilidad' => '0',
            'T611PorcAUIIVA' => '0', 'T611AUIIVA' => '0', 'T611DescuentoCom' => '0', 'T611Moneda' => 'COP',
        ];
        $db->prepare('INSERT INTO T611DOCUMENTO (' . implode(', ', array_keys($header)) . ') VALUES (' . implode(', ', array_fill(0, count($header), '?')) . ')')
            ->execute(array_values($header));
        $last_cost = $db->prepare('UPDATE T603CONCEPTO SET T603UltValorCompra = ? WHERE T603CodEmpresa = ? AND T603Codigo = ?');
        foreach ($lines as $i => $l) {
            $mov = [
                'T612CodEmpresa' => $company_id, 'T612Agno' => $year, 'T612TipoTransaccion' => $type, 'T612NumeroDoc' => $num, 'T612CodArticulo' => $l['item_code'],
                'T612Cantidad' => legacy_num($l['qty'], 4), 'T612ValorArticulo' => legacy_num($l['cost'], 4), 'T612ValorDescuento' => '0',
                'T612ValorIVA' => legacy_num($l['vat'], 2), 'T612SubCodConcepto' => ' ', 'T612Consecutivo' => (string) ($i + 1),
                'T612CodCentro' => $l['center'], 'T612PorcIVA' => legacy_num($l['rate'], 2), 'T612Digita' => $entered_by,
                'T612ValorVenta' => legacy_num($l['cost'], 4), 'T612CodMetro2' => ' ', 'T612NumMetro2' => ' ', 'T612ValorFlete' => '0',
                'T612ValorVentaAct' => '0', 'T612FechaVence' => '01/01/1900', 'T612Lote' => ' ', 'T612ValorBaseCafe' => '0',
                'T612BonificaCafe' => '0', 'T612PorcTara' => '0', 'T612PorcFR' => '0', 'T612PorcHumedad' => '0', 'T612PorcKgBruto' => '0',
                'T612BrocaBase' => '0', 'T612Broca' => '0', 'T612HumedBase' => '0', 'T612BaseFR' => '0', 'T612PorcIVA2' => '0', 'T612ValorIVA2' => '0',
            ];
            $db->prepare('INSERT INTO T612MOVIMIENTO (' . implode(', ', array_keys($mov)) . ') VALUES (' . implode(', ', array_fill(0, count($mov), '?')) . ')')
                ->execute(array_values($mov));
            if ($l['type'] === '1') {
                $last_cost->execute([legacy_num($l['cost'], 4), $company_id, $l['item_code']]);
            }
        }
        stock_in($db, $company_id, $lines);
        if ($online) {
            post_purchase($db, $company_id, $type, $tax_id, $lines, $num, $payment, $payment_row['T616Cartera'] === 'S', $withholding_amount, $d);
        }
        audit($db, $entered_by, 'COMPRA ' . $type . '-' . $num . ' FACTURA ' . $invoice);
        $db->commit();
    } catch (DocumentError $ex) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        return ['error' => $ex->getMessage()];
    } catch (Throwable $ex) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        error_log('sori: purchase not saved: ' . $ex->getMessage());
        return ['error' => t('No se pudo guardar la compra.')];
    } finally {
        number_unlock($db, $lock);
    }
    return ['keys' => ['k0' => $company_id, 'k1' => $year, 'k2' => $type, 'k3' => $num], 'notice' => null];
}
