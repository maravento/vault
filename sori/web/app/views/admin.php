<?php
// Platform administration: list of clients
// FILE: app/views/admin.php
?>
<div class="content-area">
    <h2><i class="fas fa-key"></i> <?= e(t('Clientes')) ?></h2>
    <div class="table-wrap">
    <table class="content-table">
        <thead><tr><th><?= e(t('Código')) ?></th><th><?= e(t('Cliente')) ?></th><th><?= e(t('Usuarios')) ?></th><th><?= e(t('Estado')) ?></th><th><?= e(t('Creado')) ?></th></tr></thead>
        <tbody>
        <?php foreach ($clients as $c): ?>
            <tr>
                <td><?= e($c['slug']) ?></td>
                <td><?= e($c['name']) ?></td>
                <td><?= (int) $c['users'] ?></td>
                <td><?= e(t((int) $c['active'] ? 'Activo' : 'Inactivo')) ?></td>
                <td><?= e($c['created']) ?></td>
            </tr>
        <?php endforeach; ?>
        <?php if (!$clients): ?>
            <tr><td colspan="5"><?= e(t('No hay clientes. Cree uno con la herramienta de migración.')) ?></td></tr>
        <?php endif; ?>
        </tbody>
    </table>
    </div>
</div>
