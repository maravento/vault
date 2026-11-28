/* SORI: switch between the module sheets and ask before a form that cannot be undone */
/* FILE: public/assets/sori.js */

document.querySelectorAll('form[data-confirm]').forEach(function (form) {
    form.addEventListener('submit', function (ev) {
        if (!window.confirm(form.dataset.confirm)) {
            ev.preventDefault();
        }
    });
});

document.querySelectorAll('.tab-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
        document.querySelectorAll('.tab-btn').forEach(function (b) {
            b.classList.toggle('active', b === btn);
        });
        document.querySelectorAll('.tab-panel').forEach(function (p) {
            p.hidden = p.id !== btn.dataset.tab;
        });
    });
});
