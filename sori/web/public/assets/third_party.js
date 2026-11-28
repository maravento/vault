// SORI third party form: shows the names of a natural person or the company name, and only the cities of the chosen department
// FILE: public/assets/third_party.js
(function () {
    var person_type = document.getElementById('person_type');
    var department = document.getElementById('department');
    var city = document.getElementById('city');
    if (!person_type || !department || !city) {
        return;
    }

    function persons() {
        var natural = person_type.value === '0';
        document.querySelectorAll('#party .natural').forEach(function (el) { el.hidden = !natural; });
        document.querySelectorAll('#party .legal').forEach(function (el) { el.hidden = natural; });
    }

    function cities() {
        var chosen = city.options[city.selectedIndex];
        Array.prototype.forEach.call(city.options, function (op) {
            op.hidden = op.getAttribute('data-department') !== department.value;
        });
        if (!chosen || chosen.hidden) {
            for (var i = 0; i < city.options.length; i++) {
                if (!city.options[i].hidden) {
                    city.selectedIndex = i;
                    break;
                }
            }
        }
    }

    person_type.addEventListener('change', persons);
    department.addEventListener('change', cities);
    persons();
    cities();
})();
