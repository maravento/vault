<?php
// SORI writes: the sales invoice. It follows the rules of the legacy program, checked on real data:
// numbering by prefix and resolution range, locked months and days, credit limit, overdue invoices, cost,
// stock, the stock totals and, when the company posts online, the accounting document.
// FILE: app/invoice.php
declare(strict_types=1);

// Payment forms with a verified account: cash and card. A credit form (Cartera = S) uses the credit account.
const PAYMENT_CASH = '1';
const PAYMENT_BANK = '5';

// An error meant for the user: the message is already translated
class DocumentError extends RuntimeException
{
}

// Message when the month or the day of a date is locked in the accounting, or null
function period_locked(PDO $db, string $company_id, DateTimeImmutable $d): ?string
{
    $year = $d->format('Y');
    $st = $db->prepare('SELECT COUNT(*) FROM T118MESBLOQUEADO WHERE T118CodEmpresa = ? AND T118Agno = ? AND CAST(T118Mes AS UNSIGNED) = ?');
    $st->execute([$company_id, $year, (int) $d->format('n')]);
    if ((int) $st->fetchColumn()) {
        return t('El mes se encuentra bloqueado en contabilidad.');
    }
    $st = $db->prepare('SELECT COUNT(*) FROM T154BLOQUEAFECHA WHERE T154CodEmpresa = ? AND T154Agno = ? AND T154Fecha = ?');
    $st->execute([$company_id, $year, $d->format('d/m/Y')]);
    if ((int) $st->fetchColumn()) {
        return t('El día se encuentra bloqueado en contabilidad.');
    }
    return null;
}

// Checks that do not write anything. Returns a message, or null when the invoice may be saved.
function invoice_check(PDO $db, array $v, array $cfg): ?string
{
    $company_id = $v['company_id'];

    $lock_message = period_locked($db, $company_id, $v['d']);
    if ($lock_message !== null) {
        return $lock_message;
    }

    // Credit: the open invoices of the client, on credit forms only
    if ($v['credit']) {
        $open_filter = 'FROM T604FACTURA f JOIN T616TIPOFORMAPAGO p ON p.T616Codigo = f.T604CodFormaPago '
            . "WHERE f.T604CodEmpresa = ? AND f.T604CodTercero = ? AND f.T604Cancelado <> 'S' AND p.T616Cartera = 'S'";
        $balance_sql = '(' . sql_num('f.T604Total') . ' - ' . sql_num('f.T604ValorPagado') . ' - ' . returned_sql('f') . ')';
        if (($cfg['T10ValidarCupo'] ?? 'N') === 'S') {
            $st = $db->prepare('SELECT ' . sql_num('T12Cupo') . ' FROM T12TERCERO WHERE T12CodEmpresa = ? AND T12Nit = ?');
            $st->execute([$company_id, $v['tax_id']]);
            $credit_limit = (float) $st->fetchColumn();
            $st = $db->prepare("SELECT COALESCE(SUM($balance_sql), 0) $open_filter");
            $st->execute([$company_id, $v['tax_id']]);
            if ((float) $st->fetchColumn() + $v['total'] > $credit_limit) {
                return t('El crédito del cliente no alcanza para pagar la factura.');
            }
        }
        if (($cfg['T10ValidarTiempo'] ?? 'N') === 'S') {
            $st = $db->prepare("SELECT COUNT(*) $open_filter AND $balance_sql > 0 AND STR_TO_DATE(f.T604FechaVence, '%d/%m/%Y') < CURDATE()");
            $st->execute([$company_id, $v['tax_id']]);
            if ((int) $st->fetchColumn()) {
                return t('El cliente tiene facturas vencidas.');
            }
        }
    }

    // Cost and stock, item by item
    $requested = [];
    foreach ($v['items'] as $i => $it) {
        $n = (string) ($i + 1);
        if (($cfg['T10ValidarCosto'] ?? 'N') === 'S' && $it['cost'] > 0
            && ($it['qty'] * $it['base'] - $it['disc']) / $it['qty'] < $it['cost']) {
            return str_replace('{n}', $n, t('El valor del ítem {n} es menor al costo.'));
        }
        if ($it['type'] === '1' && ($cfg['T10FacturaNegativo'] ?? 'N') !== 'S') {
            $requested[$it['item_code']] = ($requested[$it['item_code']] ?? 0.0) + $it['qty'];
            $st = $db->prepare('SELECT ' . sql_num('T637CantEntrada') . ' - ' . sql_num('T637CantSalida')
                . " FROM T637TOTALES WHERE T637CodEmpresa = ? AND T637CodConcepto = ? AND T637CodCentro = '00' FOR UPDATE");
            $st->execute([$company_id, $it['item_code']]);
            if ((float) $st->fetchColumn() < $requested[$it['item_code']]) {
                return str_replace('{n}', $n, t('No hay existencias suficientes para el ítem {n}.'));
            }
        }
    }
    return null;
}

// Next number of the prefix. When the prefix has resolution ranges, the number must fall inside a current one.
// Returns [number, notice or null].
function invoice_number(PDO $db, string $company_id, string $doc_prefix, DateTimeImmutable $d): array
{
    $st = $db->prepare('SELECT COALESCE(MAX(CAST(T604NumFactura AS UNSIGNED)), 0) FROM T604FACTURA WHERE T604CodEmpresa = ? AND T604Prefijo = ?');
    $st->execute([$company_id, $doc_prefix]);
    $next_number = (int) $st->fetchColumn() + 1;

    $st = $db->prepare('SELECT T704FechaIni, T704FechaFin, T704NumeroIni, T704NumeroFin, T704Avisar FROM T704RANGOFACTURA WHERE T704CodEmpresa = ? AND T704CodPrefijo = ?');
    $st->execute([$company_id, $doc_prefix]);
    $ranges = $st->fetchAll();
    if (!$ranges) {
        return [(string) $next_number, null];
    }
    foreach ($ranges as $r) {
        $ini = DateTimeImmutable::createFromFormat('!d/m/Y', trim((string) $r['T704FechaIni']));
        $end_date = DateTimeImmutable::createFromFormat('!d/m/Y', trim((string) $r['T704FechaFin']));
        if ($ini === false || $end_date === false || $d < $ini || $d > $end_date) {
            continue;
        }
        $n = max($next_number, (int) $r['T704NumeroIni']);
        $until = (int) $r['T704NumeroFin'];
        if ($n > $until) {
            continue;
        }
        $remaining = $until - $n;
        $notice = $remaining <= (int) trim((string) $r['T704Avisar'])
            ? str_replace('{n}', (string) $remaining, t('Quedan {n} números en el rango del prefijo.'))
            : null;
        return [(string) $n, $notice];
    }
    throw new DocumentError(t('No hay un rango de numeración vigente para el prefijo.'));
}

// Accounting document of a sale. The configuration row is chosen by the year, the accounting group of
// the item and the prefix. The number of the document is the number of the invoice.
function post_sale(PDO $db, array $v, string $num): void
{
    $company_id = $v['company_id'];
    $year = $v['d']->format('Y');
    $center = '00';
    $group = $db->prepare('SELECT T623CodGrupo FROM T623CONCEPTOxGRUPO WHERE T623CodEmpresa = ? AND T623CodConcepto = ? ORDER BY T623CodGrupo LIMIT 1');
    $record = $db->prepare("SELECT * FROM T620CONCEPTOCONTAB WHERE T620CodEmpresa = ? AND T620Agno = ? AND T620CodGrupo = ? AND T620CodProceso = '0' AND T620TipoTransaccion = ? LIMIT 1");

    $credits = [];   // account => amount, in the order they appear
    $costs = [];     // [debit account, credit account] => amount
    $doc_type = null;
    $debit_account = null;
    foreach ($v['items'] as $i => $it) {
        $n = (string) ($i + 1);
        $group->execute([$company_id, $it['item_code']]);
        $g = $group->fetchColumn();
        if ($g === false) {
            throw new DocumentError(str_replace('{n}', $n, t('El ítem {n} no tiene grupo contable.')));
        }
        $record->execute([$company_id, $year, $g, $v['doc_prefix']]);
        $c = $record->fetch();
        if (!$c) {
            throw new DocumentError(str_replace('{n}', $n, t('No hay configuración contable para el prefijo y el grupo del ítem {n}.')));
        }
        $td = trim((string) $c['T620CodTipoDocContab']);
        if ($td === '' || ($doc_type !== null && $doc_type !== $td)) {
            throw new DocumentError(t('Los ítems usan tipos de documento contable distintos.'));
        }
        $doc_type = $td;

        // The tax rate of the item picks the income, tax and cost accounts: rates 1 to 4 of the row
        $idx = null;
        for ($k = 1; $k <= 4; $k++) {
            if (trim((string) $c["T620Cuenta$k"]) !== '' && abs((float) $c["T620PorcIVA$k"] - $it['rate']) < 0.01) {
                $idx = $k;
                break;
            }
        }
        if ($idx === null) {
            throw new DocumentError(str_replace('{n}', $n, t('No hay cuenta contable para el IVA del ítem {n}.')));
        }
        $net = $it['qty'] * $it['base'] - $it['disc'];
        $credits[trim((string) $c["T620Cuenta$idx"])] = ($credits[trim((string) $c["T620Cuenta$idx"])] ?? 0.0) + $net;
        if ($it['vat'] > 0) {
            $tax_account = trim((string) $c["T620CuentaImp$idx"]);
            if ($tax_account === '') {
                throw new DocumentError(str_replace('{n}', $n, t('No hay cuenta contable para el IVA del ítem {n}.')));
            }
            $credits[$tax_account] = ($credits[$tax_account] ?? 0.0) + $it['vat'];
        }
        $cost = $it['qty'] * $it['cost'];
        if ($cost > 0) {
            $suf = $idx === 1 ? '' : (string) ($idx - 1);
            $debit_cost_account = trim((string) $c["T620CostoDeb$suf"]);
            $credit_cost_account = trim((string) $c["T620CostoCred$suf"]);
            if ($debit_cost_account === '' || $credit_cost_account === '') {
                throw new DocumentError(str_replace('{n}', $n, t('No hay cuenta de costo para el ítem {n}.')));
            }
            $costs[$debit_cost_account . '|' . $credit_cost_account] = ($costs[$debit_cost_account . '|' . $credit_cost_account] ?? 0.0) + $cost;
        }

        // The account that receives the payment: credit, card or cash
        $col = $v['credit'] ? 'T620Credito' : ($v['payment'] === PAYMENT_BANK ? 'T620Banco' : ($v['payment'] === PAYMENT_CASH ? 'T620Caja' : null));
        $acct = $col === null ? '' : trim((string) $c[$col]);
        if ($acct === '' || ($debit_account !== null && $debit_account !== $acct)) {
            throw new DocumentError(t('La forma de pago no tiene una cuenta contable verificada.'));
        }
        $debit_account = $acct;
    }

    // Lines. Each amount is rounded to whole pesos and the debit is the sum of the credits, so the document balances.
    $lines = [];
    $total = 0.0;
    foreach ($credits as $acct => $value) {
        $r = round($value, 0);
        if ($r != 0) {
            $lines[] = [$acct, 0.0, $r, '0'];
            $total += $r;
        }
    }
    foreach ($costs as $pair => $value) {
        [$debit_cost_account, $credit_cost_account] = explode('|', $pair);
        $r = round($value, 0);
        if ($r != 0) {
            $lines[] = [$debit_cost_account, $r, 0.0, ' '];
            $lines[] = [$credit_cost_account, 0.0, $r, ' '];
        }
    }
    if (!$lines) {
        return;
    }
    $lines[] = [$debit_account, $total, 0.0, ' ', $num];

    $st = $db->prepare('SELECT COUNT(*) FROM T104DOCUMENTO WHERE T104CodEmpresa = ? AND T104Agno = ? AND T104CodTipoDoc = ? AND T104NumeroDoc = ?');
    $st->execute([$company_id, $year, $doc_type, $num]);
    if ((int) $st->fetchColumn()) {
        throw new DocumentError(str_replace('{n}', $num, t('Ya existe el documento contable {n}.')));
    }
    $db->prepare(
        'INSERT INTO T104DOCUMENTO (T104CodEmpresa, T104Agno, T104CodTipoDoc, T104NumeroDoc, T104Fecha, T104Concepto, T104Anulado,
            T104Aplicacion, T104ValorTotal, T104NombreCheque, NumeroAnterior, NuevoNumero, T104Bloqueado)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    )->execute([$company_id, $year, $doc_type, $num, $v['date'], ' ', 'N', 'FACTURACIO', ' ', ' ', '', '', 'N']);

    $ins = $db->prepare(
        'INSERT INTO T106MOVIMIENTO (T106CodEmpresa, T106Agno, T106CodTipoDoc, T106NumeroDoc, T106CodCta, T106ConsecCta, T106Fecha,
            T106CodCentro, T106Nit, T106Referencia, T106Detalle, T106ValorDebito, T106ValorCredito, T106CodSubTipoDoc,
            T106SubNumeroDoc, T106FechaConciliado, Anterior, Nuevo)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    foreach ($lines as $k => $l) {
        $ins->execute([
            $company_id, $year, $doc_type, $num, $l[0], (string) $k, $v['date'], $center, $v['tax_id'], $l[3], ' ',
            legacy_num((float) $l[1], 0), legacy_num((float) $l[2], 0), $l[4] ?? ' ',
            isset($l[4]) ? 'SORI:SALE:' . $v['doc_prefix'] : ' ', '01/01/1900', '', '',
        ]);
    }
}

// Adds the sold quantity to the stock totals of each warehouse item
function stock_out(PDO $db, string $company_id, array $items): void
{
    $sel = $db->prepare("SELECT T637CantSalida, T637TotalSalida FROM T637TOTALES WHERE T637CodEmpresa = ? AND T637CodConcepto = ? AND T637CodCentro = '00' FOR UPDATE");
    $upd = $db->prepare("UPDATE T637TOTALES SET T637CantSalida = ?, T637TotalSalida = ? WHERE T637CodEmpresa = ? AND T637CodConcepto = ? AND T637CodCentro = '00'");
    $ins = $db->prepare("INSERT INTO T637TOTALES (T637CodEmpresa, T637CodConcepto, T637CodCentro, T637CantEntrada, T637TotalEntrada, T637CantSalida, T637TotalSalida) VALUES (?, ?, '00', '0', '0', ?, ?)");
    foreach ($items as $it) {
        if ($it['type'] !== '1') {
            continue;
        }
        $qty = $it['qty'];
        $value = $it['qty'] * $it['cost'];
        $sel->execute([$company_id, $it['item_code']]);
        $r = $sel->fetch();
        if ($r) {
            $upd->execute([
                legacy_num((float) $r['T637CantSalida'] + $qty, 4), legacy_num((float) $r['T637TotalSalida'] + $value, 4), $company_id, $it['item_code'],
            ]);
        } else {
            $ins->execute([$company_id, $it['item_code'], legacy_num($qty, 4), legacy_num($value, 4)]);
        }
    }
}

// Saves a sales invoice: header, items, stock totals, accounting document when the company posts online, and audit line.
// One transaction: if anything fails, nothing is saved. Returns ['keys' => [...], 'notice' => text|null] or ['error' => message].
function invoice_save(PDO $db, string $entered_by, array $in): array
{
    $company_id = company_code($db);
    $entered_by = substr($entered_by, 0, 20);
    $v = document_validate($db, $in, $company_id);
    if (isset($v['error'])) {
        return $v;
    }
    $st = $db->prepare('SELECT T10ValidarCupo, T10FacturaNegativo, T10ValidarCosto, T10ValidarTiempo, T10ContabilidadBloque FROM T10EMPRESA WHERE T10CodEmpresa = ?');
    $st->execute([$company_id]);
    $cfg = $st->fetch() ?: [];

    $lock = number_lock($db, 'fac', $company_id, $v['doc_prefix']);
    if ($lock === null) {
        return ['error' => t('No se pudo asignar el número. Intente de nuevo.')];
    }
    try {
        // The checks run inside the lock and the transaction, so stock and credit are read when they are used
        $db->beginTransaction();
        $error = invoice_check($db, $v, $cfg);
        if ($error !== null) {
            $db->rollBack();
            return ['error' => $error];
        }
        [$num, $notice] = invoice_number($db, $company_id, $v['doc_prefix'], $v['d']);
        $total = legacy_num($v['total'], 0);
        $credit = $v['credit'];

        $header_row = [
            'T604CodEmpresa' => $company_id, 'T604Prefijo' => $v['doc_prefix'], 'T604NumFactura' => $num, 'T604Fecha' => $v['date'],
            'T604CodTercero' => $v['tax_id'], 'T604Total' => $total, 'T604TotalIVA' => legacy_num($v['total_vat'], 2),
            'T604TotalDescuento' => legacy_num($v['total_discount'], 2), 'T604CodFormaPago' => $v['payment'],
            'T604Detalle' => $v['detail'] === '' ? ' ' : $v['detail'], 'T604Cancelado' => 'N', 'T604FechaIni' => ' ',
            'T604HoraIni' => date('H:i'), 'T604FechaFin' => ' ', 'T604HoraFin' => ' ', 'T604TiempoFactura' => ' ', 'T604Piso' => ' ',
            'T604Area' => ' ', 'T604Habitacion' => ' ', 'T604FechaVence' => $v['due'],
            'T604Vendedor' => $v['salesperson'] === '' ? ' ' : $v['salesperson'], 'T604Digita' => $entered_by, 'T604PorcRetencion' => '0',
            'T604Retencion' => '0', 'T604Impresa' => 'N', 'T604PorcReteIVA' => '0', 'T604ReteIVA' => '0', 'T604PorcReteICA' => '0',
            'T604ReteICA' => '0', 'T604PorcAUIAdmon' => '0', 'T604AUIAdmon' => '0', 'T604PorcAUIImprevisto' => '0',
            'T604AUIImprevisto' => '0', 'T604PorcAUIUtilidad' => '0', 'T604AUIUtilidad' => '0', 'T604PorcAUIIVA' => '0',
            'T604AUIIVA' => '0', 'T604ValorPagado' => '0', 'T604DetalleLargo' => ' ', 'T604PorcOtrosDesc' => '0',
            'T604OtroDescuento' => '0', 'T604CodFormaPago2' => ' ', 'T604TotalFormaPago1' => $total, 'T604TotalFormaPago2' => '0',
            'T604OtroTercero' => ' ', 'T604NomOtroTercero' => ' ', 'T604ObservaOtroTercero' => ' ', 'T604NumAbono1' => '0',
            'T604NumAbono2' => '0', 'T604CUFE' => ' ', 'T604DesComercial' => '0', 'T604Placa' => ' ', 'T604Moneda' => 'COP',
            'T604CodFormaPagoFE' => $credit ? '1' : '0', 'T604MedioPagoFE' => '10',
        ];
        $db->prepare('INSERT INTO T604FACTURA (' . implode(', ', array_keys($header_row)) . ') VALUES (' . implode(', ', array_fill(0, count($header_row), '?')) . ')')
            ->execute(array_values($header_row));

        foreach ($v['items'] as $i => $it) {
            $line_row = [
                'T605CodEmpresa' => $company_id, 'T605Prefijo' => $v['doc_prefix'], 'T605NumFactura' => $num, 'T605Consecutivo' => (string) ($i + 1),
                'T605Cantidad' => legacy_num($it['qty'], 2), 'T605CodConcepto' => $it['item_code'], 'T605Valor' => legacy_num($it['base'], 4),
                'T605ValorIVA' => legacy_num($it['vat'], 2), 'T605SubCodConcepto' => ' ', 'T605Descuento' => legacy_num($it['disc'], 2),
                'T605CodCentro' => '00', 'T605Digita' => $entered_by, 'T605PorcIVA' => legacy_num($it['rate'], 2),
                'T605ValorCosto' => legacy_num($it['cost'], 4), 'T605ValorPagado' => '0', 'T605Observacion' => ' ',
                'T605Fecha' => ' ', 'T605Tercero' => ' ', 'T605FechaVence' => '01/01/1900', 'T605Lote' => ' ', 'T605PorcIVA2' => '0',
                'T605ValorIVA2' => '0', 'T605BaseImpAdic' => '0', 'T605ImpuestoAdic' => '-1', 'T605PorcImpAdic' => '0',
                'T605ValorImpAdic' => '0', 'T605TerceroAdic' => ' ',
            ];
            $db->prepare('INSERT INTO T605FACTURADETALLE (' . implode(', ', array_keys($line_row)) . ') VALUES (' . implode(', ', array_fill(0, count($line_row), '?')) . ')')
                ->execute(array_values($line_row));
        }

        stock_out($db, $company_id, $v['items']);
        // 'S' means the company posts in a batch process of the legacy program; anything else posts with each invoice
        if (($cfg['T10ContabilidadBloque'] ?? 'N') !== 'S') {
            post_sale($db, $v, $num);
        }
        audit($db, $entered_by, 'FACTURA ' . $v['doc_prefix'] . '-' . $num);
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
        error_log('sori: invoice not saved: ' . $ex->getMessage());
        return ['error' => t('No se pudo guardar la factura.')];
    } finally {
        number_unlock($db, $lock);
    }
    return ['keys' => ['k0' => $company_id, 'k1' => $v['doc_prefix'], 'k2' => $num], 'notice' => $notice];
}

// Gives back to the stock totals what an invoice took out. The cost is the one saved in the line.
function stock_restore(PDO $db, string $company_id, array $lines): void
{
    $sel = $db->prepare('SELECT T637CantSalida, T637TotalSalida FROM T637TOTALES WHERE T637CodEmpresa = ? AND T637CodConcepto = ? AND T637CodCentro = ? FOR UPDATE');
    $upd = $db->prepare('UPDATE T637TOTALES SET T637CantSalida = ?, T637TotalSalida = ? WHERE T637CodEmpresa = ? AND T637CodConcepto = ? AND T637CodCentro = ?');
    foreach ($lines as $l) {
        if (trim((string) $l['type']) !== '1') {
            continue;
        }
        $qty = (float) $l['qty'];
        $sel->execute([$company_id, $l['item_code'], $l['center']]);
        $r = $sel->fetch();
        if (!$r) {
            continue;
        }
        $upd->execute([
            legacy_num(max(0.0, (float) $r['T637CantSalida'] - $qty), 4),
            legacy_num(max(0.0, (float) $r['T637TotalSalida'] - $qty * (float) $l['cost']), 4),
            $company_id, $l['item_code'], $l['center'],
        ]);
    }
}

// Cancels a sales invoice, as the legacy program does: the invoice stays with its lines and its total,
// marked as cancelled; the stock is given back and the accounting document of the sale is deleted.
// Not allowed when the invoice was sent electronically, has payments, or its month or day is locked.
// Returns ['keys' => [...], 'notice' => text] or ['error' => message].
function invoice_cancel(PDO $db, string $entered_by, array $in): array
{
    $company_id = company_code($db);
    $entered_by = substr($entered_by, 0, 20);
    $doc_prefix = field($in['k1'] ?? '');
    $num = field($in['k2'] ?? '');
    try {
        $db->beginTransaction();
        $st = $db->prepare('SELECT T604Fecha, T604Cancelado, T604CUFE, T604ValorPagado, T604CodTercero FROM T604FACTURA WHERE T604CodEmpresa = ? AND T604Prefijo = ? AND T604NumFactura = ? FOR UPDATE');
        $st->execute([$company_id, $doc_prefix, $num]);
        $f = $st->fetch();
        if (!$f) {
            $db->rollBack();
            return ['error' => t('Factura no encontrada.')];
        }
        if ($f['T604Cancelado'] === 'S') {
            $db->rollBack();
            return ['error' => t('La factura ya está anulada.')];
        }
        if (trim((string) $f['T604CUFE']) !== '') {
            $db->rollBack();
            return ['error' => t('Una factura electrónica enviada no se anula: se corrige con una nota crédito.')];
        }
        $st = $db->prepare('SELECT COUNT(*) FROM T626ABONO WHERE T626CodEmpresa = ? AND T626Prefijo = ? AND T626NumFactura = ?');
        $st->execute([$company_id, $doc_prefix, $num]);
        if ((int) $st->fetchColumn() || (float) trim((string) $f['T604ValorPagado']) > 0) {
            $db->rollBack();
            return ['error' => t('La factura tiene abonos y no se puede anular.')];
        }
        $st = $db->prepare("SELECT COUNT(*) FROM T611DOCUMENTO WHERE T611CodEmpresa = ? AND T611TipoTransaccion = '6' AND T611Anular <> 'S' AND T611Prefijo = ? AND T611NumFactura = ?");
        $st->execute([$company_id, $doc_prefix, $num]);
        if ((int) $st->fetchColumn()) {
            $db->rollBack();
            return ['error' => t('La factura tiene devoluciones y no se puede anular.')];
        }
        $d = DateTimeImmutable::createFromFormat('!d/m/Y', trim((string) $f['T604Fecha']));
        if ($d === false) {
            $db->rollBack();
            return ['error' => t('La factura tiene una fecha no válida.')];
        }
        $lock_message = period_locked($db, $company_id, $d);
        if ($lock_message !== null) {
            $db->rollBack();
            return ['error' => $lock_message];
        }

        // Stock: the lines of the invoice, with the cost saved in each one
        $st = $db->prepare(
            'SELECT d.T605CodConcepto AS item_code, d.T605Cantidad AS qty, d.T605ValorCosto AS cost, TRIM(d.T605CodCentro) AS center,
                    (SELECT c.T603Tipo FROM T603CONCEPTO c WHERE c.T603CodEmpresa = d.T605CodEmpresa AND c.T603Codigo = d.T605CodConcepto LIMIT 1) AS type
             FROM T605FACTURADETALLE d WHERE d.T605CodEmpresa = ? AND d.T605Prefijo = ? AND d.T605NumFactura = ?'
        );
        $st->execute([$company_id, $doc_prefix, $num]);
        stock_restore($db, $company_id, $st->fetchAll());

        $year = $d->format('Y');
        $st = $db->prepare(
            "SELECT DISTINCT m.T106CodTipoDoc, m.T106SubNumeroDoc,
                    EXISTS (
                        SELECT 1 FROM T620CONCEPTOCONTAB c
                        WHERE c.T620CodEmpresa = m.T106CodEmpresa AND c.T620Agno = m.T106Agno
                          AND c.T620CodProceso = '0' AND c.T620TipoTransaccion = ?
                          AND c.T620CodTipoDocContab = m.T106CodTipoDoc
                    )
                    AND NOT EXISTS (
                        SELECT 1 FROM T620CONCEPTOCONTAB c
                        WHERE c.T620CodEmpresa = m.T106CodEmpresa AND c.T620Agno = m.T106Agno
                          AND c.T620CodTipoDocContab = m.T106CodTipoDoc AND c.T620CodProceso <> '0'
                    )
                    AND NOT EXISTS (
                        SELECT 1 FROM T604FACTURA f
                        JOIN T620CONCEPTOCONTAB c ON c.T620CodEmpresa = f.T604CodEmpresa
                          AND c.T620Agno = m.T106Agno AND c.T620CodProceso = '0'
                          AND c.T620TipoTransaccion = f.T604Prefijo AND c.T620CodTipoDocContab = m.T106CodTipoDoc
                        WHERE f.T604CodEmpresa = m.T106CodEmpresa AND f.T604NumFactura = m.T106NumeroDoc
                          AND f.T604Fecha = m.T106Fecha AND f.T604CodTercero = m.T106Nit AND f.T604Prefijo <> ?
                    ) AS configured
             FROM T106MOVIMIENTO m
             JOIN T104DOCUMENTO h ON h.T104CodEmpresa = m.T106CodEmpresa AND h.T104Agno = m.T106Agno
                  AND h.T104CodTipoDoc = m.T106CodTipoDoc AND h.T104NumeroDoc = m.T106NumeroDoc
             WHERE m.T106CodEmpresa = ? AND m.T106Agno = ? AND m.T106NumeroDoc = ? AND m.T106CodSubTipoDoc = ?
                  AND m.T106Fecha = ? AND (m.T106SubNumeroDoc LIKE 'SORI:SALE:%' OR m.T106Nit = ?)
                  AND h.T104Aplicacion = 'FACTURACIO'"
        );
        $st->execute([$doc_prefix, $doc_prefix, $company_id, $year, $num, $num, $d->format('d/m/Y'), $f['T604CodTercero']]);
        $posted = [];
        $legacy = [];
        $has_legacy = false;
        $origin = 'SORI:SALE:' . $doc_prefix;
        foreach ($st->fetchAll() as $entry) {
            $marker = trim((string) $entry['T106SubNumeroDoc']);
            $type = $entry['T106CodTipoDoc'];
            if (str_starts_with($marker, 'SORI:SALE:')) {
                if ($marker === $origin) {
                    $posted[$type] = $type;
                }
                continue;
            }
            $has_legacy = true;
            if ((int) $entry['configured']) {
                $legacy[$type] = $type;
            }
        }
        $matches = $posted ?: $legacy;
        if (count($matches) > 1 || (!$matches && $has_legacy)) {
            throw new DocumentError(t('No se pudo identificar el asiento de la factura. La factura sigue activa.'));
        }
        if ($matches) {
            $key = [$company_id, $year, reset($matches), $num];
            $db->prepare('DELETE FROM T106MOVIMIENTO WHERE T106CodEmpresa = ? AND T106Agno = ? AND T106CodTipoDoc = ? AND T106NumeroDoc = ?')->execute($key);
            $db->prepare('DELETE FROM T104DOCUMENTO WHERE T104CodEmpresa = ? AND T104Agno = ? AND T104CodTipoDoc = ? AND T104NumeroDoc = ?')->execute($key);
        }

        $db->prepare("UPDATE T604FACTURA SET T604Cancelado = 'S' WHERE T604CodEmpresa = ? AND T604Prefijo = ? AND T604NumFactura = ?")
            ->execute([$company_id, $doc_prefix, $num]);
        audit($db, $entered_by, 'ANULACION FACTURA ' . $doc_prefix . '-' . $num, '3');
        $db->commit();
    } catch (DocumentError $ex) {
        $db->rollBack();
        return ['error' => $ex->getMessage()];
    } catch (Throwable $ex) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        error_log('sori: invoice not cancelled: ' . $ex->getMessage());
        return ['error' => t('No se pudo anular la factura.')];
    }
    return ['keys' => ['k0' => $company_id, 'k1' => $doc_prefix, 'k2' => $num], 'notice' => t('La factura quedó anulada.')];
}
