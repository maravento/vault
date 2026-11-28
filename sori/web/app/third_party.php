<?php
// SORI writes: create and edit a third party (client, supplier, employee). It follows the legacy program, checked on real data:
// the check digit is computed with the tax authority formula, blanks are a single space, the money and withholding columns start
// at 0, the person is natural (four names) or legal (one company name), and the types go in their own table.
// FILE: app/third_party.php
declare(strict_types=1);

// Check digit of a tax number: weights 3,7,13,17,... from the right, remainder of 11
function tax_id_check_digit(string $tax_id): string
{
    $weights = [3, 7, 13, 17, 19, 23, 29, 37, 41, 43, 47, 53, 59, 67, 71];
    $sum = 0;
    foreach (array_reverse(str_split($tax_id)) as $i => $d) {
        $sum += (int) $d * $weights[$i];
    }
    $m = $sum % 11;
    return (string) ($m < 2 ? $m : 11 - $m);
}

// Lists the form needs
function party_options(PDO $db): array
{
    $q = static fn(string $sql): array => $db->query($sql)->fetchAll();
    $company_id = $db->query("SELECT T10CodDpto AS department, T10CodCiudad AS city FROM T10EMPRESA LIMIT 1")->fetch() ?: ['department' => '', 'city' => ''];
    return [
        'doc_types' => $q('SELECT T55Codigo AS code, T55Nombre AS name FROM T55TIPODOCUMENTO ORDER BY CAST(T55Codigo AS UNSIGNED)'),
        'departments' => $q('SELECT T19Codigo AS code, T19Nombre AS name FROM T19DPTO ORDER BY T19Nombre'),
        'cities' => $q('SELECT T20CodDpto AS department, T20Codigo AS code, T20Nombre AS name FROM T20CIUDAD ORDER BY T20Nombre'),
        'professions' => $q('SELECT T57Codigo AS code, T57Nombre AS name FROM T57PROFESION ORDER BY CAST(T57Codigo AS UNSIGNED)'),
        'ratings' => $q('SELECT T15Codigo AS code, T15Nombre AS name FROM T15CALIFTERCERO ORDER BY CAST(T15Codigo AS UNSIGNED)'),
        'types' => $q('SELECT T14Codigo AS code, T14Nombre AS name FROM T14TIPOTERCERO ORDER BY CAST(T14Codigo AS UNSIGNED)'),
        'payments' => $q('SELECT T616Codigo AS code, T616Nombre AS name FROM T616TIPOFORMAPAGO ORDER BY CAST(T616Codigo AS UNSIGNED)'),
        'salespeople' => $q("SELECT T625Codigo AS code, T625Nombre AS name FROM T625VENDEDOR WHERE T625Activo = 'S' ORDER BY T625Nombre"),
        'company' => ['department' => trim((string) $company_id['department']), 'city' => trim((string) $company_id['city'])],
    ];
}

// A third party with its types, shaped like the form fields. Null when it does not exist.
function party_read(PDO $db, string $company_id, string $tax_id): ?array
{
    $st = $db->prepare('SELECT * FROM T12TERCERO WHERE T12CodEmpresa = ? AND T12Nit = ?');
    $st->execute([$company_id, $tax_id]);
    $r = $st->fetch();
    if (!$r) {
        return null;
    }
    $t = static fn(string $c): string => trim((string) $r[$c]);
    $st = $db->prepare('SELECT T13CodTipoTer FROM T13TERCEROPORTIPO WHERE T13CodEmpresa = ? AND T13Nit = ?');
    $st->execute([$company_id, $tax_id]);
    return [
        'tax_id' => $t('T12Nit'), 'check_digit' => $t('T12Dv'), 'doc_type' => $t('T12TipoDoc'), 'person_type' => $t('T12TipoPersona'),
        'name' => $t('T12Nombre'), 'middle_name' => $t('T12Nombre2'), 'last_name' => $t('T12Apellido'), 'second_last_name' => $t('T12Apellido2'),
        'company_name' => $t('T12RazonSocial'), 'department' => $t('T12CodDpto'), 'city' => $t('T12CodCiudad'), 'address' => $t('T12Direccion'),
        'phone' => $t('T12Telefono'), 'mobile' => $t('T12Celular1'), 'email' => $t('T12EMail'), 'sex' => $t('T12Sexo'),
        'birth_date' => $t('T12FechaNace'), 'remark' => $t('T12Observacion'), 'regime' => $t('T12TipoRegimen'),
        'profession' => $t('T12Profesion'), 'rating' => $t('T12CodCalifica'), 'credit_limit' => $t('T12Cupo'), 'invoice_limit' => $t('T12CupoFacturas'),
        'payment' => $t('T12FormaPago'), 'salesperson' => $t('T12Vendedor'), 'country' => $t('T12Pais'),
        'types' => array_map('trim', $st->fetchAll(PDO::FETCH_COLUMN)),
    ];
}

// Saves a new third party or the changes of an existing one. One transaction.
// Returns ['keys' => [...]] or ['error' => message].
function party_save(PDO $db, string $entered_by, array $in, bool $new): array
{
    $company_id = company_code($db);
    $entered_by = substr($entered_by, 0, 20);
    $tax_id = field($in['tax_id'] ?? '');
    $c = static fn(string $k): string => field($in[$k] ?? '');
    $row_exists = static function (string $sql, array $p) use ($db): bool {
        $st = $db->prepare($sql);
        $st->execute($p);
        return (bool) $st->fetchColumn();
    };

    if (!preg_match('/^[0-9]{3,15}$/', $tax_id)) {
        return ['error' => t('Documento no válido: use entre 3 y 15 números, sin puntos ni guiones.')];
    }
    $doc_type = $c('doc_type');
    if (!$row_exists('SELECT 1 FROM T55TIPODOCUMENTO WHERE T55Codigo = ?', [$doc_type])) {
        return ['error' => t('Tipo de documento no válido.')];
    }
    $person_type = $c('person_type');
    if ($person_type !== '0' && $person_type !== '1') {
        return ['error' => t('Tipo de persona no válido.')];
    }
    $fields = ['name' => 50, 'middle_name' => 20, 'last_name' => 50, 'second_last_name' => 20, 'company_name' => 80, 'address' => 100, 'remark' => 255, 'email' => 50];
    foreach ($fields as $k => $max) {
        if (text_length($c($k)) > $max) {
            return ['error' => str_replace('{n}', (string) $max, t('Un texto supera los {n} caracteres.'))];
        }
    }
    if ($person_type === '0') {
        if ($c('name') === '') {
            return ['error' => t('Indique el nombre.')];
        }
        $company_name = '';
    } else {
        if ($c('company_name') === '') {
            return ['error' => t('Indique la razón social.')];
        }
        $company_name = $c('company_name');
    }
    $department = $c('department');
    $city = $c('city');
    $st = $db->prepare('SELECT T20Nombre FROM T20CIUDAD WHERE T20CodDpto = ? AND T20Codigo = ?');
    $st->execute([$department, $city]);
    $city_name = $st->fetchColumn();
    if ($city_name === false) {
        return ['error' => t('Departamento o ciudad no válidos.')];
    }
    // The address is required by the tax reports; the legacy program fills it with the city name
    $address = $c('address') === '' ? trim((string) $city_name) : $c('address');
    foreach (['phone', 'mobile'] as $k) {
        if ($c($k) !== '' && !preg_match('/^[0-9 +()-]{1,30}$/', $c($k))) {
            return ['error' => t('Teléfono no válido.')];
        }
    }
    if ($c('email') !== '' && !filter_var($c('email'), FILTER_VALIDATE_EMAIL)) {
        return ['error' => t('Correo no válido.')];
    }
    if ($c('sex') !== '' && $c('sex') !== '1' && $c('sex') !== '2') {
        return ['error' => t('Sexo no válido.')];
    }
    $birth_date = $c('birth_date');
    if ($birth_date !== '') {
        $d = DateTimeImmutable::createFromFormat('!d/m/Y', $birth_date);
        if ($d === false || $d->format('d/m/Y') !== $birth_date || $d > new DateTimeImmutable('today')) {
            return ['error' => t('Fecha de nacimiento no válida.')];
        }
    }
    // Régimen codes seen in the data: 0 none, 1 common, 2 simplified, 3 large taxpayer
    if (!in_array($c('regime'), ['0', '1', '2', '3'], true)) {
        return ['error' => t('Régimen no válido.')];
    }
    if ($c('profession') !== '' && !$row_exists('SELECT 1 FROM T57PROFESION WHERE T57Codigo = ?', [$c('profession')])) {
        return ['error' => t('Profesión no válida.')];
    }
    if ($c('rating') !== '' && !$row_exists('SELECT 1 FROM T15CALIFTERCERO WHERE T15Codigo = ?', [$c('rating')])) {
        return ['error' => t('Calificación no válida.')];
    }
    if ($c('payment') !== '' && !$row_exists('SELECT 1 FROM T616TIPOFORMAPAGO WHERE T616Codigo = ?', [$c('payment')])) {
        return ['error' => t('Forma de pago no válida.')];
    }
    if ($c('salesperson') !== '' && !$row_exists("SELECT 1 FROM T625VENDEDOR WHERE T625Codigo = ? AND T625Activo = 'S'", [$c('salesperson')])) {
        return ['error' => t('Vendedor no válido.')];
    }
    $credit_limit = $c('credit_limit') === '' ? 0.0 : positive_decimal($c('credit_limit'), true);
    if ($credit_limit === null || $credit_limit > 999999999999) {
        return ['error' => t('Cupo no válido.')];
    }
    $invoice_limit = $c('invoice_limit') === '' ? '0' : $c('invoice_limit');
    if (!preg_match('/^(0|[1-9][0-9]{0,2})$/', $invoice_limit)) {
        return ['error' => t('Cupo de facturas no válido.')];
    }
    $country = strtoupper($c('country') === '' ? 'CO' : $c('country'));
    if (!preg_match('/^[A-Z]{2}$/', $country)) {
        return ['error' => t('País no válido: use el código de dos letras.')];
    }
    $types = [];
    foreach ((array) ($in['types'] ?? []) as $t) {
        $t = field($t);
        if (!$row_exists('SELECT 1 FROM T14TIPOTERCERO WHERE T14Codigo = ?', [$t])) {
            return ['error' => t('Tipo de tercero no válido.')];
        }
        $types[$t] = $t;
    }

    $blank_if_empty = static fn(string $v): string => $v === '' ? ' ' : $v;
    $data = [
        'T12TipoDoc' => $doc_type, 'T12TipoPersona' => $person_type, 'T12Nombre' => $blank_if_empty($person_type === '0' ? $c('name') : ''),
        'T12Nombre2' => $blank_if_empty($person_type === '0' ? $c('middle_name') : ''), 'T12Apellido' => $blank_if_empty($person_type === '0' ? $c('last_name') : ''),
        'T12Apellido2' => $blank_if_empty($person_type === '0' ? $c('second_last_name') : ''), 'T12RazonSocial' => $blank_if_empty($company_name),
        'T12CodDpto' => $department, 'T12CodCiudad' => $city, 'T12Direccion' => $address, 'T12Telefono' => $blank_if_empty($c('phone')),
        'T12Celular1' => $blank_if_empty($c('mobile')), 'T12EMail' => $blank_if_empty($c('email')), 'T12Sexo' => $blank_if_empty($c('sex')), 'T12FechaNace' => $blank_if_empty($birth_date),
        'T12Observacion' => $blank_if_empty($c('remark')), 'T12TipoRegimen' => $c('regime'), 'T12Profesion' => $blank_if_empty($c('profession')),
        'T12CodCalifica' => $blank_if_empty($c('rating')), 'T12Cupo' => legacy_num($credit_limit, 0), 'T12CupoFacturas' => $invoice_limit,
        'T12FormaPago' => $blank_if_empty($c('payment')), 'T12Vendedor' => $blank_if_empty($c('salesperson')), 'T12Pais' => $country,
    ];

    try {
        $db->beginTransaction();
        if ($new) {
            $record = [];
            foreach ($db->query('SHOW COLUMNS FROM T12TERCERO')->fetchAll() as $col) {
                $record[$col['Field']] = ' ';
            }
            $today = date('d/m/Y');
            $record = array_merge($record, $data, [
                'T12CodEmpresa' => $company_id, 'T12Nit' => $tax_id, 'T12Dv' => tax_id_check_digit($tax_id), 'T12FechaIngreso' => $today, 'T12Fax' => $today,
                'T12Saldo' => '0', 'T12ReteCompras' => '0', 'T12ReteVentas' => '0', 'T12ReteIVAComp' => '0', 'T12ReteICAComp' => '0',
                'T12ReteIVAVenta' => '0', 'T12ReteICAVenta' => '0',
            ]);
            $db->prepare('INSERT INTO T12TERCERO (' . implode(', ', array_keys($record)) . ') VALUES (' . implode(', ', array_fill(0, count($record), '?')) . ')')
                ->execute(array_values($record));
        } else {
            $st = $db->prepare('SELECT 1 FROM T12TERCERO WHERE T12CodEmpresa = ? AND T12Nit = ? FOR UPDATE');
            $st->execute([$company_id, $tax_id]);
            if (!$st->fetchColumn()) {
                $db->rollBack();
                return ['error' => t('Tercero no encontrado.')];
            }
            $sets = implode(', ', array_map(static fn(string $k): string => "$k = ?", array_keys($data)));
            $db->prepare("UPDATE T12TERCERO SET $sets WHERE T12CodEmpresa = ? AND T12Nit = ?")->execute([...array_values($data), $company_id, $tax_id]);
        }
        $db->prepare('DELETE FROM T13TERCEROPORTIPO WHERE T13CodEmpresa = ? AND T13Nit = ?')->execute([$company_id, $tax_id]);
        $ins = $db->prepare('INSERT INTO T13TERCEROPORTIPO (T13CodEmpresa, T13Nit, T13CodTipoTer) VALUES (?, ?, ?)');
        foreach ($types as $t) {
            $ins->execute([$company_id, $tax_id, $t]);
        }
        audit($db, $entered_by, 'TERCERO ' . $tax_id);
        $db->commit();
    } catch (PDOException $ex) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        if ($ex->getCode() === '23000') {
            return ['error' => t('Ya existe un tercero con ese documento.')];
        }
        error_log('sori: third party not saved: ' . $ex->getMessage());
        return ['error' => t('No se pudo guardar el tercero.')];
    }
    return ['keys' => ['k0' => $company_id, 'k1' => $tax_id]];
}
