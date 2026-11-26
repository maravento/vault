/* SORI: switch between the module sheets */
/* FILE: public/assets/sori.js */

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
