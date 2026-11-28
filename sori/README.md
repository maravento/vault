<!--
SORI documentation
FILE: sori/README.md
-->

# [SORI](https://github.com/maravento)

[![status-experimental](https://img.shields.io/badge/status-experimental-orange.svg)](https://github.com/maravento)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>SORI</b> (Integrated Operations and Resources System) is a web system for invoicing, inventory, accounting and payroll. It serves several clients from one installation. Each client has its own login and its own database, so data is never mixed. It can load a client from a legacy Access database, to move over without disruption.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>SORI</b> (Sistema de Operaciones y Recursos Integrales) es un sistema web de facturación, inventario, contabilidad y nómina. Atiende a varios clientes desde una sola instalación. Cada cliente tiene su propio acceso y su propia base de datos, por lo que los datos nunca se mezclan. Puede cargar un cliente desde una base Access anterior, para migrar sin traumatismos.
    </td>
  </tr>
</table>

[<img src="img/sori.png" width="100%" alt="SORI sign-in page in Spanish and English">](https://www.maravento.com)

<!-- markdownlint-disable MD033 -->

## REQUIREMENTS

---

### Compatibility

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Only tested on Ubuntu 24.04/26.04 LTS. Other versions or distributions are not tested and are used at your own risk.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Solo probado en Ubuntu 24.04/26.04 LTS. Otras versiones o distribuciones no están probadas y se usan bajo tu responsabilidad.
    </td>
  </tr>
</table>

### Network

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Internet access is required to install packages, and the browser requests the Font Awesome icon stylesheet from <code>cdnjs.cloudflare.com</code>. The frontend listens on <code>127.0.0.1:10600</code>, so it is not reachable from the LAN unless you change it.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Se necesita Internet para instalar paquetes, y el navegador solicita la hoja de iconos de Font Awesome a <code>cdnjs.cloudflare.com</code>. El frontend escucha en <code>127.0.0.1:10600</code>, por lo que no es accesible desde la LAN salvo que lo cambies.
    </td>
  </tr>
</table>

### Software

| Component | Description | Descripción |
|---|---|---|
| Apache 2.4 | Web server with PHP as a module. | Servidor web con PHP como módulo. |
| PHP 8.3 | With the database extension and command line. | Con la extensión de base de datos y la línea de comandos. |
| MariaDB 10.11 | One control database and one database per client. | Una base de control y una base por cliente. |
| mdbtools | Reads the legacy Access databases. | Lee las bases Access anteriores. |

> The installer adds the missing packages. Packages that are already installed are reused.
>
> El instalador agrega los paquetes que falten. Los paquetes ya instalados se reutilizan.

## REPOSITORY STRUCTURE

---

```text
sori/
├── sorisetup.sh                    # installer, updater and uninstaller
├── db/
│   ├── schema.sql                  # structure of the client database (no data)
│   └── app.sql                     # control tables: clients, users, login attempts
├── tools/
│   ├── sorimigrate.php             # loads a client from an Access database (.mdb)
│   ├── soribk.sh                   # backup of the databases and the configuration
│   └── sorienv.sh                  # reader of sori.env for the backup
├── img/
│   └── sori.png                    # sign-in page in Spanish and English
└── web/
    ├── app/                        # code, kept outside the web root
    │   ├── lib.php                 # configuration, sessions and login
    │   ├── i18n.php                # language of the browser: Spanish or English
    │   ├── lang_en.php             # English text of the interface
    │   ├── modules.php             # list of modules and their area
    │   ├── screens.php             # what each module lists, searches and opens
    │   ├── write.php               # who may write, the lookups, the shared checks and the quote save
    │   ├── invoice.php             # the sales invoice save and cancel: rules, stock and accounting
    │   ├── receipt.php             # the payment received on a credit invoice
    │   ├── sales_return.php        # the customer return on an invoice
    │   ├── purchase.php            # the purchase from a supplier
    │   ├── purchase_return.php     # the return of goods to a supplier
    │   ├── supplier_payment.php    # the payment made to a supplier on a credit purchase
    │   ├── third_party.php         # create and edit a client, supplier or employee
    │   ├── product.php             # create and edit a product or service with its prices
    │   └── views/                  # pages
    └── public/                     # web root
        ├── index.php               # single entry point
        └── assets/                 # stylesheet and scripts
```

### Additional Installed Paths

```text
etc/
├── apache2/
│   ├── sites-available/
│   │   └── sori.conf               # site on 127.0.0.1:10600 [0644 root:root]
│   └── sites-enabled/
│       └── sori.conf               # link to ../sites-available/sori.conf
└── sori/                           # configuration directory [0750 root:www-data]
    └── sori.env                    # generated configuration [0640 root:www-data]

var/
└── www/
    └── sori/                       # installed code [0755 root:root]
        ├── app/
        ├── db/
        ├── public/
        └── tools/
```

## HOW TO USE

---

| Command | Description | Descripción |
|---|---|---|
| `sudo bash sorisetup.sh` | Show the menu. | Muestra el menú. |
| `sudo bash sorisetup.sh --install` | Install SORI. | Instala SORI. |
| `sudo bash sorisetup.sh --update` | Install the missing packages and replace the code. Settings and client data are kept. | Instala los paquetes que falten y reemplaza el código. La configuración y los datos de los clientes se conservan. |
| `sudo bash sorisetup.sh --uninstall` | Remove SORI. | Desinstala SORI. |
| `sudo php /var/www/sori/tools/sorimigrate.php --client CODE --name "NAME" --mdb FILE.mdb` | Create a client and copy all its data from a legacy Access database, as it is. | Crea un cliente y copia todos sus datos desde una base Access anterior, tal cual. |
| `sudo php /var/www/sori/tools/sorimigrate.php --client CODE --name "NAME" --mdb FILE.mdb --anonymize` | For demonstrations only: replace third-party identity and contact data, and skip the legacy logins, audit log and report tables. | Solo para demostraciones: reemplaza los datos de identidad y contacto de terceros, y omite los accesos anteriores, el registro de auditoría y las tablas de informes. |
| `sudo php /var/www/sori/tools/sorimigrate.php --client CODE --name "NAME" --mdb FILE.mdb --replace` | Delete the client database first and load it again. | Borra primero la base del cliente y la carga de nuevo. |
| `sudo bash /var/www/sori/tools/soribk.sh` | Back up the databases and the configuration now. | Respalda ahora las bases de datos y la configuración. |
| `sudo apt-get remove --auto-remove mdbtools` | Remove the Access reader after the migrations are done. | Retira el lector de Access cuando terminen las migraciones. |

> The installer prints one line for each fact, with the same text in `sorisetup.log` next to the script. The password of the platform user `admin` is shown once.
> Each migrated client gets its own user, named like the client code, and its password is also shown once.
> Open `http://127.0.0.1:10600` and sign in.
>
> El instalador muestra una línea por cada hecho, con el mismo texto en `sorisetup.log`, junto al script. La contraseña del usuario de plataforma `admin` se muestra una sola vez.
> Cada cliente migrado recibe su propio usuario, con el nombre del código del cliente, y su contraseña también se muestra una sola vez.
> Abre `http://127.0.0.1:10600` e inicia sesión.

> **⚠️ WARNING -- Migration data:** `--anonymize` replaces identification numbers, names, addresses, phones and emails of third parties, and blanks the keys, tokens and licenses of the company. Free-text fields such as invoice notes are not scrubbed. Without `--anonymize`, the data is copied as it is, including real identification numbers.
>
> **⚠️ WARNING -- Datos de migración:** `--anonymize` reemplaza números de identificación, nombres, direcciones, teléfonos y correos de terceros, y deja en blanco las claves, tokens y licencias de la empresa. Los campos de texto libre, como las notas de factura, no se depuran. Sin `--anonymize`, los datos se copian tal cual, incluidos los números de identificación reales.

## SCOPE

---

| SCOPE | ALCANCE |
|---|---|
| <ul><li>Several clients in one installation, each with its own login and its own database.</li><li>A home page with one tab per area: Catalogs, Sales, Warehouse, Treasury, Accounting, Staff and Services. The interface is in Spanish when the browser prefers Spanish and in English for any other language.</li><li>The 17 modules with a screen list and search their records, and 16 of them open each record with its related rows, such as an invoice with its items. Only users with the editor role can write, and so far only quotes, sales invoices (and their cancellation), payments received, customer returns, purchases and returns to suppliers; everything else is read only.</li><li>The other 12 modules open an under-construction page with their record count.</li><li>Loading one company from a legacy Access database, with optional anonymization.</li><li>A platform user that lists the clients without seeing their data.</li></ul> | <ul><li>Varios clientes en una instalación, cada uno con su acceso y su base de datos.</li><li>Una página de inicio con una pestaña por área: Catálogos, Ventas, Almacén, Tesorería, Contabilidad, Personal y Servicios. La interfaz está en español si el navegador prefiere español y en inglés para cualquier otro idioma.</li><li>Los 17 módulos con pantalla listan y buscan sus registros, y 16 de ellos abren cada registro con sus filas relacionadas, como una factura con sus ítems. Solo los usuarios con el rol editor pueden escribir, y por ahora solo cotizaciones, facturas de venta (y su anulación), abonos recibidos, devoluciones de clientes, compras y devoluciones a proveedores; todo lo demás es de solo lectura.</li><li>Los otros 12 módulos abren una página en construcción con su cantidad de registros.</li><li>Carga de una empresa desde una base Access anterior, con anonimización opcional.</li><li>Un usuario de plataforma que lista los clientes sin ver sus datos.</li></ul> |
| **OUT OF SCOPE** | **FUERA DE ALCANCE** |
| <ul><li>Editing and deleting records, the electronic invoicing flow (including electronic credit notes), accounting entries other than those of sales, payments received, returns and purchases, and payroll settlement: not implemented yet. Quotes, sales invoices, payments received, customer returns, purchases and returns to suppliers are the only records that can be created.</li><li>Screens to create or edit clients and users: they are created by the installer and the migration tool.</li><li>Password recovery.</li><li>HTTPS: the tunnel provides it.</li><li>Signing in with the legacy users: they are copied as data only.</li><li>The saved queries of the legacy database, which feed its reports: they are not migrated yet.</li><li>Dates and amounts are kept as text, as in the legacy database.</li></ul> | <ul><li>Editar y eliminar registros, el flujo de facturación electrónica (incluidas las notas crédito electrónicas), asientos contables distintos de los de ventas, abonos recibidos, devoluciones y compras, y liquidación de nómina: aún no implementados. Las cotizaciones, las facturas de venta, los abonos recibidos, las devoluciones de clientes, las compras y las devoluciones a proveedores son los únicos registros que se pueden crear.</li><li>Pantallas para crear o editar clientes y usuarios: los crean el instalador y la herramienta de migración.</li><li>Recuperación de contraseñas.</li><li>HTTPS: lo aporta el túnel.</li><li>Iniciar sesión con los usuarios anteriores: se copian solo como datos.</li><li>Las consultas guardadas de la base anterior, que alimentan sus informes: aún no se migran.</li><li>Las fechas y los importes se conservan como texto, igual que en la base anterior.</li></ul> |

## HOW IT WORKS

---

### Clients and data separation

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>The control database <code>sori</code> holds the clients, their users and the failed login attempts.</li><li>Each client has its own database, named <code>sori_</code> followed by the client code. It has the same structure as the legacy database.</li><li>At login, the user is tied to one client. From then on, every page reads only that client's database.</li><li>A deactivated client cannot sign in.</li><li>The platform user <code>admin</code> belongs to no client. It only sees the list of clients.</li><li>The application connects to the database with a user that can read and write data, not change structure.</li></ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>La base de control <code>sori</code> guarda los clientes, sus usuarios y los intentos de acceso fallidos.</li><li>Cada cliente tiene su propia base, llamada <code>sori_</code> seguido del código del cliente. Tiene la misma estructura que la base anterior.</li><li>Al iniciar sesión, el usuario queda ligado a un cliente. Desde ese momento, cada página lee solo la base de ese cliente.</li><li>Un cliente desactivado no puede iniciar sesión.</li><li>El usuario de plataforma <code>admin</code> no pertenece a ningún cliente. Solo ve la lista de clientes.</li><li>La aplicación se conecta a la base con un usuario que puede leer y escribir datos, no cambiar la estructura.</li></ul>
    </td>
  </tr>
</table>

### Login protection

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>Passwords are stored hashed, never in plain text.</li><li>After 5 failed attempts from the same address, sign-in is blocked for 10 minutes.</li><li>Forms carry a token that prevents requests sent from other sites.</li><li>A session expires after 2 hours without activity.</li><li>Behind the Cloudflare tunnel, the visitor address is taken from the tunnel header.</li><li>The limits are in <code>/etc/sori/sori.env</code>: <code>SESSION_TIMEOUT</code> (seconds, 7200), <code>LOGIN_MAX_ATTEMPTS</code> (5), <code>LOGIN_WINDOW_MINUTES</code> (10), <code>LOGIN_ATTEMPTS_KEEP_DAYS</code> (1) and <code>DETAIL_ROWS_LIMIT</code> (rows per child table, 500). The installer writes these defaults. The update never touches <code>sori.env</code>; a missing key uses its default.</li><li>The installer also writes <code>TIMEZONE</code>, the time zone of the server, read with <code>timedatectl</code>. Every date Sori writes follows it. If the installer cannot read the time zone, it stops. A missing key uses UTC.</li></ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>Las contraseñas se guardan cifradas, nunca en texto plano.</li><li>Tras 5 intentos fallidos desde la misma dirección, el acceso se bloquea 10 minutos.</li><li>Los formularios llevan un token que impide solicitudes enviadas desde otros sitios.</li><li>Una sesión caduca tras 2 horas sin actividad.</li><li>Detrás del túnel de Cloudflare, la dirección del visitante se toma del encabezado del túnel.</li><li>Los límites están en <code>/etc/sori/sori.env</code>: <code>SESSION_TIMEOUT</code> (segundos, 7200), <code>LOGIN_MAX_ATTEMPTS</code> (5), <code>LOGIN_WINDOW_MINUTES</code> (10), <code>LOGIN_ATTEMPTS_KEEP_DAYS</code> (1) y <code>DETAIL_ROWS_LIMIT</code> (filas por tabla hija, 500). El instalador escribe estos valores por defecto. La actualización nunca toca <code>sori.env</code>; una clave ausente usa su valor por defecto.</li><li>El instalador escribe además <code>TIMEZONE</code>, la zona horaria del servidor, leída con <code>timedatectl</code>. Todas las fechas que Sori escribe la siguen. Si el instalador no puede leer la zona horaria, se detiene. Una clave ausente usa UTC.</li></ul>
    </td>
  </tr>
</table>

### Writing records

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>A user can write only if its role is <code>editor</code>. Every other user, and the platform user, can only read.</li><li>To grant the role: <code>UPDATE sori_users SET role='editor' WHERE username='NAME';</code> in the control database.</li><li>The <i>Quotes</i> module shows a <i>New quote</i> button to an editor: prefix, date, third party, payment method, salesperson and items.</li><li>The server computes every total from the items. Nothing comes from the browser: an item's price changes only when the item allows it, and a discount is accepted only when the item allows discounts.</li><li>The quote is written in the same tables and the same text formats as the legacy database, so the legacy program can read it. The number is the next one of its prefix, and two users never get the same one.</li><li>Each quote is saved in one transaction with a line in the audit table. If anything fails, nothing is saved.</li><li>The <i>Invoices</i> module has a <i>New invoice</i> button with the same form. Before saving, the server applies the rules the company has switched on: a locked accounting month or day, the credit limit, overdue invoices, selling below cost and stock.</li><li>The invoice number is the next one of its prefix. When the prefix has resolution ranges, the number must fall inside a current range, and a notice appears when few numbers are left.</li><li>Saving an invoice also updates the stock totals. When the company posts online, it creates the accounting document with the same number: income, tax, cost, inventory and the cash, card or credit account. Any other payment method has no verified account and is refused. A company that posts in batches gets no document.</li><li>The invoice is not sent to the tax authority: the electronic invoicing flow is not implemented.</li><li>An invoice that has no payments, no returns and no electronic number can be cancelled from its page. It stays listed with its lines and total, marked as cancelled; the stock is restored and its accounting document is deleted. A locked accounting month blocks it.</li><li>On a credit invoice, <i>Register payment</i> opens the payment form: date, amount, account and payment prefix. The amount cannot exceed the balance, which is the total less payments and returns. The payment number is the next one of its payment prefix and it updates the amount paid. When the company posts online and the prefix has an accounting setup, the payment creates its document; otherwise it is saved and a notice says so. Discounts and withholdings on a payment are not supported.</li><li>On an invoice, <i>Customer return</i> asks for the date, the payment method and the quantity of each item to give back. It cannot exceed what was sold and not yet returned. The return is numbered by its type, the items go back into the stock and, when the company posts online, the accounting document debits the sales returns and the tax and credits the payment method. An invoice sent electronically, or with a discount on the returned line, is refused.</li><li>The <i>Purchases</i> module has a <i>New purchase</i> button: purchase type, date, supplier, the supplier's invoice number, payment method, optional withholding tax percentage and up to eight items with quantity, unit cost and tax. The same supplier invoice cannot be entered twice. The items enter the stock, the last purchase cost of each item is updated and, when the company posts online, the accounting document debits the stock accounts and the tax and credits the supplier account less the withholding. Discounts, freight, other withholdings and the average cost are not supported.</li><li>On a purchase, <i>Return to supplier</i> gives back part or all of the items. It cannot exceed what was bought and not yet returned, or the stock on hand. The items leave the stock and the accounting document mirrors the purchase, giving the withholding back.</li></ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>Un usuario puede escribir solo si su rol es <code>editor</code>. Cualquier otro usuario, y el usuario de plataforma, solo puede leer.</li><li>Para dar el rol: <code>UPDATE sori_users SET role='editor' WHERE username='NOMBRE';</code> en la base de control.</li><li>El módulo <i>Cotizaciones</i> muestra a un editor el botón <i>Nueva cotización</i>: prefijo, fecha, tercero, forma de pago, vendedor e ítems.</li><li>El servidor calcula todos los totales a partir de los ítems. Nada viene del navegador: el precio de un ítem cambia solo cuando el ítem lo permite, y un descuento se acepta solo cuando el ítem admite descuentos.</li><li>La cotización se escribe en las mismas tablas y con los mismos formatos de texto que la base anterior, así que el programa anterior puede leerla. El número es el siguiente de su prefijo, y dos usuarios nunca reciben el mismo.</li><li>Cada cotización se guarda en una sola transacción con una línea en la tabla de auditoría. Si algo falla, no se guarda nada.</li><li>El módulo <i>Facturas</i> tiene un botón <i>Nueva factura</i> con el mismo formulario. Antes de guardar, el servidor aplica las reglas que la empresa tiene activas: mes o día contable bloqueado, cupo de crédito, facturas vencidas, venta bajo el costo y existencias.</li><li>El número de la factura es el siguiente de su prefijo. Cuando el prefijo tiene rangos de resolución, el número debe caer dentro de un rango vigente, y aparece un aviso cuando quedan pocos números.</li><li>Guardar una factura también actualiza los totales de inventario. Cuando la empresa contabiliza en línea, crea el documento contable con el mismo número: ingreso, impuesto, costo, inventario y la cuenta de caja, de banco o de crédito. Cualquier otra forma de pago no tiene una cuenta verificada y se rechaza. Una empresa que contabiliza por lotes no recibe documento.</li><li>La factura no se envía a la autoridad tributaria: el flujo de facturación electrónica no está implementado.</li><li>Una factura sin abonos, sin devoluciones y sin número electrónico se puede anular desde su página. Sigue en el listado con sus líneas y su total, marcada como anulada; las existencias se restituyen y su documento contable se elimina. Un mes contable bloqueado lo impide.</li><li>En una factura a crédito, <i>Registrar abono</i> abre el formulario del abono: fecha, valor, cuenta y prefijo del abono. El valor no puede superar el saldo, que es el total menos abonos y devoluciones. El número del abono es el siguiente de su prefijo y actualiza el valor pagado. Cuando la empresa contabiliza en línea y el prefijo tiene configuración contable, el abono crea su documento; de lo contrario se guarda y un aviso lo indica. Los descuentos y las retenciones en un abono no están soportados.</li><li>En una factura, <i>Devolución de cliente</i> pide la fecha, la forma de pago y la cantidad de cada ítem a devolver. No puede superar lo vendido y aún no devuelto. La devolución se numera por su tipo, los ítems vuelven a las existencias y, cuando la empresa contabiliza en línea, el documento contable debita las devoluciones en ventas y el impuesto y acredita la forma de pago. Se rechaza una factura enviada electrónicamente, o con descuento en la línea devuelta.</li><li>El módulo <i>Compras</i> tiene un botón <i>Nueva compra</i>: tipo de compra, fecha, proveedor, número de la factura del proveedor, forma de pago, porcentaje opcional de retención en la fuente y hasta ocho ítems con cantidad, costo unitario e impuesto. La misma factura de un proveedor no se puede ingresar dos veces. Los ítems entran a las existencias, se actualiza el último costo de compra de cada ítem y, cuando la empresa contabiliza en línea, el documento contable debita las cuentas de inventario y el impuesto y acredita la cuenta del proveedor menos la retención. Los descuentos, el flete, las otras retenciones y el costo promedio no están soportados.</li><li>En una compra, <i>Devolución a proveedor</i> devuelve parte o todos los ítems. No puede superar lo comprado y aún no devuelto, ni las existencias disponibles. Los ítems salen de las existencias y el documento contable es el reflejo de la compra, devolviendo la retención.</li></ul>
    </td>
  </tr>
</table>

### Modules

| Area | Description | Descripción |
|---|---|---|
| Catalogs | Third parties, Products | Terceros, Productos |
| Sales | Invoices, Resolutions, Quotations, Orders, Tables, Vouchers | Facturas, Resoluciones, Cotizaciones, Pedidos, Mesas, Bonos |
| Warehouse | Purchases, Inventory, Transfers, Requests | Compras, Inventario, Traslados, Solicitudes |
| Treasury | Receivables, Payables, Collections, Loans, Reconciliation | Cobros, Pagos, Recaudo, Créditos, Conciliación |
| Accounting | Accounting, IFRS, Exogenous, Depreciation, Budget, Due dates | Contabilidad, NIIF, Exógena, Depreciación, Presupuesto, Vencimientos |
| Staff | Payroll, Schedules | Nómina, Horarios |
| Services | Workshop, Maintenance, Hotel, Certificates | Taller, Mantenimiento, Hotel, Certificados |

### Migration

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>Migration is offered only for clients that have an Access database (<code>.mdb</code>). No other source is supported.</li><li>Command: <code>sudo php /var/www/sori/tools/sorimigrate.php --client CODE --name "NAME" --mdb FILE.mdb</code></li><li>It creates the client database with the full legacy structure, 305 tables, and loads the rows of the chosen company. Rows of other companies in the same file are skipped. Use <code>--company</code> to pick the company; the default is 1.</li><li>Every table is copied as it is, including the legacy users, the audit log and the report work tables. Nothing is left out.</li><li>With <code>--anonymize</code>, every identification number is replaced by a new one. The same number is used in every table, so invoices still match their third parties. The legacy users, the audit log and the report tables are skipped.</li><li>If a row, a column or a table cannot be loaded, it is reported and the exit status is not zero.</li><li>It prints the rows loaded per table.</li><li>If the client database already exists, the tool stops. <code>--replace</code> deletes it first.</li><li>It creates the client user and shows its password once.</li></ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>La migración se ofrece solo para clientes que tengan una base Access (<code>.mdb</code>). No se admite ningún otro origen.</li><li>Comando: <code>sudo php /var/www/sori/tools/sorimigrate.php --client CODE --name "NAME" --mdb FILE.mdb</code></li><li>Crea la base del cliente con toda la estructura anterior, 305 tablas, y carga las filas de la empresa elegida. Las filas de otras empresas del mismo archivo se omiten. Usa <code>--company</code> para elegir la empresa; por defecto es 1.</li><li>Cada tabla se copia tal cual, incluidos los usuarios anteriores, el registro de auditoría y las tablas de trabajo de informes. No se omite nada.</li><li>Con <code>--anonymize</code>, cada número de identificación se reemplaza por uno nuevo. Se usa el mismo número en todas las tablas, así que las facturas siguen coincidiendo con sus terceros. Se omiten los usuarios anteriores, el registro de auditoría y las tablas de informes.</li><li>Si una fila, una columna o una tabla no se puede cargar, se informa y el código de salida no es cero.</li><li>Muestra las filas cargadas por tabla.</li><li>Si la base del cliente ya existe, la herramienta se detiene. <code>--replace</code> la borra primero.</li><li>Crea el usuario del cliente y muestra su contraseña una sola vez.</li></ul>
    </td>
  </tr>
</table>

### Backup

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>The backup saves a dump of the control database and of every client database, the folder <code>/etc/sori</code>, the Apache site and the installed code, in one zip file.</li><li>The copies go to <code>/etc/bak/sori</code>. The three most recent are kept.</li><li>A monthly cron entry, <code>/etc/cron.d/sori</code>, runs it. The update runs it before it replaces the code and stops if it fails. The uninstall removes the cron entry and keeps the copies.</li><li>The key <code>BACKUP_DIR=/etc/bak/sori</code> in <code>sori.env</code> is required. Without it the backup refuses to run. The installer writes it; the update never touches <code>sori.env</code>, so on an existing installation add the key yourself.</li><li>To restore a database, unzip the copy and load its dump with <code>mariadb &lt; FILE.sql</code>.</li></ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>El respaldo guarda un volcado de la base de control y de cada base de cliente, la carpeta <code>/etc/sori</code>, el sitio de Apache y el código instalado, en un solo archivo zip.</li><li>Las copias van a <code>/etc/bak/sori</code>. Se conservan las tres más recientes.</li><li>Una entrada mensual de cron, <code>/etc/cron.d/sori</code>, lo ejecuta. La actualización lo ejecuta antes de reemplazar el código y se detiene si falla. La desinstalación quita la entrada de cron y conserva las copias.</li><li>La clave <code>BACKUP_DIR=/etc/bak/sori</code> en <code>sori.env</code> es obligatoria. Sin ella el respaldo no se ejecuta. El instalador la escribe; la actualización nunca toca <code>sori.env</code>, así que en una instalación existente agrega la clave tú.</li><li>Para restaurar una base, descomprime la copia y carga su volcado con <code>mariadb &lt; ARCHIVO.sql</code>.</li></ul>
    </td>
  </tr>
</table>

### Installation

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>It asks nothing. It installs the missing packages: <code>apache2</code>, <code>libapache2-mod-php</code>, <code>php-cli</code>, <code>php-mysql</code>, <code>mariadb-server</code>, <code>mariadb-client</code>, <code>mdbtools</code>, <code>curl</code>, <code>zip</code> and <code>cron</code>.</li><li>It creates <code>/var/www/sori</code> for the code and <code>/etc/sori</code> for the configuration.</li><li>It adds the Apache site <code>sori.conf</code>, listening only on <code>127.0.0.1:10600</code>. The existing Apache and MariaDB settings are kept, and Apache is reloaded.</li><li>It creates the database <code>sori</code> and the database user <code>sori</code>, which can read and write data but not change the structure.</li><li>It creates the platform user <code>admin</code>.</li><li>It stops if the port is taken or if SORI is already installed.</li></ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>No pregunta nada. Instala los paquetes que falten: <code>apache2</code>, <code>libapache2-mod-php</code>, <code>php-cli</code>, <code>php-mysql</code>, <code>mariadb-server</code>, <code>mariadb-client</code>, <code>mdbtools</code>, <code>curl</code>, <code>zip</code> y <code>cron</code>.</li><li>Crea <code>/var/www/sori</code> para el código y <code>/etc/sori</code> para la configuración.</li><li>Agrega el sitio de Apache <code>sori.conf</code>, que escucha solo en <code>127.0.0.1:10600</code>. Se conservan los ajustes existentes de Apache y MariaDB, y se recarga Apache.</li><li>Crea la base <code>sori</code> y el usuario de base de datos <code>sori</code>, que puede leer y escribir datos pero no cambiar la estructura.</li><li>Crea el usuario de plataforma <code>admin</code>.</li><li>Se detiene si el puerto está ocupado o si SORI ya está instalado.</li></ul>
    </td>
  </tr>
</table>

### Update and uninstall

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>The update installs the missing packages, replaces the code in <code>/var/www/sori</code> and reloads Apache. It keeps <code>sori.env</code> and all databases.</li><li>The uninstall removes <code>/var/www/sori</code>, <code>/etc/sori</code> and the Apache site, after you confirm. The answer is no by default.</li><li>The databases are deleted only if you confirm a second time. The answer is no by default.</li><li>The packages are never removed.</li></ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>La actualización instala los paquetes que falten, reemplaza el código en <code>/var/www/sori</code> y recarga Apache. Conserva <code>sori.env</code> y todas las bases.</li><li>La desinstalación elimina <code>/var/www/sori</code>, <code>/etc/sori</code> y el sitio de Apache, tras tu confirmación. La respuesta por defecto es no.</li><li>Las bases solo se borran si confirmas por segunda vez. La respuesta por defecto es no.</li><li>Los paquetes nunca se eliminan.</li></ul>
    </td>
  </tr>
</table>

## ⚠️ WARNING: NETWORK ACCESS

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      This project is designed for use on a local network (LAN). It does not include the security hardening needed for direct exposure to the internet. If internet access is required, an on-demand tunnel is recommended instead of opening ports directly. This enables access when needed without leaving the server permanently exposed.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Este proyecto está diseñado para usarse en una red local (LAN). No cuenta con las medidas de seguridad necesarias para exponerlo directamente a Internet. Si se requiere acceso desde Internet, se recomienda utilizar un túnel bajo demanda en lugar de abrir puertos directamente. Así, el acceso se habilita cuando hace falta y el servidor no queda expuesto permanentemente.
    </td>
  </tr>
</table>

**Optional tunnel:**
- [Cloudflare Tunnel with Zero Trust Recommended](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/cftunnel.sh)

## NOTICE

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <strong>This repository</strong>
      <ul>
        <li>May include third-party components.</li>
        <li>Does not accept Pull Requests. Changes must be proposed via Issues.</li>
        <li>This project does not support backward compatibility. New versions may require configuration changes or reinstallation.</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <strong>Este repositorio</strong>
      <ul>
        <li>Puede incluir componentes de terceros.</li>
        <li>No acepta Pull Requests. Los cambios deben proponerse mediante Issues.</li>
        <li>Este proyecto no soporta retrocompatibilidad. Las nuevas versiones pueden requerir cambios de configuración o una reinstalación.</li>
      </ul>
    </td>
  </tr>
</table>

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
