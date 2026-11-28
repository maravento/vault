/* SORI: helps to fill the quote and invoice forms. The server checks and computes everything again. */
/* FILE: public/assets/document.js */

(function () {
    var form = document.getElementById('document');
    if (!form) {
        return;
    }
    var items = document.getElementById('items');
    var tpl = document.getElementById('record');
    var lang = document.documentElement.lang || 'en';

    function formato(n) {
        return n.toLocaleString(lang, { maximumFractionDigits: 2 });
    }

    function buscar(type, q) {
        return fetch('/api/search?type=' + type + '&q=' + encodeURIComponent(q), { credentials: 'same-origin' })
            .then(function (r) { return r.ok ? r.json() : []; })
            .catch(function () { return []; });
    }

    // Fills a list of suggestions for an input
    function sugerir(price_list, filas, value, label) {
        price_list.innerHTML = '';
        filas.forEach(function (f) {
            var o = document.createElement('option');
            o.value = f[value];
            o.label = f[label];
            price_list.appendChild(o);
        });
    }

    function totals() {
        var total = 0;
        var vat = 0;
        items.querySelectorAll('.record').forEach(function (record) {
            var qty = parseFloat(record.querySelector('.f-qty').value) || 0;
            var value = parseFloat(record.querySelector('.f-value').value) || 0;
            var disc = parseFloat(record.querySelector('.f-disc').value) || 0;
            var rate = parseFloat(record.dataset.vat) || 0;
            var gross = qty * value;
            var sub = gross - disc;
            vat += gross - gross / (1 + rate / 100);
            total += sub;
            record.querySelector('.f-sub').textContent = formato(sub);
            record.querySelector('.f-vat').textContent = formato(rate);
        });
        document.getElementById('t-vat').textContent = formato(vat);
        document.getElementById('t-total').textContent = formato(Math.round(total));
    }

    // Loads the item of a row. When the row came back from a rejected save, the typed values stay.
    function llenar(record, conservar) {
        var item_code = record.querySelector('.f-code').value.trim();
        if (item_code === '') {
            return;
        }
        buscar('item', item_code).then(function (price_list) {
            var c = price_list.filter(function (x) { return x.code === item_code; })[0];
            var value = record.querySelector('.f-value');
            var disc = record.querySelector('.f-disc');
            if (!c) {
                record.querySelector('.f-name').textContent = '';
                record.dataset.vat = '0';
                value.readOnly = true;
                disc.readOnly = true;
                totals();
                return;
            }
            record.querySelector('.f-name').textContent = c.name;
            record.dataset.vat = c.vat;
            value.readOnly = !c.free_price;
            disc.readOnly = !c.free_discount;
            if (!conservar || !c.free_price || value.value === '') {
                value.value = c.price;
            }
            if (!c.free_discount) {
                disc.value = '0';
            }
            totals();
        });
    }

    function add() {
        var record = tpl.content.firstElementChild.cloneNode(true);
        items.appendChild(record);
        record.querySelector('.f-code').focus();
    }

    document.getElementById('add').addEventListener('click', add);

    items.addEventListener('click', function (ev) {
        if (!ev.target.classList.contains('f-remove')) {
            return;
        }
        if (items.querySelectorAll('.record').length > 1) {
            ev.target.closest('.record').remove();
            totals();
        }
    });

    items.addEventListener('input', function (ev) {
        if (ev.target.classList.contains('f-code')) {
            var q = ev.target.value.trim();
            if (q.length >= 2) {
                buscar('item', q).then(function (r) {
                    sugerir(document.getElementById('dl-item'), r, 'code', 'name');
                });
            }
        }
        totals();
    });

    items.addEventListener('change', function (ev) {
        if (ev.target.classList.contains('f-code')) {
            llenar(ev.target.closest('.record'), false);
        }
    });

    document.getElementById('party').addEventListener('input', function (ev) {
        var q = ev.target.value.trim();
        if (q.length >= 2) {
            buscar('party', q).then(function (r) {
                sugerir(document.getElementById('dl-party'), r, 'tax_id', 'name');
            });
        }
    });

    items.querySelectorAll('.record').forEach(function (record) {
        record.dataset.vat = '0';
        llenar(record, true);
    });
    totals();
})();
