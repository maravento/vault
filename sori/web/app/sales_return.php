<?php
// SORI writes: a customer return on a sales invoice. It follows the legacy program, checked on real data:
// the return is a document of type 6 (T611 with lines in T612) that points to the invoice, the returned
// quantities go back into the stock totals and, when the company posts online, the accounting document
// debits the sales-returns accounts and the tax and credits the means of payment.
// FILE: app/sales_return.php
declare(strict_types=1);

// SQL: what has been returned on an invoice, as an amount. $alias is the alias of the invoice table.
function returned_sql(string $alias): string
{
    return '(SELECT COALESCE(SUM(' . sql_num('h.T611ValorTtFactura') . "), 0) FROM T611DOCUMENTO h
             WHERE h.T611CodEmpresa = $alias.T604CodEmpresa AND h.T611TipoTransaccion = '6' AND h.T611Anular <> 'S'
               AND h.T611Prefijo = $alias.T604Prefijo AND h.T611NumFactura = $alias.T604NumFactura)";
}

// The lines of an invoice with what is left to return of each item. Items are counted by code:
// the same item on two lines shares what was sold and what was returned.
function sales_return_lines(PDO $db, string $company_id, string $doc_prefix, string $num): array
{
    $st = $db->prepare(
        'SELECT d.T605Consecutivo AS line_no, d.T605CodConcepto AS item_code, d.T605Cantidad AS qty, d.T605Valor AS value, d.T605ValorIVA AS vat,
                d.T605PorcIVA AS rate, d.T605Descuento AS discount, d.T605ValorCosto AS cost, TRIM(d.T605CodCentro) AS center,
                (SELECT c.T603Nombre FROM T603CONCEPTO c WHERE c.T603CodEmpresa = d.T605CodEmpresa AND c.T603Codigo = d.T605CodConcepto LIMIT 1) AS name,
                (SELECT c.T603Tipo FROM T603CONCEPTO c WHERE c.T603CodEmpresa = d.T605CodEmpresa AND c.T603Codigo = d.T605CodConcepto LIMIT 1) AS type,
                (SELECT COALESCE(SUM(' . sql_num('m.T612Cantidad') . "), 0) FROM T612MOVIMIENTO m
                   JOIN T611DOCUMENTO h ON h.T611CodEmpresa = m.T612CodEmpresa AND h.T611Agno = m.T612Agno
                        AND h.T611TipoTransaccion = m.T612TipoTransaccion AND h.T611NumeroDoc = m.T612NumeroDoc
                  WHERE h.T611TipoTransaccion = '6' AND h.T611Anular <> 'S' AND h.T611CodEmpresa = d.T605CodEmpresa
                    AND h.T611Prefijo = d.T605Prefijo AND h.T611NumFactura = d.T605NumFactura AND m.T612CodArticulo = d.T605CodConcepto) AS returned
         FROM T605FACTURADETALLE d WHERE d.T605CodEmpresa = ? AND d.T605Prefijo = ? AND d.T605NumFactura = ?
         ORDER BY CAST(d.T605Consecutivo AS UNSIGNED)"
    );
    $st->execute([$company_id, $doc_prefix, $num]);
    return $st->fetchAll();
}

// Accounting document of a return. The setup row is chosen by year, accounting group and the prefix of the
// return (process 1, transaction 6). The debit side is the sales-returns account and the tax of each item rate;
// the credit side is the means of payment, with the number of the return in the line.
function post_sales_return(PDO $db, string $company_id, array $f, array $lines, string $num, string $payment, bool $credit, DateTimeImmutable $d): void
{
    $year = $d->format('Y');
    $date = $d->format('d/m/Y');
    $group = $db->prepare('SELECT T623CodGrupo FROM T623CONCEPTOxGRUPO WHERE T623CodEmpresa = ? AND T623CodConcepto = ? ORDER BY T623CodGrupo LIMIT 1');
    $record = $db->prepare("SELECT * FROM T620CONCEPTOCONTAB WHERE T620CodEmpresa = ? AND T620Agno = ? AND T620CodGrupo = ? AND T620CodProceso = '1' AND T620TipoTransaccion = '6' LIMIT 1");
    $debits = [];
    $doc_type = null;
    $credit_account = null;
    foreach ($lines as $n => $l) {
        $group->execute([$company_id, $l['item_code']]);
        $g = $group->fetchColumn();
        if ($g === false) {
            throw new DocumentError(str_replace('{n}', (string) ($n + 1), t('El ítem {n} no tiene grupo contable.')));
        }
        $record->execute([$company_id, $year, $g]);
        $c = $record->fetch();
        if (!$c) {
            throw new DocumentError(t('No hay configuración contable para la devolución de este grupo.'));
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
        $debits[$acct] = ($debits[$acct] ?? 0.0) + $l['qty'] * $l['base'];
        if ($l['vat'] > 0) {
            $tax_account = trim((string) $c["T620CuentaImp$idx"]);
            if ($tax_account === '') {
                throw new DocumentError(str_replace('{n}', (string) ($n + 1), t('No hay cuenta contable para el IVA del ítem {n}.')));
            }
            $debits[$tax_account] = ($debits[$tax_account] ?? 0.0) + $l['vat'];
        }
        // The account that pays back: credit, card or cash
        $col = $credit ? 'T620Credito' : ($payment === PAYMENT_BANK ? 'T620Banco' : ($payment === PAYMENT_CASH ? 'T620Caja' : null));
        $account = $col === null ? '' : trim((string) $c[$col]);
        if ($account === '' || ($credit_account !== null && $credit_account !== $account)) {
            throw new DocumentError(t('La forma de pago no tiene una cuenta contable verificada.'));
        }
        $credit_account = $account;
    }
    $entry_lines = [];
    $total = 0.0;
    foreach ($debits as $acct => $value) {
        $r = round($value, 0);
        if ($r != 0) {
            $entry_lines[] = [$acct, $r, 0.0, ' ', ' '];
            $total += $r;
        }
    }
    if (!$entry_lines) {
        return;
    }
    $entry_lines[] = [$credit_account, 0.0, $total, ' ', $num];

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
            $company_id, $year, $doc_type, $num, $l[0], (string) $k, $date, '00', $f['party'], $l[3], ' ',
            legacy_num((float) $l[1], 0), legacy_num((float) $l[2], 0), $l[4], ' ', '01/01/1900', '', '',
        ]);
    }
}

// Saves a customer return. One transaction: if anything fails, nothing is saved.
// $in['quantity'] maps the line number of the invoice to the quantity returned.
// Returns ['keys' => [...], 'notice' => text|null] or ['error' => message].
function sales_return_save(PDO $db, string $entered_by, array $in): array
{
    $company_id = company_code($db);
    $entered_by = substr($entered_by, 0, 20);
    $doc_prefix = field($in['prefix'] ?? '');
    $invoice_num = field($in['number'] ?? '');
    $payment = field($in['payment'] ?? '');
    $date = field($in['date'] ?? '');
    $quantities = $in['quantity'] ?? null;
    if (!is_array($quantities)) {
        return ['error' => t('Indique la cantidad de al menos un ítem.')];
    }
    $d = DateTimeImmutable::createFromFormat('!d/m/Y', $date);
    if ($d === false || $d->format('d/m/Y') !== $date) {
        return ['error' => t('Fecha no válida.')];
    }
    if ($d > new DateTimeImmutable('today')) {
        return ['error' => t('La fecha no puede ser futura.')];
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

    $lock = number_lock($db, 'return_link', $company_id, '6');
    if ($lock === null) {
        return ['error' => t('No se pudo asignar el número. Intente de nuevo.')];
    }
    try {
        $db->beginTransaction();
        $st = $db->prepare('SELECT T604CUFE, T604Vendedor FROM T604FACTURA WHERE T604CodEmpresa = ? AND T604Prefijo = ? AND T604NumFactura = ? FOR UPDATE');
        $st->execute([$company_id, $doc_prefix, $invoice_num]);
        $header_row = $st->fetch();
        $f = $header_row ? invoice_for_receipt($db, $company_id, $doc_prefix, $invoice_num) : null;
        if ($f === null) {
            $db->rollBack();
            return ['error' => t('Factura no encontrada.')];
        }
        if ($f['cancelled_flag'] === 'S') {
            $db->rollBack();
            return ['error' => t('La factura está anulada.')];
        }
        if (trim((string) $header_row['T604CUFE']) !== '') {
            $db->rollBack();
            return ['error' => t('La factura se envió electrónicamente: su devolución es una nota crédito electrónica, que Sori aún no genera.')];
        }
        $doc_date = DateTimeImmutable::createFromFormat('!d/m/Y', trim((string) $f['date']));
        if ($doc_date !== false && $d < $doc_date) {
            $db->rollBack();
            return ['error' => t('La fecha de la devolución es anterior a la de la factura.')];
        }
        $lock_message = period_locked($db, $company_id, $d);
        if ($lock_message !== null) {
            $db->rollBack();
            return ['error' => $lock_message];
        }

        // What is returned, line by line. An item cannot go back more than was sold and not yet returned.
        $remaining = [];
        $invoice_lines = sales_return_lines($db, $company_id, $doc_prefix, $invoice_num);
        foreach ($invoice_lines as $l) {
            $remaining[$l['item_code']] = ($remaining[$l['item_code']] ?? 0.0) + (float) $l['qty'];
        }
        foreach ($invoice_lines as $l) {
            if (isset($remaining[$l['item_code'] . '#dev'])) {
                continue;
            }
            $remaining[$l['item_code'] . '#dev'] = (float) $l['returned'];
            $remaining[$l['item_code']] -= (float) $l['returned'];
        }
        $lines = [];
        foreach ($invoice_lines as $n => $l) {
            $c = field($quantities[trim((string) $l['line_no'])] ?? '');
            if ($c === '' || (float) $c == 0.0) {
                continue;
            }
            $qty = positive_decimal($c);
            if ($qty === null || $qty > 99999) {
                $db->rollBack();
                return ['error' => str_replace('{n}', (string) ($n + 1), t('Cantidad no válida en el ítem {n}.'))];
            }
            if ((float) $l['discount'] > 0) {
                $db->rollBack();
                return ['error' => str_replace('{n}', (string) ($n + 1), t('El ítem {n} tiene descuento: su devolución aún no está verificada.'))];
            }
            $remaining[$l['item_code']] -= $qty;
            if ($remaining[$l['item_code']] < -0.0001) {
                $db->rollBack();
                return ['error' => str_replace('{n}', (string) ($n + 1), t('La cantidad del ítem {n} supera lo que se vendió y no se ha devuelto.'))];
            }
            $base = (float) $l['value'];
            $rate = (float) $l['rate'];
            $lines[] = [
                'item_code' => $l['item_code'], 'qty' => $qty, 'base' => $base, 'rate' => $rate, 'vat' => round($qty * $base * $rate / 100, 2),
                'cost' => max(0.0, (float) $l['cost']), 'center' => $l['center'] === '' ? '00' : $l['center'], 'type' => trim((string) $l['type']),
            ];
        }
        if (!$lines) {
            $db->rollBack();
            return ['error' => t('Indique la cantidad de al menos un ítem.')];
        }
        $base_total = 0.0;
        $vat_total = 0.0;
        foreach ($lines as $l) {
            $base_total += $l['qty'] * $l['base'];
            $vat_total += $l['vat'];
        }

        // Number: the next one of the type, after the counter of the type and the highest document
        $num = next_number_for_type($db, $company_id, '6');
        $year = $d->format('Y');
        $due = $d->modify('+' . (int) $payment_row['T616DiasInc'] . ' days')->format('d/m/Y');

        $header = [
            'T611CodEmpresa' => $company_id, 'T611Agno' => $year, 'T611TipoTransaccion' => '6', 'T611NumeroDoc' => $num, 'T611Fecha' => $date,
            'T611CodProveedor' => $f['party'], 'T611ValorBase' => legacy_num($base_total, 4), 'T611ValorIVA' => legacy_num($vat_total, 2),
            'T611ValorDescuento' => '0', 'T611ValorTtFactura' => legacy_num($base_total + $vat_total, 4), 'T611FormaPago' => $payment,
            'T611FechaVence' => $due, 'T611Concepto' => ' ', 'T611Prefijo' => $doc_prefix, 'T611NumFactura' => $invoice_num, 'T611Anular' => 'N',
            'T611FechaPago' => ' ', 'T611ValorReteRenta' => '0', 'T611ValorReteIVA' => '0', 'T611ValorReteICA' => '0', 'T611PorcRenta' => '0',
            'T611PorcIVA' => '0', 'T611PorcICA' => '0', 'T611Consecutivo' => ' ', 'T611Digita' => $entered_by, 'T611Impresa' => 'N',
            'T611OtroDescuento' => '0', 'T611Hora' => date('H:i'), 'T611FechaDevol' => ' ', 'T611Obra' => ' ',
            'T611Vendedor' => trim((string) $header_row['T604Vendedor']) === '' ? ' ' : trim((string) $header_row['T604Vendedor']), 'T611Conductor' => ' ',
            'T611PorcOtro' => '0', 'T611CUFE' => ' ', 'T611PdfCufe' => ' ', 'T611PorcAUIAdmon' => '0', 'T611AUIAdmon' => '0',
            'T611PorcAUIImprevisto' => '0', 'T611AUIImprevisto' => '0', 'T611PorcAUIUtilidad' => '0', 'T611AUIUtilidad' => '0',
            'T611PorcAUIIVA' => '0', 'T611AUIIVA' => '0', 'T611DescuentoCom' => '0', 'T611Moneda' => 'COP',
        ];
        $db->prepare('INSERT INTO T611DOCUMENTO (' . implode(', ', array_keys($header)) . ') VALUES (' . implode(', ', array_fill(0, count($header), '?')) . ')')
            ->execute(array_values($header));

        foreach ($lines as $i => $l) {
            $mov = [
                'T612CodEmpresa' => $company_id, 'T612Agno' => $year, 'T612TipoTransaccion' => '6', 'T612NumeroDoc' => $num, 'T612CodArticulo' => $l['item_code'],
                'T612Cantidad' => legacy_num($l['qty'], 4), 'T612ValorArticulo' => legacy_num($l['cost'], 4), 'T612ValorDescuento' => '0',
                'T612ValorIVA' => legacy_num($l['vat'], 2), 'T612SubCodConcepto' => ' ', 'T612Consecutivo' => (string) ($i + 1),
                'T612CodCentro' => $l['center'], 'T612PorcIVA' => legacy_num($l['rate'], 2), 'T612Digita' => $entered_by,
                'T612ValorVenta' => legacy_num($l['base'], 4), 'T612CodMetro2' => ' ', 'T612NumMetro2' => ' ', 'T612ValorFlete' => '0',
                'T612ValorVentaAct' => '0', 'T612FechaVence' => '01/01/1900', 'T612Lote' => ' ', 'T612ValorBaseCafe' => '0',
                'T612BonificaCafe' => '0', 'T612PorcTara' => '0', 'T612PorcFR' => '0', 'T612PorcHumedad' => '0', 'T612PorcKgBruto' => '0',
                'T612BrocaBase' => '0', 'T612Broca' => '0', 'T612HumedBase' => '0', 'T612BaseFR' => '0', 'T612PorcIVA2' => '0', 'T612ValorIVA2' => '0',
            ];
            $db->prepare('INSERT INTO T612MOVIMIENTO (' . implode(', ', array_keys($mov)) . ') VALUES (' . implode(', ', array_fill(0, count($mov), '?')) . ')')
                ->execute(array_values($mov));
        }

        stock_in($db, $company_id, $lines);
        $notice = null;
        if ($online) {
            post_sales_return($db, $company_id, $f, $lines, $num, $payment, $payment_row['T616Cartera'] === 'S', $d);
        }
        audit($db, $entered_by, 'DEVOLUCION CLIENTE ' . $num . ' FACTURA ' . $doc_prefix . '-' . $invoice_num);
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
        error_log('sori: return not saved: ' . $ex->getMessage());
        return ['error' => t('No se pudo guardar la devolución.')];
    } finally {
        number_unlock($db, $lock);
    }
    return ['keys' => ['k0' => $company_id, 'k1' => $year, 'k2' => '6', 'k3' => $num], 'notice' => $notice];
}

// Adds the returned quantity to the entries of the stock totals of each warehouse item
function stock_in(PDO $db, string $company_id, array $lines): void
{
    $sel = $db->prepare('SELECT T637CantEntrada, T637TotalEntrada FROM T637TOTALES WHERE T637CodEmpresa = ? AND T637CodConcepto = ? AND T637CodCentro = ? FOR UPDATE');
    $upd = $db->prepare('UPDATE T637TOTALES SET T637CantEntrada = ?, T637TotalEntrada = ? WHERE T637CodEmpresa = ? AND T637CodConcepto = ? AND T637CodCentro = ?');
    $ins = $db->prepare("INSERT INTO T637TOTALES (T637CodEmpresa, T637CodConcepto, T637CodCentro, T637CantEntrada, T637TotalEntrada, T637CantSalida, T637TotalSalida) VALUES (?, ?, ?, ?, ?, '0', '0')");
    foreach ($lines as $l) {
        if ($l['type'] !== '1') {
            continue;
        }
        $value = $l['qty'] * $l['cost'];
        $sel->execute([$company_id, $l['item_code'], $l['center']]);
        $r = $sel->fetch();
        if ($r) {
            $upd->execute([legacy_num((float) $r['T637CantEntrada'] + $l['qty'], 4), legacy_num((float) $r['T637TotalEntrada'] + $value, 4), $company_id, $l['item_code'], $l['center']]);
        } else {
            $ins->execute([$company_id, $l['item_code'], $l['center'], legacy_num($l['qty'], 4), legacy_num($value, 4)]);
        }
    }
}
