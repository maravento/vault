<?php
// SORI module registry: which modules exist and in which area they appear.
// FILE: app/modules.php

// 'grupo': business area, one tab on the home page (see views/home.php).
$modules_list = [
    ['id' => 'parties',     'group' => 'catalogs', 'name' => 'Terceros',                 'icon' => 'fa-users',                'table' => 'T12TERCERO'],
    ['id' => 'invoices',  'group' => 'sales', 'name' => 'Facturas',              'icon' => 'fa-file-invoice-dollar',  'table' => 'T604FACTURA'],
    ['id' => 'resolutions',         'group' => 'sales', 'name' => 'Resoluciones', 'icon' => 'fa-landmark',             'table' => 'T629PREFIJO'],
    ['id' => 'products',    'group' => 'catalogs', 'name' => 'Productos',                'icon' => 'fa-tags',                 'table' => 'T603CONCEPTO'],
    ['id' => 'quotes', 'group' => 'sales', 'name' => 'Cotizaciones',            'icon' => 'fa-file-lines',           'table' => 'T638COTIZACION'],
    ['id' => 'receivables',      'group' => 'treasury', 'name' => 'Cobros',                  'icon' => 'fa-hand-holding-dollar',  'table' => 'T626ABONO'],
    ['id' => 'payables',        'group' => 'treasury', 'name' => 'Pagos',        'icon' => 'fa-truck',                'table' => 'T628ABONOCOMPRA'],
    ['id' => 'purchases',      'group' => 'warehouse', 'name' => 'Compras',                  'icon' => 'fa-cart-shopping',        'table' => 'T611DOCUMENTO'],
    ['id' => 'inventory',   'group' => 'warehouse', 'name' => 'Inventario',               'icon' => 'fa-boxes-stacked',        'table' => 'T637TOTALES'],
    ['id' => 'transfers',    'group' => 'warehouse', 'name' => 'Traslados',                'icon' => 'fa-right-left',           'table' => 'T633TRASLADO'],
    ['id' => 'accounting', 'group' => 'accounting', 'name' => 'Contabilidad',             'icon' => 'fa-chart-pie',            'table' => 'T104DOCUMENTO'],
    ['id' => 'exogenous',      'group' => 'accounting', 'name' => 'Exógena',      'icon' => 'fa-file-export',          'table' => 'T53FORMATOEXOGENA'],
    ['id' => 'payroll',       'group' => 'staff', 'name' => 'Nómina',                   'icon' => 'fa-id-card',              'table' => 'T140LIQUIDACION'],
    ['id' => 'certificates', 'group' => 'services', 'name' => 'Certificados',             'icon' => 'fa-certificate',          'table' => 'T664CERTIFICADOS'],
    ['id' => 'niif',         'group' => 'accounting', 'name' => 'NIIF',                     'icon' => 'fa-scale-balanced',       'table' => 'T104DOCUMENTONIIF'],
    ['id' => 'depreciation', 'group' => 'accounting',   'name' => 'Depreciación',             'icon' => 'fa-arrow-trend-down',     'table' => 'T121DEPRECIACION'],
    ['id' => 'work_orders',      'group' => 'services',   'name' => 'Taller', 'icon' => 'fa-wrench',            'table' => 'T646ORDENTRABAJO'],
    ['id' => 'orders',      'group' => 'sales',   'name' => 'Pedidos',                  'icon' => 'fa-clipboard-list',       'table' => 'T635ORDENPEDIDO'],
    ['id' => 'schedule',      'group' => 'staff',   'name' => 'Horarios',       'icon' => 'fa-clock',                'table' => 'T640CONTROLHORARIO'],
    ['id' => 'maintenance', 'group' => 'services',  'name' => 'Mantenimiento',            'icon' => 'fa-screwdriver-wrench',   'table' => 'T683ORDENMANTENIM'],
    ['id' => 'vouchers',        'group' => 'sales',   'name' => 'Bonos',                    'icon' => 'fa-ticket',               'table' => 'T709BONO'],
    ['id' => 'loans',     'group' => 'treasury',   'name' => 'Créditos',                 'icon' => 'fa-credit-card',          'table' => 'T678CREDITO'],
    ['id' => 'collections',      'group' => 'treasury',   'name' => 'Recaudo',                  'icon' => 'fa-coins',                'table' => 'T132RECAUDO'],
    ['id' => 'reconciliation', 'group' => 'treasury',   'name' => 'Conciliación',    'icon' => 'fa-building-columns',     'table' => 'T115CONCILIACIONBANCARIA'],
    ['id' => 'requests',    'group' => 'warehouse',   'name' => 'Solicitudes',       'icon' => 'fa-file-invoice',         'table' => 'T693SOLICITACOSTO'],
    ['id' => 'tables',        'group' => 'sales',   'name' => 'Mesas',         'icon' => 'fa-utensils',             'table' => 'T817MESA'],
    ['id' => 'budget',  'group' => 'accounting',   'name' => 'Presupuesto',              'icon' => 'fa-calculator',           'table' => 'T36TIPOPLANPPTO'],
    ['id' => 'hotel',        'group' => 'services',   'name' => 'Hotel',                    'icon' => 'fa-hotel',                'table' => 'T823RESERVAHABITACION'],
    ['id' => 'calendar',   'group' => 'accounting',   'name' => 'Vencimientos',    'icon' => 'fa-calendar-days',        'table' => 'T49CALENDARIOTRIBUTARIO'],
];

return $modules_list;
