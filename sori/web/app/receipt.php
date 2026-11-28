<?php
// SORI writes: a payment received on a credit invoice. It follows the legacy program, checked on real data:
// the invoice paid amount grows by the payment, the payment number is the next one of its payment prefix and,
// when the company posts online and the prefix has a setup, the accounting document has the number of the payment.
// FILE: app/receipt.php
declare(strict_types=1);

// The invoice a payment would go to, with what is paid and what is left. Null when it does not exist.
function invoice_for_receipt(PDO $db, string $company_id, string $doc_prefix, string $num): ?array
{
    $st = $db->prepare(
        'SELECT f.T604Prefijo AS prefix, f.T604NumFactura AS number, f.T604Fecha AS date, f.T604FechaVence AS due,
                f.T604Total AS total, f.T604ValorPagado AS paid, f.T604Cancelado AS cancelled_flag, f.T604CodTercero AS party,
                p.T616Cartera AS credit, p.T616Nombre AS payment, ' . party_name('t') . ' AS name
         FROM T604FACTURA f
         LEFT JOIN T616TIPOFORMAPAGO p ON p.T616Codigo = f.T604CodFormaPago
         LEFT JOIN T12TERCERO t ON t.T12CodEmpresa = f.T604CodEmpresa AND t.T12Nit = f.T604CodTercero
         WHERE f.T604CodEmpresa = ? AND f.T604Prefijo = ? AND f.T604NumFactura = ?'
    );
    $st->execute([$company_id, $doc_prefix, $num]);
    $f = $st->fetch();
    if (!$f) {
        return null;
    }
    $st = $db->prepare("SELECT COALESCE(SUM(" . sql_num('T611ValorTtFactura') . "), 0) FROM T611DOCUMENTO
        WHERE T611CodEmpresa = ? AND T611TipoTransaccion = '6' AND T611Anular <> 'S' AND T611Prefijo = ? AND T611NumFactura = ?");
    $st->execute([$company_id, $doc_prefix, $num]);
    $f['returned'] = (float) $st->fetchColumn();
    $f['balance'] = (float) $f['total'] - (float) trim((string) $f['paid']) - $f['returned'];
    return $f;
}

// Choices of the payment form
function receipt_options(PDO $db): array
{
    return [
        'accounts' => $db->query("SELECT T627Codigo AS code, T627Nombre AS name FROM T627BANCO WHERE T627Activo = 'S' ORDER BY T627Nombre")->fetchAll(),
        'prefixes' => $db->query('SELECT T629Codigo AS code, T629Nombre AS name FROM T629PREFIJO ORDER BY CAST(T629Codigo AS UNSIGNED)')->fetchAll(),
        'last_prefix' => (string) $db->query('SELECT T626PrefijoAbono FROM T626ABONO ORDER BY CAST(T626NumAbono AS UNSIGNED) DESC LIMIT 1')->fetchColumn(),
    ];
}

// The accounting document of a payment: credit to the receivable account, debit to cash or bank.
// The row of the setup is chosen by year, accounting group of the invoice and payment prefix (process 4).
// Returns a notice when the prefix has no setup, so the payment is saved without document, as the legacy program does.
function post_receipt(PDO $db, string $company_id, string $tax_id, array $f, string $num, string $receipt_prefix, string $account, DateTimeImmutable $d, float $value): ?string
{
    $year = $d->format('Y');
    $st = $db->prepare(
        'SELECT g.T623CodGrupo FROM T605FACTURADETALLE l JOIN T623CONCEPTOxGRUPO g ON g.T623CodEmpresa = l.T605CodEmpresa AND g.T623CodConcepto = l.T605CodConcepto
         WHERE l.T605CodEmpresa = ? AND l.T605Prefijo = ? AND l.T605NumFactura = ? ORDER BY l.T605Consecutivo LIMIT 1'
    );
    $st->execute([$company_id, $f['prefix'], $f['number']]);
    $group = $st->fetchColumn();
    $st = $db->prepare("SELECT T620CodTipoDocContab, T620Caja, T620Banco, T620Cuenta1 FROM T620CONCEPTOCONTAB WHERE T620CodEmpresa = ? AND T620Agno = ? AND T620CodGrupo = ? AND T620CodProceso = '4' AND T620TipoTransaccion = ? LIMIT 1");
    $st->execute([$company_id, $year, $group === false ? '1' : $group, $receipt_prefix]);
    $c = $st->fetch();
    if (!$c || trim((string) $c['T620CodTipoDocContab']) === '' || trim((string) $c['T620Cuenta1']) === '') {
        return t('El abono se guardó sin asiento: el prefijo de abono no tiene configuración contable.');
    }
    $type = trim((string) $c['T620CodTipoDocContab']);
    // Paid in the cash account: cash. Any other account: the bank account of the setup.
    $debit_account = $account === trim((string) $c['T620Caja']) ? trim((string) $c['T620Caja']) : trim((string) $c['T620Banco']);
    if ($debit_account === '') {
        throw new DocumentError(t('El abono no tiene una cuenta contable de caja o banco configurada.'));
    }
    $st = $db->prepare('SELECT COUNT(*) FROM T104DOCUMENTO WHERE T104CodEmpresa = ? AND T104Agno = ? AND T104CodTipoDoc = ? AND T104NumeroDoc = ?');
    $st->execute([$company_id, $year, $type, $num]);
    if ((int) $st->fetchColumn()) {
        throw new DocumentError(str_replace('{n}', $num, t('Ya existe el documento contable {n}.')));
    }
    $date = $d->format('d/m/Y');
    $db->prepare(
        'INSERT INTO T104DOCUMENTO (T104CodEmpresa, T104Agno, T104CodTipoDoc, T104NumeroDoc, T104Fecha, T104Concepto, T104Anulado,
            T104Aplicacion, T104ValorTotal, T104NombreCheque, NumeroAnterior, NuevoNumero, T104Bloqueado)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    )->execute([$company_id, $year, $type, $num, $date, ' ', 'N', 'FACTURACIO', ' ', ' ', '', '', 'N']);
    $ins = $db->prepare(
        'INSERT INTO T106MOVIMIENTO (T106CodEmpresa, T106Agno, T106CodTipoDoc, T106NumeroDoc, T106CodCta, T106ConsecCta, T106Fecha,
            T106CodCentro, T106Nit, T106Referencia, T106Detalle, T106ValorDebito, T106ValorCredito, T106CodSubTipoDoc,
            T106SubNumeroDoc, T106FechaConciliado, Anterior, Nuevo)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    $v = legacy_num($value, 0);
    $ins->execute([$company_id, $year, $type, $num, trim((string) $c['T620Cuenta1']), '0', $date, '00', $tax_id, '0', ' ', '0', $v, $f['number'], ' ', '01/01/1900', '', '']);
    $ins->execute([$company_id, $year, $type, $num, $debit_account, '1', $date, '00', $tax_id, ' ', ' ', $v, '0', ' ', ' ', '01/01/1900', '', '']);
    return null;
}

// Saves a payment on a credit invoice. One transaction: if anything fails, nothing is saved.
// Returns ['keys' => [...], 'notice' => text|null] or ['error' => message].
function receipt_save(PDO $db, string $entered_by, array $in): array
{
    $company_id = company_code($db);
    $entered_by = substr($entered_by, 0, 20);
    $doc_prefix = field($in['prefix'] ?? '');
    $invoice_num = field($in['number'] ?? '');
    $receipt_prefix = field($in['receipt_prefix'] ?? '');
    $account = field($in['account'] ?? '');
    $remark_text = field($in['remark'] ?? '');

    $st = $db->prepare('SELECT COUNT(*) FROM T629PREFIJO WHERE T629Codigo = ?');
    $st->execute([$receipt_prefix]);
    if ($receipt_prefix === '' || !(int) $st->fetchColumn()) {
        return ['error' => t('Prefijo no válido.')];
    }
    $st = $db->prepare("SELECT COUNT(*) FROM T627BANCO WHERE T627Codigo = ? AND T627Activo = 'S'");
    $st->execute([$account]);
    if ($account === '' || !(int) $st->fetchColumn()) {
        return ['error' => t('Cuenta de pago no válida.')];
    }
    if (text_length($remark_text) > 255) {
        return ['error' => t('La observación es muy larga.')];
    }
    $date = field($in['date'] ?? '');
    $d = DateTimeImmutable::createFromFormat('!d/m/Y', $date);
    if ($d === false || $d->format('d/m/Y') !== $date) {
        return ['error' => t('Fecha no válida.')];
    }
    if ($d > new DateTimeImmutable('today')) {
        return ['error' => t('La fecha no puede ser futura.')];
    }
    $value = positive_decimal(field($in['value'] ?? ''));
    if ($value === null || ($value = round($value, 2)) <= 0) {
        return ['error' => t('Valor no válido.')];
    }

    $st = $db->prepare('SELECT T10ContabilidadAbono FROM T10EMPRESA WHERE T10CodEmpresa = ?');
    $st->execute([$company_id]);
    $online = ($st->fetchColumn() ?: 'N') !== 'S';

    $lock = number_lock($db, 'abo', $company_id, $receipt_prefix);
    if ($lock === null) {
        return ['error' => t('No se pudo asignar el número. Intente de nuevo.')];
    }
    try {
        $db->beginTransaction();
        // The invoice is read with a lock, so two payments cannot both fit in the same balance
        $st = $db->prepare('SELECT T604NumFactura FROM T604FACTURA WHERE T604CodEmpresa = ? AND T604Prefijo = ? AND T604NumFactura = ? FOR UPDATE');
        $st->execute([$company_id, $doc_prefix, $invoice_num]);
        $f = $st->fetchColumn() === false ? null : invoice_for_receipt($db, $company_id, $doc_prefix, $invoice_num);
        if ($f === null) {
            $db->rollBack();
            return ['error' => t('Factura no encontrada.')];
        }
        if ($f['cancelled_flag'] === 'S') {
            $db->rollBack();
            return ['error' => t('La factura está anulada.')];
        }
        if ($f['credit'] !== 'S') {
            $db->rollBack();
            return ['error' => t('La factura no es de crédito: no recibe abonos.')];
        }
        $doc_date = DateTimeImmutable::createFromFormat('!d/m/Y', trim((string) $f['date']));
        if ($doc_date !== false && $d < $doc_date) {
            $db->rollBack();
            return ['error' => t('La fecha del abono es anterior a la de la factura.')];
        }
        if (round($value, 2) > round($f['balance'], 2)) {
            $db->rollBack();
            return ['error' => t('El abono supera el saldo de la factura.')];
        }
        $lock_message = period_locked($db, $company_id, $d);
        if ($lock_message !== null) {
            $db->rollBack();
            return ['error' => $lock_message];
        }

        $st = $db->prepare('SELECT COALESCE(MAX(CAST(T626NumAbono AS UNSIGNED)), 0) + 1 FROM T626ABONO WHERE T626CodEmpresa = ? AND T626PrefijoAbono = ?');
        $st->execute([$company_id, $receipt_prefix]);
        $num = (string) $st->fetchColumn();

        // Days late when positive, days early when negative: payment date minus the due date of the invoice
        $due_date = DateTimeImmutable::createFromFormat('!d/m/Y', trim((string) $f['due']));
        $days = $due_date === false ? 0 : (int) round(($d->getTimestamp() - $due_date->getTimestamp()) / 86400);
        $row = [
            'T626CodEmpresa' => $company_id, 'T626NumAbono' => $num, 'T626Prefijo' => $doc_prefix, 'T626NumFactura' => $invoice_num,
            'T626Fecha' => $date, 'T626Valor' => legacy_num($value, 2), 'T626CodBanco' => $account, 'T626NumDoc' => ' ',
            'T626CodTercero' => $f['party'], 'T626Observacion' => $remark_text === '' ? ' ' : $remark_text, 'T626TotalDescuentos' => '0',
            'T626AgnoFactura' => $doc_date === false ? ' ' : $doc_date->format('Y'), 'T626ValorDeudaAnt' => legacy_num((float) $f['total'], 2),
            'T626ValorPagadoAnt' => legacy_num((float) trim((string) $f['paid']), 2), 'T626ValorSaloAnt' => legacy_num($f['balance'], 2),
            'T626Digita' => $entered_by, 'T626FechaVence' => (string) $days,
            'T626Vendedor' => ' ', 'T626FormaPago' => substr(trim((string) $f['payment']), 0, 30), 'T626Retencion' => '0', 'T626Multa' => '0',
            'T626TipoAbono' => '0', 'T626Folio' => ' ', 'T626RetencionICA' => '0', 'T626RetencionIVA' => '0', 'T626PrefijoAbono' => $receipt_prefix,
            'T626Cobrador' => ' ', 'T626Hora' => date('H:i'), 'T626RetencionOtro' => '0', 'T626PorcRetencion' => '0', 'T626Referencia' => ' ',
        ];
        $db->prepare('INSERT INTO T626ABONO (' . implode(', ', array_keys($row)) . ') VALUES (' . implode(', ', array_fill(0, count($row), '?')) . ')')
            ->execute(array_values($row));
        $db->prepare('UPDATE T604FACTURA SET T604ValorPagado = ? WHERE T604CodEmpresa = ? AND T604Prefijo = ? AND T604NumFactura = ?')
            ->execute([legacy_num((float) trim((string) $f['paid']) + $value, 2), $company_id, $doc_prefix, $invoice_num]);

        $notice = $online ? post_receipt($db, $company_id, $f['party'], $f, $num, $receipt_prefix, $account, $d, $value) : null;
        audit($db, $entered_by, 'ABONO ' . $receipt_prefix . '-' . $num . ' FACTURA ' . $doc_prefix . '-' . $invoice_num);
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
        error_log('sori: payment not saved: ' . $ex->getMessage());
        return ['error' => t('No se pudo guardar el abono.')];
    } finally {
        number_unlock($db, $lock);
    }
    return ['keys' => ['k0' => $company_id, 'k1' => $num, 'k2' => $doc_prefix, 'k3' => $invoice_num, 'k4' => $receipt_prefix], 'notice' => $notice];
}
