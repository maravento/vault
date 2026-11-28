<?php
// SORI writes: a payment made to a supplier on a credit purchase. It follows the legacy program, checked on real data:
// the payment is a row of T628 that points to the purchase by its type and number, it is numbered inside its payment prefix
// (the type of the purchase), it keeps the debt, what was paid and the balance before it, and, when the company posts online,
// the accounting document debits the supplier account and credits the bank account.
// FILE: app/supplier_payment.php
declare(strict_types=1);

// What is owed on a purchase: total less withholdings, less payments, less the returns to the supplier (also less their withholdings)
function purchase_balance(PDO $db, string $company_id, array $purchase): array
{
    $debt = (float) $purchase['total'] - (float) trim((string) $purchase['withholding_income']) - (float) trim((string) $purchase['withholding_vat']) - (float) trim((string) $purchase['withholding_ica']);
    $st = $db->prepare(
        "SELECT COALESCE(SUM(" . sql_num('T628Valor') . ' + ' . sql_num('T628TotalDescuentos') . "), 0) FROM T628ABONOCOMPRA
         WHERE T628CodEmpresa = ? AND T628TipoTransaccion = ? AND T628NumEntrada = ? AND T628AgnoFactura = ? AND T628TipoAbono = '0'"
    );
    $st->execute([$company_id, $purchase['type'], $purchase['number'], $purchase['doc_year']]);
    $paid = (float) $st->fetchColumn();
    $st = $db->prepare(
        "SELECT COALESCE(SUM(" . sql_num('T611ValorTtFactura') . ' - ' . sql_num('T611ValorReteRenta') . ' - ' . sql_num('T611ValorReteIVA') . ' - ' . sql_num('T611ValorReteICA') . "), 0)
         FROM T611DOCUMENTO WHERE T611CodEmpresa = ? AND T611TipoTransaccion = '3' AND T611Anular <> 'S' AND T611Prefijo = ? AND T611NumFactura = ?"
    );
    $st->execute([$company_id, $purchase['type'], $purchase['number']]);
    $returned = (float) $st->fetchColumn();
    return ['debt' => $debt, 'paid' => $paid, 'returned' => $returned, 'balance' => $debt - $paid - $returned];
}

// The accounting document of a payment: debit to the supplier account, credit to the bank account of the setup.
// The row is chosen by year, accounting group of the first item and the payment prefix, which is the purchase type (process 3).
// Returns a notice when there is no setup, so the payment is saved without document, as the legacy program does.
function post_supplier_payment(PDO $db, string $company_id, array $purchase, string $num, string $account, DateTimeImmutable $d, float $value): ?string
{
    $year = $d->format('Y');
    $st = $db->prepare(
        'SELECT g.T623CodGrupo FROM T612MOVIMIENTO l JOIN T623CONCEPTOxGRUPO g ON g.T623CodEmpresa = l.T612CodEmpresa AND g.T623CodConcepto = l.T612CodArticulo
         WHERE l.T612CodEmpresa = ? AND l.T612Agno = ? AND l.T612TipoTransaccion = ? AND l.T612NumeroDoc = ? ORDER BY CAST(l.T612Consecutivo AS UNSIGNED) LIMIT 1'
    );
    $st->execute([$company_id, $purchase['doc_year'], $purchase['type'], $purchase['number']]);
    $group = $st->fetchColumn();
    $st = $db->prepare("SELECT T620CodTipoDocContab, T620Caja, T620Banco, T620Cuenta1 FROM T620CONCEPTOCONTAB WHERE T620CodEmpresa = ? AND T620Agno = ? AND T620CodGrupo = ? AND T620CodProceso = '3' AND T620TipoTransaccion = ? LIMIT 1");
    $st->execute([$company_id, $year, $group === false ? '1' : $group, $purchase['type']]);
    $c = $st->fetch();
    if (!$c || trim((string) $c['T620CodTipoDocContab']) === '' || trim((string) $c['T620Cuenta1']) === '') {
        return t('El pago se guardó sin asiento: no hay configuración contable para los pagos a proveedores.');
    }
    $type = trim((string) $c['T620CodTipoDocContab']);
    // Paid from the cash account: cash. Any other account: the bank account of the setup.
    $credit_account = $account === trim((string) $c['T620Caja']) ? trim((string) $c['T620Caja']) : trim((string) $c['T620Banco']);
    if ($credit_account === '') {
        throw new DocumentError(t('El pago no tiene una cuenta contable de caja o banco configurada.'));
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
    $ins->execute([$company_id, $year, $type, $num, trim((string) $c['T620Cuenta1']), '0', $date, '00', $purchase['supplier'], '0', ' ', $v, '0', $purchase['number'], ' ', '01/01/1900', '', '']);
    $ins->execute([$company_id, $year, $type, $num, $credit_account, '1', $date, '00', $purchase['supplier'], ' ', ' ', '0', $v, ' ', ' ', '01/01/1900', '', '']);
    return null;
}

// Saves a payment on a credit purchase. One transaction: if anything fails, nothing is saved.
// Returns ['keys' => [...], 'notice' => text|null] or ['error' => message].
function supplier_payment_save(PDO $db, string $entered_by, array $in): array
{
    $company_id = company_code($db);
    $entered_by = substr($entered_by, 0, 20);
    $purchase_type = field($in['type'] ?? '');
    $purchase_number = field($in['number'] ?? '');
    $purchase_year = field($in['year'] ?? '');
    if (!preg_match('/^[0-9]{4}$/D', $purchase_year)) {
        return ['error' => t('Compra no encontrada.')];
    }
    $account = field($in['account'] ?? '');
    $doc = field($in['document'] ?? '');
    $remark_text = field($in['remark'] ?? '');

    $st = $db->prepare("SELECT COUNT(*) FROM T627BANCO WHERE T627Codigo = ? AND T627Activo = 'S'");
    $st->execute([$account]);
    if ($account === '' || !(int) $st->fetchColumn()) {
        return ['error' => t('Cuenta de pago no válida.')];
    }
    if (text_length($remark_text) > 255) {
        return ['error' => t('La observación es muy larga.')];
    }
    if (text_length($doc) > 5) {
        return ['error' => t('El número de documento es muy largo.')];
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

    $lock = number_lock($db, 'pagoc', $company_id, $purchase_type);
    if ($lock === null) {
        return ['error' => t('No se pudo asignar el número. Intente de nuevo.')];
    }
    try {
        $db->beginTransaction();
        $purchase = purchase_document($db, $company_id, $purchase_type, $purchase_number, $purchase_year);
        if ($purchase === null) {
            $db->rollBack();
            return ['error' => t('Compra no encontrada.')];
        }
        // The purchase is locked, so two payments cannot both fit in the same balance
        $st = $db->prepare('SELECT 1 FROM T611DOCUMENTO WHERE T611CodEmpresa = ? AND T611Agno = ? AND T611TipoTransaccion = ? AND T611NumeroDoc = ? FOR UPDATE');
        $st->execute([$company_id, $purchase['doc_year'], $purchase['type'], $purchase['number']]);
        if ($purchase['cancelled'] === 'S') {
            $db->rollBack();
            return ['error' => t('La compra está anulada.')];
        }
        if ($purchase['credit'] !== 'S') {
            $db->rollBack();
            return ['error' => t('La compra no es a crédito: no recibe pagos.')];
        }
        $doc_date = DateTimeImmutable::createFromFormat('!d/m/Y', trim((string) $purchase['date']));
        if ($doc_date !== false && $d < $doc_date) {
            $db->rollBack();
            return ['error' => t('La fecha del pago es anterior a la de la compra.')];
        }
        $s = purchase_balance($db, $company_id, $purchase);
        if (round($value, 2) > round($s['balance'], 2)) {
            $db->rollBack();
            return ['error' => t('El pago supera el saldo de la compra.')];
        }
        $lock_message = period_locked($db, $company_id, $d);
        if ($lock_message !== null) {
            $db->rollBack();
            return ['error' => $lock_message];
        }

        $st = $db->prepare('SELECT COALESCE(MAX(CAST(T628NumAbono AS UNSIGNED)), 0) + 1 FROM T628ABONOCOMPRA WHERE T628CodEmpresa = ? AND T628PrefijoAbono = ?');
        $st->execute([$company_id, $purchase['type']]);
        $num = (string) $st->fetchColumn();

        $row = [
            'T628CodEmpresa' => $company_id, 'T628NumAbono' => $num, 'T628NumEntrada' => $purchase['number'], 'T628TipoTransaccion' => $purchase['type'],
            'T628Fecha' => $date, 'T628Valor' => legacy_num($value, 2), 'T628CodBanco' => $account, 'T628NumDoc' => $doc === '' ? ' ' : $doc,
            'T628CodTercero' => $purchase['supplier'], 'T628Observacion' => $remark_text === '' ? ' ' : $remark_text, 'T628TotalDescuentos' => '0',
            'T628AgnoFactura' => $purchase['doc_year'], 'T628ValorDeudaAnt' => legacy_num($s['debt'], 2), 'T628ValorPagadoAnt' => legacy_num($s['paid'], 2),
            'T628ValorSaloAnt' => legacy_num($s['debt'] - $s['paid'], 2), 'T628Digita' => $entered_by, 'T628FechaVence' => '0', 'T628Vendedor' => $entered_by,
            'T628FormaPago' => substr(trim((string) $purchase['payment_name']), 0, 30), 'T628NumFactura' => $purchase['invoice'], 'T628Retencion' => '0',
            'T628TipoAbono' => '0', 'T628RetencionICA' => '0', 'T628RetencionIVA' => '0', 'T628PrefijoAbono' => $purchase['type'],
            'T628PorcRetencion' => ' ', 'T628Referencia' => ' ',
        ];
        $db->prepare('INSERT INTO T628ABONOCOMPRA (' . implode(', ', array_keys($row)) . ') VALUES (' . implode(', ', array_fill(0, count($row), '?')) . ')')
            ->execute(array_values($row));

        $notice = $online ? post_supplier_payment($db, $company_id, $purchase, $num, $account, $d, $value) : null;
        audit($db, $entered_by, 'PAGO ' . $purchase['type'] . '-' . $num . ' COMPRA ' . $purchase['type'] . '-' . $purchase['number']);
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
        error_log('sori: supplier payment not saved: ' . $ex->getMessage());
        return ['error' => t('No se pudo guardar el pago.')];
    } finally {
        number_unlock($db, $lock);
    }
    return ['keys' => ['k0' => $company_id, 'k1' => $num, 'k2' => $purchase['number'], 'k3' => $purchase['type'], 'k4' => $purchase['type']], 'notice' => $notice];
}
