<?php
// SORI module registry: which modules exist and in which area they appear.
// FILE: app/modules.php

// 'grupo': business area, one tab on the home page (see views/home.php).
$modulos = [
    ['id' => 'terceros',     'grupo' => 'catalogos', 'nombre' => 'Terceros',                 'icono' => 'fa-users',                'tabla' => 'T12TERCERO'],
    ['id' => 'facturacion',  'grupo' => 'ventas', 'nombre' => 'Facturas',              'icono' => 'fa-file-invoice-dollar',  'tabla' => 'T604FACTURA'],
    ['id' => 'dian',         'grupo' => 'ventas', 'nombre' => 'Resoluciones', 'icono' => 'fa-landmark',             'tabla' => 'T629PREFIJO'],
    ['id' => 'conceptos',    'grupo' => 'catalogos', 'nombre' => 'Productos',                'icono' => 'fa-tags',                 'tabla' => 'T603CONCEPTO'],
    ['id' => 'cotizaciones', 'grupo' => 'ventas', 'nombre' => 'Cotizaciones',            'icono' => 'fa-file-lines',           'tabla' => 'T638COTIZACION'],
    ['id' => 'cartera',      'grupo' => 'tesoreria', 'nombre' => 'Cobros',                  'icono' => 'fa-hand-holding-dollar',  'tabla' => 'T626ABONO'],
    ['id' => 'pagar',        'grupo' => 'tesoreria', 'nombre' => 'Pagos',        'icono' => 'fa-truck',                'tabla' => 'T628ABONOCOMPRA'],
    ['id' => 'compras',      'grupo' => 'almacen', 'nombre' => 'Compras',                  'icono' => 'fa-cart-shopping',        'tabla' => 'T611DOCUMENTO'],
    ['id' => 'inventario',   'grupo' => 'almacen', 'nombre' => 'Inventario',               'icono' => 'fa-boxes-stacked',        'tabla' => 'T637TOTALES'],
    ['id' => 'traslados',    'grupo' => 'almacen', 'nombre' => 'Traslados',                'icono' => 'fa-right-left',           'tabla' => 'T633TRASLADO'],
    ['id' => 'contabilidad', 'grupo' => 'contabilidad', 'nombre' => 'Contabilidad',             'icono' => 'fa-chart-pie',            'tabla' => 'T104DOCUMENTO'],
    ['id' => 'exogena',      'grupo' => 'contabilidad', 'nombre' => 'Exógena',      'icono' => 'fa-file-export',          'tabla' => 'T53FORMATOEXOGENA'],
    ['id' => 'nomina',       'grupo' => 'personal', 'nombre' => 'Nómina',                   'icono' => 'fa-id-card',              'tabla' => 'T140LIQUIDACION'],
    ['id' => 'certificados', 'grupo' => 'servicios', 'nombre' => 'Certificados',             'icono' => 'fa-certificate',          'tabla' => 'T664CERTIFICADOS'],
    ['id' => 'niif',         'grupo' => 'contabilidad', 'nombre' => 'NIIF',                     'icono' => 'fa-scale-balanced',       'tabla' => 'T104DOCUMENTONIIF'],
    ['id' => 'depreciacion', 'grupo' => 'contabilidad',   'nombre' => 'Depreciación',             'icono' => 'fa-arrow-trend-down',     'tabla' => 'T121DEPRECIACION'],
    ['id' => 'ordenes',      'grupo' => 'servicios',   'nombre' => 'Taller', 'icono' => 'fa-wrench',            'tabla' => 'T646ORDENTRABAJO'],
    ['id' => 'pedidos',      'grupo' => 'ventas',   'nombre' => 'Pedidos',                  'icono' => 'fa-clipboard-list',       'tabla' => 'T635ORDENPEDIDO'],
    ['id' => 'horario',      'grupo' => 'personal',   'nombre' => 'Horarios',       'icono' => 'fa-clock',                'tabla' => 'T640CONTROLHORARIO'],
    ['id' => 'mantenimiento', 'grupo' => 'servicios',  'nombre' => 'Mantenimiento',            'icono' => 'fa-screwdriver-wrench',   'tabla' => 'T683ORDENMANTENIM'],
    ['id' => 'bonos',        'grupo' => 'ventas',   'nombre' => 'Bonos',                    'icono' => 'fa-ticket',               'tabla' => 'T709BONO'],
    ['id' => 'creditos',     'grupo' => 'tesoreria',   'nombre' => 'Créditos',                 'icono' => 'fa-credit-card',          'tabla' => 'T678CREDITO'],
    ['id' => 'recaudo',      'grupo' => 'tesoreria',   'nombre' => 'Recaudo',                  'icono' => 'fa-coins',                'tabla' => 'T132RECAUDO'],
    ['id' => 'conciliacion', 'grupo' => 'tesoreria',   'nombre' => 'Conciliación',    'icono' => 'fa-building-columns',     'tabla' => 'T115CONCILIACIONBANCARIA'],
    ['id' => 'solicitud',    'grupo' => 'almacen',   'nombre' => 'Solicitudes',       'icono' => 'fa-file-invoice',         'tabla' => 'T693SOLICITACOSTO'],
    ['id' => 'mesas',        'grupo' => 'ventas',   'nombre' => 'Mesas',         'icono' => 'fa-utensils',             'tabla' => 'T817MESA'],
    ['id' => 'presupuesto',  'grupo' => 'contabilidad',   'nombre' => 'Presupuesto',              'icono' => 'fa-calculator',           'tabla' => 'T36TIPOPLANPPTO'],
    ['id' => 'hotel',        'grupo' => 'servicios',   'nombre' => 'Hotel',                    'icono' => 'fa-hotel',                'tabla' => 'T823RESERVAHABITACION'],
    ['id' => 'calendario',   'grupo' => 'contabilidad',   'nombre' => 'Vencimientos',    'icono' => 'fa-calendar-days',        'tabla' => 'T49CALENDARIOTRIBUTARIO'],
];

return $modulos;
