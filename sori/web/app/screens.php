<?php
// Views of the modules: which table each one lists, how it is searched and what it shows.
// FILE: app/screens.php
//
// alias   alias of the main table in 'from'
// pk      columns of the main table that identify a record; null when it has none
// cols    [label, SQL expression, type]; the type is text (default) or money
// search  SQL expressions the search box looks into
// hijos   child rows shown in the detail; 'where' maps a child column to a parent column

// Same shape for the accounting and the NIIF documents, which differ only by table names
function accounting_screen(string $suffix): array
{
    return [
        'alias' => 'd',
        'from' => "T104DOCUMENTO$suffix d LEFT JOIN T26TIPODOCUMENTOCIA k ON k.T26CodEmpresa = d.T104CodEmpresa AND k.T26Codigo = d.T104CodTipoDoc",
        'pk' => ['T104CodEmpresa', 'T104Agno', 'T104CodTipoDoc', 'T104NumeroDoc'],
        'cols' => [
            ['Año', 'd.T104Agno'],
            ['Tipo de documento', 'k.T26Nombre'],
            ['Número', 'd.T104NumeroDoc'],
            ['Fecha', 'd.T104Fecha'],
            ['Concepto', 'd.T104Concepto'],
            ['Valor total', 'd.T104ValorTotal', 'money'],
            ['Anulado', 'd.T104Anulado'],
        ],
        'search' => ['d.T104NumeroDoc', 'd.T104Concepto', 'k.T26Nombre'],
        'order' => date_sql('d.T104Fecha') . ' DESC, CAST(d.T104NumeroDoc AS UNSIGNED) DESC',
        'title' => 'Documento {T104NumeroDoc}',
        'children' => [[
            'title' => 'Movimientos',
            'from' => "T106MOVIMIENTO$suffix m LEFT JOIN T100CUENTA$suffix c ON c.T100CodEmpresa = m.T106CodEmpresa AND c.T100Agno = m.T106Agno AND c.T100CodCta = m.T106CodCta",
            'where' => [
                'm.T106CodEmpresa' => 'T104CodEmpresa', 'm.T106Agno' => 'T104Agno',
                'm.T106CodTipoDoc' => 'T104CodTipoDoc', 'm.T106NumeroDoc' => 'T104NumeroDoc',
            ],
            'cols' => [
                ['Cuenta', 'm.T106CodCta'],
                ['Nombre de la cuenta', 'c.T100Nombre'],
                ['Tercero', 'm.T106Nit'],
                ['Detalle', 'm.T106Detalle'],
                ['Débito', 'm.T106ValorDebito', 'money'],
                ['Crédito', 'm.T106ValorCredito', 'money'],
            ],
            'order' => 'CAST(m.T106ConsecCta AS UNSIGNED), m.T106CodCta',
        ]],
    ];
}

// Condition: the third party 't' has the given type (1 client, 2 supplier, 3 employee)
$of_type = static fn(string $type) =>
    "EXISTS (SELECT 1 FROM T13TERCEROPORTIPO y WHERE y.T13CodEmpresa = t.T12CodEmpresa AND y.T13Nit = t.T12Nit AND y.T13CodTipoTer = '$type')";

// Column of the latest numbering resolution of the prefix of the row 'x' in the DIAN view
$last_resolution = static fn(string $col) =>
    "(SELECT r.$col FROM T704RANGOFACTURA r WHERE r.T704CodPrefijo = x.T629Codigo ORDER BY "
    . date_sql('r.T704FechaIni') . ' DESC LIMIT 1)';

// Join that gives the name of the concept of an item row; $p is the column prefix, like T605
$item_line = static fn(string $d, string $p) =>
    "LEFT JOIN T603CONCEPTO c ON c.T603CodEmpresa = $d.{$p}CodEmpresa AND c.T603Codigo = $d.{$p}CodConcepto";

return [
    'parties' => [
        'new' => ['/module/parties/new', 'Nuevo tercero'],
        'edit_cfg' => ['route' => '/module/parties/edit', 'text' => 'Editar tercero'],
        'alias' => 't',
        'from' => 'T12TERCERO t',
        'pk' => ['T12CodEmpresa', 'T12Nit'],
        'note' => 'Las personas y empresas con las que se relaciona el negocio. Cada factura, abono y compra apunta a una de ellas.',
        'filter' => [
            'options_list' => [
                '1' => ['Clientes', $of_type('1')],
                '2' => ['Proveedores', $of_type('2')],
                '3' => ['Empleados', $of_type('3')],
                'n' => ['Sin clasificar', 'NOT EXISTS (SELECT 1 FROM T13TERCEROPORTIPO y WHERE y.T13CodEmpresa = t.T12CodEmpresa AND y.T13Nit = t.T12Nit)'],
            ],
        ],
        'cols' => [
            ['NIT', "CONCAT(t.T12Nit, IF(TRIM(t.T12Dv) <> '', CONCAT('-', TRIM(t.T12Dv)), ''))"],
            ['Nombre', party_name('t')],
            ['Tipo', "(SELECT GROUP_CONCAT(DISTINCT k.T14Nombre ORDER BY k.T14Codigo SEPARATOR ', ') FROM T13TERCEROPORTIPO y "
                . 'JOIN T14TIPOTERCERO k ON k.T14Codigo = y.T13CodTipoTer '
                . 'WHERE y.T13CodEmpresa = t.T12CodEmpresa AND y.T13Nit = t.T12Nit)'],
            ['Teléfono', 't.T12Telefono'],
            ['Celular', 't.T12Celular1'],
            ['Correo', 't.T12EMail'],
        ],
        'search' => ['t.T12Nit', 't.T12RazonSocial', 't.T12Nombre', 't.T12Nombre2', 't.T12Apellido', 't.T12Apellido2'],
        'order' => party_name('t'),
        'title' => 'Tercero {T12Nit}',
        'children' => [[
            'title' => 'Facturas del tercero',
            'from' => 'T604FACTURA f',
            'where' => ['f.T604CodEmpresa' => 'T12CodEmpresa', 'f.T604CodTercero' => 'T12Nit'],
            'cols' => [
                ['Prefijo', 'f.T604Prefijo'],
                ['Número', 'f.T604NumFactura'],
                ['Fecha', 'f.T604Fecha'],
                ['Total', 'f.T604Total', 'money'],
            ],
            'order' => date_sql('f.T604Fecha') . ' DESC, CAST(f.T604NumFactura AS UNSIGNED) DESC',
        ]],
    ],

    'invoices' => [
        'alias' => 'f',
        'from' => 'T604FACTURA f '
            . 'LEFT JOIN T12TERCERO t ON t.T12CodEmpresa = f.T604CodEmpresa AND t.T12Nit = f.T604CodTercero '
            . 'LEFT JOIN T616TIPOFORMAPAGO p ON p.T616Codigo = f.T604CodFormaPago',
        'pk' => ['T604CodEmpresa', 'T604Prefijo', 'T604NumFactura'],
        'new' => ['/module/invoices/new', 'Nueva factura'],
        'cancel_cfg' => [
            'route' => '/module/invoices/cancel', 'field' => 'T604Cancelado', 'text' => 'Anular factura',
            'confirm' => '¿Anular esta factura? Se devuelven las existencias y se borra su asiento contable.',
            'cancelled' => 'Esta factura está anulada.',
            'receive' => ['route' => '/module/receivables/new', 'text' => 'Registrar abono'],
            'return_cfg' => ['route' => '/module/invoices/return', 'text' => 'Devolución de cliente'],
        ],
        'cols' => [
            ['Prefijo', 'f.T604Prefijo'],
            ['Número', 'f.T604NumFactura'],
            ['Fecha', 'f.T604Fecha'],
            ['Tercero', party_name('t')],
            ['Forma de pago', 'p.T616Nombre'],
            ['Total', 'f.T604Total', 'money'],
            ['IVA', 'f.T604TotalIVA', 'money'],
            ['CUFE', "IF(TRIM(f.T604CUFE) <> '', 'Sí', 'No')"],
        ],
        'search' => ['f.T604NumFactura', 'f.T604Prefijo', 'f.T604CodTercero', 't.T12RazonSocial', 't.T12Nombre', 't.T12Apellido'],
        'order' => date_sql('f.T604Fecha') . ' DESC, CAST(f.T604NumFactura AS UNSIGNED) DESC',
        'title' => 'Factura {T604Prefijo}-{T604NumFactura}',
        'children' => [[
            'title' => 'Ítems de la factura',
            'from' => 'T605FACTURADETALLE d ' . $item_line('d', 'T605'),
            'where' => ['d.T605CodEmpresa' => 'T604CodEmpresa', 'd.T605Prefijo' => 'T604Prefijo', 'd.T605NumFactura' => 'T604NumFactura'],
            'cols' => [
                ['Ítem', 'd.T605Consecutivo'],
                ['Código', 'd.T605CodConcepto'],
                ['Concepto', 'c.T603Nombre'],
                ['Cantidad', 'd.T605Cantidad'],
                ['Valor', 'd.T605Valor', 'money'],
                ['IVA', 'd.T605ValorIVA', 'money'],
                ['Descuento', 'd.T605Descuento', 'money'],
            ],
            'order' => 'CAST(d.T605Consecutivo AS UNSIGNED)',
        ]],
    ],

    'resolutions' => [
        'alias' => 'x',
        'from' => 'T629PREFIJO x',
        'pk' => ['T629Codigo'],
        'note' => 'Series de numeración con su última resolución de la DIAN. «Con CUFE» cuenta las facturas que ya tienen '
            . 'código único de factura electrónica. El envío a la DIAN aún no está implementado.',
        'cols' => [
            ['Prefijo', 'x.T629Codigo'],
            ['Nombre', 'x.T629Nombre'],
            ['Activo', "IF(x.T629Activo = 'S', 'Sí', 'No')"],
            ['Factura electrónica', "IF(x.T629FactElectro = 'S', 'Sí', 'No')"],
            ['POS electrónico', "IF(x.T629PosElectro = 'S', 'Sí', 'No')"],
            ['Resolución', $last_resolution('T704Resolucion')],
            ['Vigente hasta', $last_resolution('T704FechaFin')],
            ['Rango autorizado', "CONCAT_WS(' - ', " . $last_resolution('T704NumeroIni') . ', ' . $last_resolution('T704NumeroFin') . ')'],
            ['Facturas', '(SELECT COUNT(*) FROM T604FACTURA f WHERE f.T604Prefijo = x.T629Codigo)'],
            ['Con CUFE', "(SELECT COUNT(*) FROM T604FACTURA f WHERE f.T604Prefijo = x.T629Codigo AND TRIM(f.T604CUFE) <> '')"],
        ],
        'search' => ['x.T629Codigo', 'x.T629Nombre'],
        'order' => 'CAST(x.T629Codigo AS UNSIGNED), x.T629Codigo',
        'title' => 'Prefijo {T629Codigo} {T629Nombre}',
        'children' => [[
            'title' => 'Resoluciones de numeración',
            'from' => 'T704RANGOFACTURA r',
            'where' => ['r.T704CodPrefijo' => 'T629Codigo'],
            'cols' => [
                ['Resolución', 'r.T704Resolucion'],
                ['Desde', 'r.T704FechaIni'],
                ['Hasta', 'r.T704FechaFin'],
                ['Número inicial', 'r.T704NumeroIni'],
                ['Número final', 'r.T704NumeroFin'],
                ['Observación', 'r.T704Observacion'],
            ],
            'order' => date_sql('r.T704FechaIni') . ' DESC',
        ]],
    ],

    'products' => [
        'new' => ['/module/products/new', 'Nuevo producto'],
        'edit_cfg' => ['route' => '/module/products/edit', 'text' => 'Editar producto'],
        'alias' => 'c',
        'from' => 'T603CONCEPTO c',
        'pk' => ['T603CodEmpresa', 'T603Codigo', 'T603CodTemporada'],
        'cols' => [
            ['Código', 'c.T603Codigo'],
            ['Nombre', 'c.T603Nombre'],
            ['Tipo', 'c.T603Tipo'],
            ['Unidad de medida', 'c.T603UnidadMedida'],
            ['Costo promedio', 'c.T603CostoPromedio', 'money'],
            ['Última compra', 'c.T603UltValorCompra', 'money'],
        ],
        'search' => ['c.T603Codigo', 'c.T603Nombre'],
        'order' => 'c.T603Nombre',
        'title' => 'Concepto {T603Codigo}',
        'children' => [[
            'title' => 'Existencias por centro',
            'from' => 'T637TOTALES s',
            'where' => ['s.T637CodEmpresa' => 'T603CodEmpresa', 's.T637CodConcepto' => 'T603Codigo'],
            'cols' => [
                ['Centro', 's.T637CodCentro'],
                ['Entradas', 's.T637CantEntrada'],
                ['Salidas', 's.T637CantSalida'],
                ['Saldo', '(s.T637CantEntrada + 0) - (s.T637CantSalida + 0)'],
            ],
            'order' => 's.T637CodCentro',
        ]],
    ],

    'quotes' => [
        'alias' => 'q',
        'from' => 'T638COTIZACION q '
            . 'LEFT JOIN T12TERCERO t ON t.T12CodEmpresa = q.T638CodEmpresa AND t.T12Nit = q.T638CodTercero',
        'pk' => ['T638CodEmpresa', 'T638Prefijo', 'T638NumFactura', 'T638Digita'],
        'cols' => [
            ['Prefijo', 'q.T638Prefijo'],
            ['Número', 'q.T638NumFactura'],
            ['Fecha', 'q.T638Fecha'],
            ['Tercero', party_name('t')],
            ['Total', 'q.T638Total', 'money'],
            ['IVA', 'q.T638TotalIVA', 'money'],
        ],
        'search' => ['q.T638NumFactura', 'q.T638CodTercero', 't.T12RazonSocial', 't.T12Nombre', 't.T12Apellido'],
        'order' => date_sql('q.T638Fecha') . ' DESC, CAST(q.T638NumFactura AS UNSIGNED) DESC',
        'title' => 'Cotización {T638Prefijo}-{T638NumFactura}',
        'new' => ['/module/quotes/new', 'Nueva cotización'],
        'children' => [[
            'title' => 'Ítems de la cotización',
            'from' => 'T639CONTIZADETALLE d ' . $item_line('d', 'T639'),
            'where' => [
                'd.T639CodEmpresa' => 'T638CodEmpresa', 'd.T639Prefijo' => 'T638Prefijo',
                'd.T639NumFactura' => 'T638NumFactura', 'd.T639Digita' => 'T638Digita',
            ],
            'cols' => [
                ['Ítem', 'd.T639Consecutivo'],
                ['Código', 'd.T639CodConcepto'],
                ['Concepto', 'c.T603Nombre'],
                ['Cantidad', 'd.T639Cantidad'],
                ['Valor', 'd.T639Valor', 'money'],
                ['IVA', 'd.T639ValorIVA', 'money'],
                ['Descuento', 'd.T639Descuento', 'money'],
            ],
            'order' => 'CAST(d.T639Consecutivo AS UNSIGNED)',
        ]],
    ],

    'receivables' => [
        'alias' => 'a',
        'from' => 'T626ABONO a '
            . 'LEFT JOIN T12TERCERO t ON t.T12CodEmpresa = a.T626CodEmpresa AND t.T12Nit = a.T626CodTercero',
        'pk' => ['T626CodEmpresa', 'T626NumAbono', 'T626Prefijo', 'T626NumFactura', 'T626PrefijoAbono'],
        'cols' => [
            ['Abono', "CONCAT_WS('-', NULLIF(TRIM(a.T626PrefijoAbono), ''), a.T626NumAbono)"],
            ['Fecha', 'a.T626Fecha'],
            ['Factura', "CONCAT_WS('-', NULLIF(TRIM(a.T626Prefijo), ''), a.T626NumFactura)"],
            ['Tercero', party_name('t')],
            ['Forma de pago', 'a.T626FormaPago'],
            ['Valor', 'a.T626Valor', 'money'],
            ['Observación', 'a.T626Observacion'],
        ],
        'search' => ['a.T626NumAbono', 'a.T626NumFactura', 'a.T626CodTercero', 't.T12RazonSocial', 't.T12Nombre', 't.T12Apellido'],
        'order' => date_sql('a.T626Fecha') . ' DESC, CAST(a.T626NumAbono AS UNSIGNED) DESC',
        'title' => 'Abono {T626PrefijoAbono}-{T626NumAbono}',
        'new' => ['/module/receivables/new', 'Nuevo abono'],
    ],

    'payables' => [
        'new' => ['/module/payables/new', 'Nuevo pago a proveedor'],
        'alias' => 'a',
        'from' => 'T628ABONOCOMPRA a '
            . 'LEFT JOIN T12TERCERO t ON t.T12CodEmpresa = a.T628CodEmpresa AND t.T12Nit = a.T628CodTercero '
            . 'LEFT JOIN T617TIPOTRANSACCION x ON x.T617Codigo = a.T628TipoTransaccion',
        'pk' => ['T628CodEmpresa', 'T628NumAbono', 'T628NumEntrada', 'T628TipoTransaccion', 'T628PrefijoAbono'],
        'cols' => [
            ['Abono', "CONCAT_WS('-', NULLIF(TRIM(a.T628PrefijoAbono), ''), a.T628NumAbono)"],
            ['Fecha', 'a.T628Fecha'],
            ['Entrada', 'a.T628NumEntrada'],
            ['Tipo de transacción', "COALESCE(NULLIF(x.T617Nombre, ''), a.T628TipoTransaccion)"],
            ['Proveedor', party_name('t')],
            ['Forma de pago', 'a.T628FormaPago'],
            ['Valor', 'a.T628Valor', 'money'],
        ],
        'search' => ['a.T628NumAbono', 'a.T628NumEntrada', 'a.T628CodTercero', 't.T12RazonSocial', 't.T12Nombre', 't.T12Apellido'],
        'order' => date_sql('a.T628Fecha') . ' DESC, CAST(a.T628NumAbono AS UNSIGNED) DESC',
        'title' => 'Abono de compra {T628PrefijoAbono}-{T628NumAbono}',
    ],

    'inventory' => [
        'alias' => 's',
        'from' => 'T637TOTALES s '
            . 'LEFT JOIN T603CONCEPTO c ON c.T603CodEmpresa = s.T637CodEmpresa AND c.T603Codigo = s.T637CodConcepto '
            . 'LEFT JOIN T24CENTROCOSTO z ON z.T24CodEmpresa = s.T637CodEmpresa AND z.T24CodCentro = s.T637CodCentro',
        'pk' => ['T637CodEmpresa', 'T637CodConcepto', 'T637CodCentro'],
        'note' => 'Entradas y salidas acumuladas por artículo y bodega, como las guarda el programa anterior. '
            . 'El saldo es entradas menos salidas.',
        'filter' => [
            'options_list' => [
                'm' => ['Con movimiento', '((s.T637CantEntrada + 0) <> 0 OR (s.T637CantSalida + 0) <> 0)'],
                's' => ['Con saldo', '((s.T637CantEntrada + 0) - (s.T637CantSalida + 0)) <> 0'],
            ],
        ],
        'cols' => [
            ['Código', 's.T637CodConcepto'],
            ['Artículo', 'c.T603Nombre'],
            ['Bodega', 'z.T24Nombre'],
            ['Entradas', 's.T637CantEntrada'],
            ['Salidas', 's.T637CantSalida'],
            ['Saldo', '(s.T637CantEntrada + 0) - (s.T637CantSalida + 0)'],
            ['Valor entradas', 's.T637TotalEntrada', 'money'],
            ['Valor salidas', 's.T637TotalSalida', 'money'],
        ],
        'search' => ['s.T637CodConcepto', 'c.T603Nombre', 'z.T24Nombre'],
        'order' => 'c.T603Nombre, s.T637CodCentro',
        'title' => 'Inventario {T637CodConcepto} bodega {T637CodCentro}',
    ],

    'purchases' => [
        'new' => ['/module/purchases/new', 'Nueva compra'],
        'return_cfg' => ['route' => '/module/purchases/return', 'text' => 'Devolución a proveedor'],
        'pay' => ['route' => '/module/payables/new', 'text' => 'Registrar pago'],
        'alias' => 'd',
        'from' => 'T611DOCUMENTO d '
            . 'LEFT JOIN T12TERCERO t ON t.T12CodEmpresa = d.T611CodEmpresa AND t.T12Nit = d.T611CodProveedor '
            . 'LEFT JOIN T617TIPOTRANSACCION x ON x.T617Codigo = d.T611TipoTransaccion '
            . 'LEFT JOIN T616TIPOFORMAPAGO p ON p.T616Codigo = d.T611FormaPago',
        'pk' => ['T611CodEmpresa', 'T611Agno', 'T611TipoTransaccion', 'T611NumeroDoc'],
        'cols' => [
            ['Año', 'd.T611Agno'],
            ['Tipo', 'x.T617Nombre'],
            ['Número', 'd.T611NumeroDoc'],
            ['Fecha', 'd.T611Fecha'],
            ['Tercero', party_name('t')],
            ['Forma de pago', 'p.T616Nombre'],
            ['Base', 'd.T611ValorBase', 'money'],
            ['IVA', 'd.T611ValorIVA', 'money'],
            ['Total', 'd.T611ValorTtFactura', 'money'],
            ['Anulado', 'd.T611Anular'],
        ],
        'search' => ['d.T611NumeroDoc', 'd.T611NumFactura', 'd.T611CodProveedor', 't.T12RazonSocial', 't.T12Nombre', 't.T12Apellido', 'x.T617Nombre'],
        'order' => date_sql('d.T611Fecha') . ' DESC, CAST(d.T611NumeroDoc AS UNSIGNED) DESC',
        'title' => 'Documento de almacén {T611NumeroDoc}',
        'children' => [[
            'title' => 'Movimientos del documento',
            'from' => 'T612MOVIMIENTO m LEFT JOIN T603CONCEPTO c ON c.T603CodEmpresa = m.T612CodEmpresa AND c.T603Codigo = m.T612CodArticulo',
            'where' => [
                'm.T612CodEmpresa' => 'T611CodEmpresa', 'm.T612Agno' => 'T611Agno',
                'm.T612TipoTransaccion' => 'T611TipoTransaccion', 'm.T612NumeroDoc' => 'T611NumeroDoc',
            ],
            'cols' => [
                ['Ítem', 'm.T612Consecutivo'],
                ['Código', 'm.T612CodArticulo'],
                ['Artículo', 'c.T603Nombre'],
                ['Cantidad', 'm.T612Cantidad'],
                ['Valor', 'm.T612ValorArticulo', 'money'],
                ['Descuento', 'm.T612ValorDescuento', 'money'],
                ['IVA', 'm.T612ValorIVA', 'money'],
            ],
            'order' => 'CAST(m.T612Consecutivo AS UNSIGNED)',
        ]],
    ],

    'transfers' => [
        'alias' => 'r',
        'from' => 'T633TRASLADO r',
        'pk' => ['T633CodEmpresa', 'T633Agno', 'T633Numero'],
        'cols' => [
            ['Año', 'r.T633Agno'],
            ['Número', 'r.T633Numero'],
            ['Fecha', 'r.T633Fecha'],
            ['Valor total', 'r.T633ValorTotal', 'money'],
            ['Concepto', 'r.T633Concepto'],
            ['Anulado', 'r.T633Anular'],
        ],
        'search' => ['r.T633Numero', 'r.T633Concepto'],
        'order' => date_sql('r.T633Fecha') . ' DESC, CAST(r.T633Numero AS UNSIGNED) DESC',
        'title' => 'Traslado {T633Numero}',
        'children' => [[
            'title' => 'Artículos trasladados',
            'from' => 'T634TRASLADOMOV m '
                . 'LEFT JOIN T603CONCEPTO ce ON ce.T603CodEmpresa = m.T634CodEmpresa AND ce.T603Codigo = m.T634CodArticuloE '
                . 'LEFT JOIN T603CONCEPTO cs ON cs.T603CodEmpresa = m.T634CodEmpresa AND cs.T603Codigo = m.T634CodArticuloS',
            'where' => ['m.T634CodEmpresa' => 'T633CodEmpresa', 'm.T634Agno' => 'T633Agno', 'm.T634NumeroDoc' => 'T633Numero'],
            'cols' => [
                ['Ítem', 'm.T634Consecutivo'],
                ['Entra', 'ce.T603Nombre'],
                ['Cantidad entra', 'm.T634CantidadE'],
                ['Sale', 'cs.T603Nombre'],
                ['Cantidad sale', 'm.T634CantidadS'],
                ['Valor', 'm.T634ValorArticuloE', 'money'],
            ],
            'order' => 'CAST(m.T634Consecutivo AS UNSIGNED)',
        ]],
    ],

    'accounting' => accounting_screen(''),
    'niif' => accounting_screen('NIIF'),

    'exogenous' => [
        'alias' => 'x',
        'from' => 'T53FORMATOEXOGENA x',
        'pk' => ['T53Agno', 'T53Codigo'],
        'cols' => [
            ['Año', 'x.T53Agno'],
            ['Código', 'x.T53Codigo'],
            ['Nombre', 'x.T53Nombre'],
            ['Columnas', "IF(TRIM(x.T53Detalle) = '', 0, LENGTH(x.T53Detalle) - LENGTH(REPLACE(x.T53Detalle, ';', '')) + 1)"],
        ],
        'note' => 'Formatos de información exógena de la DIAN, con las columnas del archivo que cada uno genera.',
        // The field holds the column codes of the file, separated by semicolons
        'price_list' => [
            'title' => 'Columnas del archivo',
            'field' => 'T53Detalle',
            'separator' => ';',
            'note' => 'Descripciones según el formato de la DIAN. Los códigos sin descripción no se han identificado.',
            'names' => [
                'cpt' => 'Concepto',
                'tdoc' => 'Tipo de documento',
                'nid' => 'Número de identificación',
                'check_digit' => 'Dígito de verificación',
                'apl1' => 'Primer apellido',
                'apl2' => 'Segundo apellido',
                'nom1' => 'Primer nombre',
                'nom2' => 'Otros nombres',
                'raz' => 'Razón social',
                'dir' => 'Dirección',
                'department' => 'Departamento',
                'mun' => 'Municipio',
                'country' => 'País',
                'payment_cfg' => 'Pago o abono en cuenta',
                'pnded' => 'Pago no deducible',
                'ided' => 'IVA deducible',
                'inded' => 'IVA no deducible',
                'retp' => 'Retención practicada',
                'reta' => 'Retención asumida',
                'comun' => 'Retención de IVA, régimen común',
                'simp' => 'Retención de IVA, régimen simplificado',
                'ndom' => 'Retención a no domiciliados',
            ],
        ],
        'search' => ['x.T53Codigo', 'x.T53Nombre'],
        'order' => 'x.T53Agno DESC, x.T53Codigo',
        'title' => 'Formato {T53Codigo} {T53Agno}',
    ],

    'payroll' => [
        'alias' => 'l',
        'from' => 'T140LIQUIDACION l '
            . 'LEFT JOIN T12TERCERO t ON t.T12CodEmpresa = l.T140CodEmpresa AND t.T12Nit = l.T140Nit '
            . 'LEFT JOIN T138PERIODO p ON p.T138CodEmpresa = l.T140CodEmpresa AND p.T138Codigo = l.T140CodPeriodo '
            . 'LEFT JOIN T137CONCEPTONOMINA c ON c.T137CodEmpresa = l.T140CodEmpresa AND c.T137Codigo = l.T140CodConcepto',
        'pk' => ['T140CodEmpresa', 'T140Nit', 'T140CodPeriodo', 'T140CodConcepto'],
        'cols' => [
            ['Empleado', party_name('t')],
            ['NIT', 'l.T140Nit'],
            ['Período', 'p.T138Nombre'],
            ['Concepto', 'c.T137Nombre'],
            ['Devengado', 'l.T140ValorDevengado', 'money'],
            ['Deducido', 'l.T140ValorDeducido', 'money'],
        ],
        'search' => ['l.T140Nit', 't.T12RazonSocial', 't.T12Nombre', 't.T12Apellido', 'p.T138Nombre', 'c.T137Nombre'],
        'order' => 'CAST(l.T140CodPeriodo AS UNSIGNED) DESC, ' . party_name('t'),
        'title' => 'Liquidación {T140Nit} período {T140CodPeriodo}',
    ],

    'certificates' => [
        'alias' => 'x',
        'from' => 'T664CERTIFICADOS x '
            . 'LEFT JOIN T12TERCERO t ON t.T12Nit = x.T664Infractor '
            . 'LEFT JOIN T20CIUDAD c ON c.T20CodDpto = x.T664CodDpto AND c.T20Codigo = x.T664CodCiudad',
        'pk' => ['T664NumeroCertificado'],
        'note' => 'Certificados de curso para infractores: comparendo, sanción y curso. '
            . 'Las columnas sin datos en esta base (comparendo, valores) están en el detalle.',
        'cols' => [
            ['Número', 'x.T664NumeroCertificado'],
            ['Infractor', "COALESCE(NULLIF(" . party_name('t') . ", ''), NULLIF(TRIM(x.T664Infractor), ''))"],
            ['Documento', 'x.T664Infractor'],
            ['Recibo de pago', 'x.T664ReciboPago'],
            ['Fecha del comparendo', 'x.T664FechaComparendo'],
            ['Curso programado', "CONCAT_WS(' ', x.T664FechaProgCurso, x.T664HoraProgCurso)"],
            ['Curso realizado', "CONCAT_WS(' ', x.T664FechaRealizacurso, x.T664HoraRealizaCurso)"],
            ['Sanción', 'x.T664TipoSancion'],
            ['Ciudad', 'c.T20Nombre'],
        ],
        'search' => ['x.T664NumeroCertificado', 'x.T664Infractor', 'x.T664ReciboPago', 't.T12Nombre', 't.T12Apellido', 't.T12RazonSocial'],
        'order' => 'CAST(x.T664NumeroCertificado AS UNSIGNED) DESC',
        'title' => 'Certificado {T664NumeroCertificado}',
    ],

    'depreciation' => [
        'alias' => 'x',
        'from' => 'T121DEPRECIACION x '
            . 'LEFT JOIN T100CUENTA c ON c.T100CodEmpresa = x.T121CodEmpresa AND c.T100Agno = x.T121Agno AND c.T100CodCta = x.T121CodCta',
        'pk' => null,
        'cols' => [
            ['Año', 'x.T121Agno'],
            ['Cuenta', 'x.T121CodCta'],
            ['Nombre de la cuenta', 'c.T100Nombre'],
            ['Cuenta cruce', 'x.T121CodCtaCruce'],
            ['Cuenta de aplicación', 'x.T121CodCtaAplication'],
            ['Fecha', 'x.T121Fecha'],
            ['Vida útil', 'x.T121VidaUtil'],
            ['Centro de costo', 'x.T121CodCentro'],
        ],
        'search' => ['x.T121CodCta', 'c.T100Nombre'],
        'order' => 'x.T121Agno DESC, x.T121CodCta',
        'title' => 'Depreciación {T121CodCta}',
    ],

    'calendar' => [
        'alias' => 'x',
        'from' => 'T49CALENDARIOTRIBUTARIO x '
            . 'LEFT JOIN T50TIPOCALENDARIO k ON k.T50Codigo = x.T49TipoCalendario '
            . 'LEFT JOIN T51PERIODOTRIBUTARIO p ON p.T51TipoCalendario = x.T49TipoCalendario AND p.T51Codigo = x.T49Periodo '
            . 'LEFT JOIN T52TIPODIGITOS g ON g.T52Codigo = x.T49TipoDigitos',
        'pk' => ['T49Agno', 'T49TipoCalendario', 'T49TipoDigitos', 'T49Digito', 'T49Periodo'],
        'note' => 'Fechas de vencimiento por año, tipo de calendario, dígito del NIT y período. '
            . 'Esta tabla está vacía en las cinco bases revisadas: los tipos y períodos son un catálogo que trae el programa.',
        'cols' => [
            ['Año', 'x.T49Agno'],
            ['Tipo de calendario', 'k.T50Nombre'],
            ['Dígitos', 'g.T52Nombre'],
            ['Dígito', 'x.T49Digito'],
            ['Período', 'p.T51Nombre'],
            ['Fecha de vencimiento', 'x.T49Fecha'],
        ],
        'search' => ['k.T50Nombre', 'p.T51Nombre', 'x.T49Agno'],
        'order' => 'x.T49Agno DESC, CAST(x.T49TipoCalendario AS UNSIGNED), CAST(x.T49Periodo AS UNSIGNED), CAST(x.T49Digito AS UNSIGNED)',
        'title' => 'Vencimiento {T49Agno} dígito {T49Digito}',
    ],
];
