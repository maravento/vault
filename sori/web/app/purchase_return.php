<?php
// SORI writes: a return of goods to a supplier. It follows the legacy program, checked on real data:
// the return is a document of type 3 (T611 with lines in T612) that points to the purchase by its type and number,
// the returned quantities leave the stock totals and, when the company posts online, the accounting document
// credits the stock accounts and the tax, and debits the means of payment, less the withholding tax given back.
// FILE: app/purchase_return.php
declare(strict_types=1);

const SUPPLIER_RETURN_TYPE = '3';

// A purchase with its supplier and what was already returned. Null when it does not exist.
function purchase_document(PDO $db, string $company_id, string $type, string $num, string $year = ''): ?array
{
    $st = $db->prepare(
        "SELECT h.T611Agno AS doc_year, h.T611TipoTransaccion AS type, h.T611NumeroDoc AS number, h.T611Fecha AS date, h.T611CodProveedor AS supplier,
                h.T611NumFactura AS invoice, h.T611Anular AS cancelled, h.T611PorcRenta AS withholding_percent, h.T611ValorTtFactura AS total,
                h.T611ValorReteRenta AS withholding_income, h.T611ValorReteIVA AS withholding_vat, h.T611ValorReteICA AS withholding_ica, h.T611FechaVence AS due,
                p.T616Cartera AS credit, p.T616Nombre AS payment_name, " . party_name('t') . " AS name
         FROM T611DOCUMENTO h
         LEFT JOIN T616TIPOFORMAPAGO p ON p.T616Codigo = h.T611FormaPago
         JOIN T617TIPOTRANSACCION x ON x.T617Codigo = h.T611TipoTransaccion AND x.T617Tipo = 'E' AND x.T617Nombre LIKE 'COMPRA%'
         LEFT JOIN T12TERCERO t ON t.T12CodEmpresa = h.T611CodEmpresa AND t.T12Nit = h.T611CodProveedor
         WHERE h.T611CodEmpresa = ? AND h.T611TipoTransaccion = ? AND h.T611NumeroDoc = ?
           AND (? = '' OR h.T611Agno = ?)
         ORDER BY h.T611Agno DESC LIMIT 1"
    );
    $st->execute([$company_id, $type, $num, $year, $year]);
    $c = $st->fetch();
    return $c ?: null;
}

// The lines of a purchase with what is left to return of each one
function purchase_return_lines(PDO $db, string $company_id, array $purchase): array
{
    $st = $db->prepare(
        'SELECT m.T612Consecutivo AS line_no, m.T612CodArticulo AS item_code, m.T612Cantidad AS qty, m.T612ValorArticulo AS cost, m.T612PorcIVA AS rate,
                m.T612ValorDescuento AS discount, TRIM(m.T612CodCentro) AS center,
                (SELECT c.T603Nombre FROM T603CONCEPTO c WHERE c.T603CodEmpresa = m.T612CodEmpresa AND c.T603Codigo = m.T612CodArticulo LIMIT 1) AS name,
                (SELECT TRIM(c.T603Tipo) FROM T603CONCEPTO c WHERE c.T603CodEmpresa = m.T612CodEmpresa AND c.T603Codigo = m.T612CodArticulo LIMIT 1) AS item_type,
                (SELECT COALESCE(SUM(' . sql_num('r.T612Cantidad') . "), 0) FROM T612MOVIMIENTO r
                   JOIN T611DOCUMENTO h ON h.T611CodEmpresa = r.T612CodEmpresa AND h.T611Agno = r.T612Agno
                        AND h.T611TipoTransaccion = r.T612TipoTransaccion AND h.T611NumeroDoc = r.T612NumeroDoc
                  WHERE h.T611TipoTransaccion = '3' AND h.T611Anular <> 'S' AND h.T611CodEmpresa = m.T612CodEmpresa
                    AND h.T611Prefijo = m.T612TipoTransaccion AND h.T611NumFactura = m.T612NumeroDoc AND r.T612CodArticulo = m.T612CodArticulo) AS returned
         FROM T612MOVIMIENTO m WHERE m.T612CodEmpresa = ? AND m.T612Agno = ? AND m.T612TipoTransaccion = ? AND m.T612NumeroDoc = ?
         ORDER BY CAST(m.T612Consecutivo AS UNSIGNED)"
    );
    $st->execute([$company_id, $purchase['doc_year'], $purchase['type'], $purchase['number']]);
    return $st->fetchAll();
}

// Accounting document of a return to a supplier: the mirror of the purchase, with its own setup row (process 2, type 3)
function post_purchase_return(PDO $db, string $company_id, array $purchase, array $lines, string $num, string $payment, bool $credit, float $withholding_amount, DateTimeImmutable $d): void
{
    $year = $d->format('Y');
    $date = $d->format('d/m/Y');
    $group = $db->prepare('SELECT T623CodGrupo FROM T623CONCEPTOxGRUPO WHERE T623CodEmpresa = ? AND T623CodConcepto = ? ORDER BY T623CodGrupo LIMIT 1');
    $record = $db->prepare("SELECT * FROM T620CONCEPTOCONTAB WHERE T620CodEmpresa = ? AND T620Agno = ? AND T620CodGrupo = ? AND T620CodProceso = '2' AND T620TipoTransaccion = '3' LIMIT 1");
    $credits = [];
    $doc_type = null;
    $debit_account = null;
    $withholding_account = '';
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
        $credits[$acct] = ($credits[$acct] ?? 0.0) + $l['qty'] * $l['cost'];
        if ($l['vat'] > 0) {
            $tax_account = trim((string) $c["T620CuentaImp$idx"]);
            if ($tax_account === '') {
                throw new DocumentError(str_replace('{n}', (string) ($n + 1), t('No hay cuenta contable para el IVA del ítem {n}.')));
            }
            $credits[$tax_account] = ($credits[$tax_account] ?? 0.0) + $l['vat'];
        }
        $col = $credit ? 'T620Credito' : ($payment === PAYMENT_BANK ? 'T620Banco' : ($payment === PAYMENT_CASH ? 'T620Caja' : null));
        $account = $col === null ? '' : trim((string) $c[$col]);
        if ($account === '' || ($debit_account !== null && $debit_account !== $account)) {
            throw new DocumentError(t('La forma de pago no tiene una cuenta contable verificada.'));
        }
        $debit_account = $account;
        $withholding_account = trim((string) $c['T620ReteRenta']);
    }
    $entry_lines = [];
    $total = 0.0;
    foreach ($credits as $acct => $value) {
        $r = round($value, 0);
        if ($r != 0) {
            $entry_lines[] = [$acct, 0.0, $r, ' '];
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
    array_unshift($entry_lines, [$debit_account, $total - $withholding_rounded, 0.0, $num]);
    if ($withholding_rounded > 0) {
        array_splice($entry_lines, 1, 0, [[$withholding_account, $withholding_rounded, 0.0, ' ']]);
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
            $company_id, $year, $doc_type, $num, $l[0], (string) $k, $date, $lines[0]['center'], $purchase['supplier'], ' ', ' ',
            legacy_num((float) $l[1], 0), legacy_num((float) $l[2], 0), $l[3], ' ', '01/01/1900', '', '',
        ]);
    }
}

// Takes the returned quantities out of the stock totals of each warehouse item
function stock_out_for_return(PDO $db, string $company_id, array $lines): void
{
    $sel = $db->prepare('SELECT T637CantEntrada, T637TotalEntrada, T637CantSalida, T637TotalSalida FROM T637TOTALES WHERE T637CodEmpresa = ? AND T637CodConcepto = ? AND T637CodCentro = ? FOR UPDATE');
    $upd = $db->prepare('UPDATE T637TOTALES SET T637CantSalida = ?, T637TotalSalida = ? WHERE T637CodEmpresa = ? AND T637CodConcepto = ? AND T637CodCentro = ?');
    // Quantity by item first: two lines of the same item draw from the same stock
    $requested = [];
    foreach ($lines as $l) {
        if ($l['type'] === '1') {
            $k = $l['item_code'] . '|' . $l['center'];
            $requested[$k] = ($requested[$k] ?? 0.0) + $l['qty'];
        }
    }
    foreach ($lines as $l) {
        if ($l['type'] !== '1') {
            continue;
        }
        $sel->execute([$company_id, $l['item_code'], $l['center']]);
        $r = $sel->fetch();
        $available = $r ? (float) $r['T637CantEntrada'] - (float) $r['T637CantSalida'] : 0.0;
        if ($available + 0.0001 < $requested[$l['item_code'] . '|' . $l['center']]) {
            throw new DocumentError(str_replace('{c}', $l['item_code'], t('No hay existencias suficientes de {c} para devolver.')));
        }
        $upd->execute([
            legacy_num((float) $r['T637CantSalida'] + $l['qty'], 4), legacy_num((float) $r['T637TotalSalida'] + $l['qty'] * $l['cost'], 4),
            $company_id, $l['item_code'], $l['center'],
        ]);
    }
}

// Saves a return to a supplier. One transaction: if anything fails, nothing is saved.
// $in['quantity'] maps the line number of the purchase to the quantity returned.
function purchase_return_save(PDO $db, string $entered_by, array $in): array
{
    $company_id = company_code($db);
    $entered_by = substr($entered_by, 0, 20);
    $purchase_type = field($in['type'] ?? '');
    $purchase_number = field($in['number'] ?? '');
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

    $lock = number_lock($db, 'devprov', $company_id, SUPPLIER_RETURN_TYPE);
    if ($lock === null) {
        return ['error' => t('No se pudo asignar el número. Intente de nuevo.')];
    }
    try {
        $db->beginTransaction();
        $purchase = purchase_document($db, $company_id, $purchase_type, $purchase_number);
        if ($purchase === null) {
            $db->rollBack();
            return ['error' => t('Compra no encontrada.')];
        }
        // The purchase is locked while its lines are read, so two returns cannot take the same quantity
        $st = $db->prepare('SELECT 1 FROM T611DOCUMENTO WHERE T611CodEmpresa = ? AND T611Agno = ? AND T611TipoTransaccion = ? AND T611NumeroDoc = ? FOR UPDATE');
        $st->execute([$company_id, $purchase['doc_year'], $purchase['type'], $purchase['number']]);
        if ($purchase['cancelled'] === 'S') {
            $db->rollBack();
            return ['error' => t('La compra está anulada.')];
        }
        $doc_date = DateTimeImmutable::createFromFormat('!d/m/Y', trim((string) $purchase['date']));
        if ($doc_date !== false && $d < $doc_date) {
            $db->rollBack();
            return ['error' => t('La fecha de la devolución es anterior a la de la compra.')];
        }
        $lock_message = period_locked($db, $company_id, $d);
        if ($lock_message !== null) {
            $db->rollBack();
            return ['error' => $lock_message];
        }

        $purchase_lines = purchase_return_lines($db, $company_id, $purchase);
        // What is left of each item: bought minus returned (the returned amount is by item, the same on each of its lines)
        $remaining = [];
        $returned = [];
        foreach ($purchase_lines as $l) {
            $remaining[$l['item_code']] = ($remaining[$l['item_code']] ?? 0.0) + (float) $l['qty'];
            $returned[$l['item_code']] = (float) $l['returned'];
        }
        foreach ($returned as $item_code => $v) {
            $remaining[$item_code] -= $v;
        }
        $lines = [];
        foreach ($purchase_lines as $n => $l) {
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
                return ['error' => str_replace('{n}', (string) ($n + 1), t('La cantidad del ítem {n} supera lo que se compró y no se ha devuelto.'))];
            }
            $cost = (float) $l['cost'];
            $rate = (float) $l['rate'];
            $lines[] = [
                'item_code' => $l['item_code'], 'qty' => $qty, 'cost' => $cost, 'rate' => $rate, 'vat' => round($qty * $cost * $rate / 100, 2),
                'center' => $l['center'] === '' ? '00' : $l['center'], 'type' => (string) $l['item_type'],
            ];
        }
        if (!$lines) {
            $db->rollBack();
            return ['error' => t('Indique la cantidad de al menos un ítem.')];
        }
        $base_total = 0.0;
        $vat_total = 0.0;
        foreach ($lines as $l) {
            $base_total += $l['qty'] * $l['cost'];
            $vat_total += $l['vat'];
        }
        $withholding_percent = (float) trim((string) $purchase['withholding_percent']);
        $withholding_amount = round($base_total * $withholding_percent / 100, 2);

        $num = next_number_for_type($db, $company_id, SUPPLIER_RETURN_TYPE);
        $year = $d->format('Y');
        $due = $d->modify('+' . (int) $payment_row['T616DiasInc'] . ' days')->format('d/m/Y');
        $header = [
            'T611CodEmpresa' => $company_id, 'T611Agno' => $year, 'T611TipoTransaccion' => SUPPLIER_RETURN_TYPE, 'T611NumeroDoc' => $num, 'T611Fecha' => $date,
            'T611CodProveedor' => $purchase['supplier'], 'T611ValorBase' => legacy_num($base_total, 4), 'T611ValorIVA' => legacy_num($vat_total, 2),
            'T611ValorDescuento' => '0', 'T611ValorTtFactura' => legacy_num($base_total + $vat_total, 4), 'T611FormaPago' => $payment,
            'T611FechaVence' => $due, 'T611Concepto' => ' ', 'T611Prefijo' => $purchase['type'], 'T611NumFactura' => $purchase['number'], 'T611Anular' => 'N',
            'T611FechaPago' => ' ', 'T611ValorReteRenta' => legacy_num($withholding_amount, 2), 'T611ValorReteIVA' => '0', 'T611ValorReteICA' => '0',
            'T611PorcRenta' => legacy_num($withholding_percent, 2), 'T611PorcIVA' => '0', 'T611PorcICA' => '0', 'T611Consecutivo' => ' ', 'T611Digita' => $entered_by,
            'T611Impresa' => 'N', 'T611OtroDescuento' => '0', 'T611Hora' => date('H:i'), 'T611FechaDevol' => $date, 'T611Obra' => ' ',
            'T611Vendedor' => ' ', 'T611Conductor' => ' ', 'T611PorcOtro' => '0', 'T611CUFE' => ' ', 'T611PdfCufe' => ' ', 'T611PorcAUIAdmon' => '0',
            'T611AUIAdmon' => '0', 'T611PorcAUIImprevisto' => '0', 'T611AUIImprevisto' => '0', 'T611PorcAUIUtilidad' => '0', 'T611AUIUtilidad' => '0',
            'T611PorcAUIIVA' => '0', 'T611AUIIVA' => '0', 'T611DescuentoCom' => '0', 'T611Moneda' => 'COP',
        ];
        $db->prepare('INSERT INTO T611DOCUMENTO (' . implode(', ', array_keys($header)) . ') VALUES (' . implode(', ', array_fill(0, count($header), '?')) . ')')
            ->execute(array_values($header));
        foreach ($lines as $i => $l) {
            $mov = [
                'T612CodEmpresa' => $company_id, 'T612Agno' => $year, 'T612TipoTransaccion' => SUPPLIER_RETURN_TYPE, 'T612NumeroDoc' => $num, 'T612CodArticulo' => $l['item_code'],
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
        }
        stock_out_for_return($db, $company_id, $lines);
        if ($online) {
            post_purchase_return($db, $company_id, $purchase, $lines, $num, $payment, $payment_row['T616Cartera'] === 'S', $withholding_amount, $d);
        }
        audit($db, $entered_by, 'DEVOLUCION PROVEEDOR ' . $num . ' COMPRA ' . $purchase['type'] . '-' . $purchase['number']);
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
        error_log('sori: supplier return not saved: ' . $ex->getMessage());
        return ['error' => t('No se pudo guardar la devolución.')];
    } finally {
        number_unlock($db, $lock);
    }
    return ['keys' => ['k0' => $company_id, 'k1' => $year, 'k2' => SUPPLIER_RETURN_TYPE, 'k3' => $num], 'notice' => null];
}
