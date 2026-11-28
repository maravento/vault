<?php
// SORI writes: who may write, lookups for the forms, the check shared by quotes and invoices, and the quote save.
// The legacy tables are written as they are, with their text formats:
// numbers with a dot and no thousands separator, dates dd/mm/yyyy, blank = one space.
// FILE: app/write.php
declare(strict_types=1);

// Only a client user with the editor role writes. The platform user has no client data.
function can_write(): bool
{
    $u = user();
    return $u !== null && $u['slug'] !== null && $u['role'] === 'editor';
}

// Length in characters of UTF-8 text, without the mbstring extension. Invalid UTF-8 counts as too long.
function text_length(string $s): int
{
    $n = preg_match_all('/./su', $s);
    return $n === false ? PHP_INT_MAX : $n;
}

// A form value as trimmed text. Anything that is not a plain value counts as empty.
function field(mixed $v): string
{
    return is_scalar($v) ? trim((string) $v) : '';
}

// Number as the legacy database stores it: 4950000, 48275.86, 301724.1379
function legacy_num(float $n, int $decimals): string
{
    $s = number_format($n, $decimals, '.', '');
    if (str_contains($s, '.')) {
        $s = rtrim(rtrim($s, '0'), '.');
    }
    return $s === '-0' || $s === '' ? '0' : $s;
}

// A legacy text column that may hold a number, a blank or a space, as a number
function sql_num(string $col): string
{
    return "CAST(COALESCE(NULLIF(TRIM($col), ''), '0') AS DECIMAL(20,4))";
}

// Company code of the client database. A client has one company.
function company_code(PDO $db): string
{
    $v = $db->query('SELECT T10CodEmpresa FROM T10EMPRESA ORDER BY T10CodEmpresa LIMIT 1')->fetchColumn();
    return $v === false ? '1' : (string) $v;
}

// VAT percentage of a price list row: only a taxed item (type 0) charges it
function vat_rate(?string $type, ?string $value): float
{
    return trim((string) $type) === '0' ? max(0.0, (float) $value) : 0.0;
}

// Items found by code or name, with the price of list 1 (VAT included)
function search_items(PDO $db, string $q): array
{
    $like = '%' . addcslashes($q, '%_\\') . '%';
    $st = $db->prepare(
        "SELECT c.T603Codigo AS code, c.T603Nombre AS name, c.T603ActivaValor AS free_price,
                c.T603ActivaDescuento AS free_discount, l.T630Valor AS value, l.T630ValorIVA AS vat, l.T630CodTipoIVA AS vat_type
         FROM T603CONCEPTO c
         LEFT JOIN T630LISTAVALORES l ON l.T630CodEmpresa = c.T603CodEmpresa AND l.T630CodTemporada = c.T603CodTemporada
              AND l.T630CodConcepto = c.T603Codigo AND l.T630Codigo = '1'
         WHERE c.T603CodEmpresa = ? AND c.T603Imprimir <> 'N' AND (c.T603Codigo LIKE ? OR c.T603Nombre LIKE ?)
         ORDER BY (c.T603Codigo = ?) DESC, c.T603Nombre LIMIT 20"
    );
    $st->execute([company_code($db), $like, $like, $q]);
    $out = [];
    foreach ($st->fetchAll() as $r) {
        $out[] = [
            'code' => trim($r['code']),
            'name' => trim($r['name']),
            'price' => (float) $r['value'],
            'vat' => vat_rate($r['vat_type'], $r['vat']),
            'free_price' => $r['free_price'] === 'S',
            'free_discount' => $r['free_discount'] === 'S',
        ];
    }
    return $out;
}

// Third parties found by document or name
function search_parties(PDO $db, string $q): array
{
    $like = '%' . addcslashes($q, '%_\\') . '%';
    $st = $db->prepare(
        'SELECT t.T12Nit AS tax_id, ' . party_name('t') . ' AS name
         FROM T12TERCERO t
         WHERE t.T12CodEmpresa = ? AND (t.T12Nit LIKE ? OR t.T12RazonSocial LIKE ? OR t.T12Nombre LIKE ? OR t.T12Apellido LIKE ?)
         ORDER BY name LIMIT 20'
    );
    $st->execute([company_code($db), $like, $like, $like, $like]);
    return array_map(static fn($r) => ['tax_id' => trim($r['tax_id']), 'name' => $r['name']], $st->fetchAll());
}

// Choices of the quote and invoice form. $table_name and $col are fixed names from the code, never user input.
function document_options(PDO $db, string $table, string $col): array
{
    return [
        'prefixes' => $db->query('SELECT T629Codigo AS code, T629Nombre AS name FROM T629PREFIJO ORDER BY CAST(T629Codigo AS UNSIGNED)')->fetchAll(),
        'payments' => $db->query('SELECT T616Codigo AS code, T616Nombre AS name FROM T616TIPOFORMAPAGO ORDER BY CAST(T616Codigo AS UNSIGNED)')->fetchAll(),
        'salespeople' => $db->query("SELECT T625Codigo AS code, T625Nombre AS name FROM T625VENDEDOR WHERE T625Activo = 'S' ORDER BY T625Nombre")->fetchAll(),
        'last_prefix' => (string) $db->query("SELECT $col FROM $table ORDER BY CAST(" . str_replace('Prefijo', 'NumFactura', $col) . ' AS UNSIGNED) DESC LIMIT 1')->fetchColumn(),
    ];
}

// Positive decimal typed in a form, or null
function positive_decimal(mixed $v, bool $allow_zero = false): ?float
{
    $v = trim((string) $v);
    if (!preg_match('/^\d{1,9}(\.\d{1,4})?$/', $v)) {
        return null;
    }
    $n = (float) $v;
    return ($n > 0 || ($allow_zero && $n == 0)) ? $n : null;
}

// Checks the form of a quote or an invoice and computes its items and totals.
// Returns ['error' => message] or the data to save. Nothing is taken from the browser but the choices:
// totals, taxes and prices come from the database and the items.
function document_validate(PDO $db, array $in, string $company_id): array
{
    $doc_prefix = field($in['prefix'] ?? '');
    $st = $db->prepare('SELECT COUNT(*) FROM T629PREFIJO WHERE T629Codigo = ?');
    $st->execute([$doc_prefix]);
    if ($doc_prefix === '' || !(int) $st->fetchColumn()) {
        return ['error' => t('Prefijo no válido.')];
    }

    $tax_id = field($in['party'] ?? '');
    $st = $db->prepare('SELECT COUNT(*) FROM T12TERCERO WHERE T12CodEmpresa = ? AND T12Nit = ?');
    $st->execute([$company_id, $tax_id]);
    if ($tax_id === '' || !(int) $st->fetchColumn()) {
        return ['error' => t('Tercero no encontrado.')];
    }

    $payment = field($in['payment'] ?? '');
    $st = $db->prepare('SELECT T616DiasInc, T616Cartera FROM T616TIPOFORMAPAGO WHERE T616Codigo = ?');
    $st->execute([$payment]);
    $f = $st->fetch();
    if ($payment === '' || !$f) {
        return ['error' => t('Forma de pago no válida.')];
    }

    $salesperson = field($in['salesperson'] ?? '');
    if ($salesperson !== '') {
        $st = $db->prepare("SELECT COUNT(*) FROM T625VENDEDOR WHERE T625Codigo = ? AND T625Activo = 'S'");
        $st->execute([$salesperson]);
        if (!(int) $st->fetchColumn()) {
            return ['error' => t('Vendedor no válido.')];
        }
    }

    $date = field($in['date'] ?? '');
    $d = DateTimeImmutable::createFromFormat('!d/m/Y', $date);
    if ($d === false || $d->format('d/m/Y') !== $date) {
        return ['error' => t('Fecha no válida.')];
    }
    if ($d > new DateTimeImmutable('today')) {
        return ['error' => t('La fecha no puede ser futura.')];
    }
    $due = $d->modify('+' . (int) $f['T616DiasInc'] . ' days')->format('d/m/Y');

    $detail = field($in['detail'] ?? '');
    if (text_length($detail) > 100) {
        return ['error' => t('El detalle es muy largo.')];
    }

    // The item fields are lists. A single value in their place is not accepted.
    foreach (['item', 'quantity', 'value', 'discount'] as $price_list) {
        if (!isset($in[$price_list]) || !is_array($in[$price_list])) {
            return ['error' => t('Agregue al menos un ítem.')];
        }
        $in[$price_list] = array_values($in[$price_list]);
    }
    $codes = $in['item'];
    if (!$codes) {
        return ['error' => t('Agregue al menos un ítem.')];
    }
    if (count($codes) > 200) {
        return ['error' => t('Demasiados ítems.')];
    }
    $line = $db->prepare(
        "SELECT c.T603Codigo AS code, c.T603ActivaValor AS free_price, c.T603ActivaDescuento AS free_discount,
                c.T603Tipo AS type, c.T603CostoPromedio AS cost,
                l.T630Valor AS value, l.T630ValorIVA AS vat, l.T630CodTipoIVA AS vat_type
         FROM T603CONCEPTO c
         LEFT JOIN T630LISTAVALORES l ON l.T630CodEmpresa = c.T603CodEmpresa AND l.T630CodTemporada = c.T603CodTemporada
              AND l.T630CodConcepto = c.T603Codigo AND l.T630Codigo = '1'
         WHERE c.T603CodEmpresa = ? AND c.T603Codigo = ? AND c.T603Imprimir <> 'N' LIMIT 1"
    );
    $items = [];
    $total = 0.0;
    $total_vat = 0.0;
    $total_discount = 0.0;
    foreach ($codes as $i => $item_code) {
        $n = $i + 1;
        $item_code = field($item_code);
        $line->execute([$company_id, $item_code]);
        $c = $line->fetch();
        if (!$c) {
            return ['error' => str_replace('{c}', $item_code, t('Concepto no encontrado: {c}'))];
        }
        $qty = positive_decimal(field($in['quantity'][$i] ?? ''));
        if ($qty === null || $qty !== round($qty, 2) || strlen(legacy_num($qty, 2)) > 5) {
            return ['error' => str_replace('{n}', (string) $n, t('Cantidad no válida en el ítem {n}.'))];
        }
        $rate = vat_rate($c['vat_type'], $c['vat']);
        // The price of the list, VAT included. It changes only when the item allows it.
        $price = (float) $c['value'];
        if ($c['free_price'] === 'S') {
            $price = positive_decimal(field($in['value'][$i] ?? ''), true) ?? -1.0;
        }
        if ($price < 0 || ($price == 0 && $c['free_price'] !== 'S')) {
            return ['error' => str_replace('{n}', (string) $n, t('Valor no válido en el ítem {n}.'))];
        }
        $disc = positive_decimal(field($in['discount'][$i] ?? '') === '' ? '0' : field($in['discount'][$i]), true);
        if ($disc === null) {
            return ['error' => str_replace('{n}', (string) $n, t('Descuento no válido en el ítem {n}.'))];
        }
        if ($disc > 0 && $c['free_discount'] !== 'S') {
            return ['error' => str_replace('{n}', (string) $n, t('El ítem {n} no permite descuento.'))];
        }
        // The stored value has no VAT: base with 4 decimals, VAT with 2
        $base = round($price / (1 + $rate / 100), 4);
        $vat = round($qty * $base * $rate / 100, 2);
        $gross = $qty * $base + $vat;
        if ($disc > $gross) {
            return ['error' => str_replace('{n}', (string) $n, t('El descuento supera el valor del ítem {n}.'))];
        }
        $items[] = [
            'line_no' => $i, 'item_code' => $item_code, 'qty' => $qty, 'base' => $base, 'vat' => $vat, 'disc' => $disc, 'rate' => $rate,
            'type' => trim((string) $c['type']), 'cost' => max(0.0, (float) $c['cost']),
        ];
        $total += $gross - $disc;
        $total_vat += $vat;
        $total_discount += $disc;
    }
    return [
        'company_id' => $company_id, 'doc_prefix' => $doc_prefix, 'tax_id' => $tax_id, 'payment' => $payment, 'credit' => $f['T616Cartera'] === 'S',
        'salesperson' => $salesperson, 'date' => $date, 'd' => $d, 'due' => $due, 'detail' => $detail, 'items' => $items,
        'total' => round($total, 0), 'total_vat' => $total_vat, 'total_discount' => $total_discount,
    ];
}

// Takes the lock that keeps two users from getting the same number. Returns the lock name, or null.
function number_lock(PDO $db, string $kind, string $company_id, string $doc_prefix): ?string
{
    $dbname = (string) $db->query('SELECT DATABASE()')->fetchColumn();
    $lock = 'sori_' . $kind . '_' . md5($dbname . '|' . $company_id . '|' . $doc_prefix);
    $st = $db->prepare('SELECT GET_LOCK(?, 5)');
    $st->execute([$lock]);
    return (int) $st->fetchColumn() === 1 ? $lock : null;
}

function number_unlock(PDO $db, string $lock): void
{
    $db->prepare('SELECT RELEASE_LOCK(?)')->execute([$lock]);
}

// Saves a quote: header, items and audit line, in one transaction.
// Returns ['keys' => [...]] to open the record, or ['error' => message].
function quote_save(PDO $db, string $entered_by, array $in): array
{
    $company_id = company_code($db);
    $entered_by = substr($entered_by, 0, 20);
    $v = document_validate($db, $in, $company_id);
    if (isset($v['error'])) {
        return $v;
    }

    $lock = number_lock($db, 'cot', $company_id, $v['doc_prefix']);
    if ($lock === null) {
        return ['error' => t('No se pudo asignar el número. Intente de nuevo.')];
    }
    try {
        $db->beginTransaction();
        $st = $db->prepare('SELECT COALESCE(MAX(CAST(T638NumFactura AS UNSIGNED)), 0) + 1 FROM T638COTIZACION WHERE T638CodEmpresa = ? AND T638Prefijo = ?');
        $st->execute([$company_id, $v['doc_prefix']]);
        $num = (string) $st->fetchColumn();

        $db->prepare(
            'INSERT INTO T638COTIZACION (T638CodEmpresa, T638Prefijo, T638NumFactura, T638Fecha, T638CodTercero, T638Total,
                T638TotalIVA, T638TotalDescuento, T638CodFormaPago, T638Detalle, T638Cancelado, T638FechaIni, T638HoraIni,
                T638FechaFin, T638HoraFin, T638TiempoFactura, T638Piso, T638Area, T638Habitacion, T638FechaVence,
                T638Vendedor, T638Digita, T638PorcRetencion, T638Retencion)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        )->execute([
            $company_id, $v['doc_prefix'], $num, $v['date'], $v['tax_id'], legacy_num($v['total'], 0), legacy_num($v['total_vat'], 2),
            legacy_num($v['total_discount'], 2), $v['payment'], $v['detail'] === '' ? ' ' : $v['detail'], 'N', ' ', date('H:i'),
            ' ', ' ', ' ', ' ', ' ', ' ', $v['due'], $v['salesperson'] === '' ? ' ' : $v['salesperson'], $entered_by, '0', '0',
        ]);

        $ins = $db->prepare(
            'INSERT INTO T639CONTIZADETALLE (T639CodEmpresa, T639Prefijo, T639NumFactura, T639Consecutivo, T639Cantidad,
                T639CodConcepto, T639Valor, T639ValorIVA, T639SubCodConcepto, T639Descuento, T639CodCentro, T639Digita,
                T639PorcIVA, T639Observacion, T639FechaVence, T639Lote)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        foreach ($v['items'] as $it) {
            $ins->execute([
                $company_id, $v['doc_prefix'], $num, (string) $it['line_no'], legacy_num($it['qty'], 2), $it['item_code'], legacy_num($it['base'], 4),
                legacy_num($it['vat'], 2), '1', legacy_num($it['disc'], 2), '00', $entered_by, legacy_num($it['rate'], 2), ' ',
                '01/01/1900', ' ',
            ]);
        }

        audit($db, $entered_by, 'COTIZACION ' . $v['doc_prefix'] . '-' . $num);
        $db->commit();
    } catch (Throwable $ex) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        error_log('sori: quote not saved: ' . $ex->getMessage());
        return ['error' => t('No se pudo guardar la cotización.')];
    } finally {
        number_unlock($db, $lock);
    }
    return ['keys' => ['k0' => $company_id, 'k1' => $v['doc_prefix'], 'k2' => $num, 'k3' => $entered_by]];
}

// One line in the audit table: type 2 is "saved", type 3 is "deleted"
function audit(PDO $db, string $username, string $detail, string $type = '2'): void
{
    $db->prepare('INSERT INTO CAUDITORIA (Fecha, Hora, Usuario, TipoAuditoria, Detalle) VALUES (?, ?, ?, ?, ?)')
        ->execute([date('d/m/Y'), date('H:i:s'), $username, $type, $detail]);
}
